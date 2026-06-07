local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local remoteFolder = ReplicatedStorage:WaitForChild("LootRemotes")
local interactionRemote = remoteFolder:WaitForChild("LootInteraction")

-- RemoteEvent das acoes que nao dependem de uma caixa (Tab, equipar, dropar, pegar do chao).
-- Voce DEVE criar este RemoteEvent manualmente em ReplicatedStorage > LootRemotes.
local inventoryRemote = remoteFolder:WaitForChild("InventoryRemote")

local LOOT_TAG = "LootContainer"
local DROPPED_TAG = "DroppedItem"
local LOOT_FOLDER_NAME = "Loot"
local DEFAULT_TITLE = "Loot"
local INVENTORY_TITLE = "Inventario"
local OPEN_SOUND_ID = "rbxassetid://115636166700655"
local CLOSE_SOUND_ID = "rbxassetid://140470748655921"
local TAKE_SOUND_ID = ""
local LOOT_SOUND_VOLUME = 0.6
local MAX_LOOT_DISTANCE = 22
local MAX_PICKUP_DISTANCE = 16
local MAX_INVENTORY_SLOTS = 24

-- Pasta opcional em ReplicatedStorage com modelos personalizados dos itens:
--   ItemAssets/Tools/<NomeDoItem>       -> Tool clonada ao equipar
--   ItemAssets/WorldModels/<NomeDoItem> -> Model/Part clonado ao dropar
local itemAssets = ReplicatedStorage:FindFirstChild("ItemAssets")

-- Pasta no Workspace para organizar os itens dropados.
local worldItemsFolder = Workspace:FindFirstChild("DroppedItems")
if not worldItemsFolder then
	worldItemsFolder = Instance.new("Folder")
	worldItemsFolder.Name = "DroppedItems"
	worldItemsFolder.Parent = Workspace
end

-- Inventario de cada jogador guardado em memoria: [player] = { [itemName] = count }
local inventories = {}

local function getInventory(player)
	local inventory = inventories[player]
	if not inventory then
		inventory = {}
		inventories[player] = inventory
	end

	return inventory
end

local function getLootPart(lootInstance)
	if lootInstance:IsA("BasePart") then
		return lootInstance
	end

	if lootInstance:IsA("Model") then
		return lootInstance.PrimaryPart or lootInstance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function isLootInstance(instance)
	return instance and CollectionService:HasTag(instance, LOOT_TAG)
end

local function normalizeSoundId(soundId)
	if typeof(soundId) == "number" then
		return "rbxassetid://" .. soundId
	end

	if typeof(soundId) ~= "string" or soundId == "" then
		return nil
	end

	if string.find(soundId, "rbxassetid://", 1, true) then
		return soundId
	end

	return "rbxassetid://" .. soundId
end

local function getLootFolder(lootInstance)
	return lootInstance:FindFirstChild(LOOT_FOLDER_NAME)
end

local function sortedItemList(itemMap)
	local items = {}
	for name, count in pairs(itemMap) do
		local rounded = math.floor(count)
		if rounded > 0 then
			table.insert(items, { name = name, count = rounded })
		end
	end

	table.sort(items, function(a, b)
		return a.name < b.name
	end)

	return items
end

local function getLootItems(lootInstance)
	local itemMap = {}
	local folder = getLootFolder(lootInstance)
	if not folder then
		return {}
	end

	for _, entry in ipairs(folder:GetChildren()) do
		if entry:IsA("IntValue") or entry:IsA("NumberValue") then
			local count = math.floor(entry.Value)
			if count > 0 then
				itemMap[entry.Name] = count
			end
		end
	end

	return sortedItemList(itemMap)
end

local function countDistinctItems(inventory)
	local distinct = 0
	for _, count in pairs(inventory) do
		if math.floor(count) > 0 then
			distinct += 1
		end
	end

	return distinct
end

local function getLootState(lootInstance)
	return {
		title = lootInstance:GetAttribute("Title") or DEFAULT_TITLE,
		items = getLootItems(lootInstance),
	}
end

local function getInventoryState(player)
	return {
		title = INVENTORY_TITLE,
		items = sortedItemList(getInventory(player)),
	}
end

-- Envia o inventario para o cliente (usado pela UI de inventario standalone).
local function sendInventoryUpdate(player, errorMessage)
	inventoryRemote:FireClient(player, "Update", getInventoryState(player), errorMessage)
end

local function sendLootState(player, lootInstance, errorMessage, soundId)
	interactionRemote:FireClient(
		player,
		"State",
		lootInstance,
		getLootState(lootInstance),
		getInventoryState(player),
		errorMessage,
		soundId,
		LOOT_SOUND_VOLUME
	)
	-- Mantem a UI de inventario standalone sincronizada.
	sendInventoryUpdate(player)
end

local function getRootPart(player)
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function isPlayerInRange(player, lootInstance)
	local rootPart = getRootPart(player)
	local lootPart = getLootPart(lootInstance)
	if not rootPart or not lootPart then
		return false
	end

	return (rootPart.Position - lootPart.Position).Magnitude <= MAX_LOOT_DISTANCE
end

-- Quantidade disponivel do item na caixa.
local function getLootItemCount(lootInstance, itemName)
	local folder = getLootFolder(lootInstance)
	if not folder then
		return 0
	end

	local entry = folder:FindFirstChild(itemName)
	if not entry or not (entry:IsA("IntValue") or entry:IsA("NumberValue")) then
		return 0
	end

	return math.max(0, math.floor(entry.Value))
end

-- Remove o stack INTEIRO do item da caixa.
local function removeLootItem(lootInstance, itemName)
	local folder = getLootFolder(lootInstance)
	if not folder then
		return
	end

	local entry = folder:FindFirstChild(itemName)
	if entry then
		entry:Destroy()
	end
end

-- Adiciona uma quantidade do item de volta na caixa.
local function addToLoot(lootInstance, itemName, amount)
	amount = math.floor(amount or 0)
	if amount <= 0 then
		return false
	end

	local folder = getLootFolder(lootInstance)
	if not folder then
		-- Sem a pasta Loot nao da para guardar; cria uma para nao perder o item.
		folder = Instance.new("Folder")
		folder.Name = LOOT_FOLDER_NAME
		folder.Parent = lootInstance
	end

	local entry = folder:FindFirstChild(itemName)
	if entry and (entry:IsA("IntValue") or entry:IsA("NumberValue")) then
		entry.Value = math.floor(entry.Value) + amount
	else
		entry = Instance.new("IntValue")
		entry.Name = itemName
		entry.Value = amount
		entry.Parent = folder
	end

	return true
end

-- Quantidade do item no inventario do jogador.
local function getInventoryItemCount(player, itemName)
	local inventory = getInventory(player)
	return math.max(0, math.floor(inventory[itemName] or 0))
end

-- Remove uma quantidade do item do inventario (ou tudo, se amount nao for informado).
local function removeFromInventory(player, itemName, amount)
	local inventory = getInventory(player)
	local current = math.floor(inventory[itemName] or 0)
	if current <= 0 then
		return 0
	end

	local toRemove = amount and math.min(current, math.floor(amount)) or current
	local newCount = current - toRemove
	if newCount <= 0 then
		inventory[itemName] = nil
	else
		inventory[itemName] = newCount
	end

	return toRemove
end

local function addToInventory(player, itemName, amount)
	amount = math.floor(amount or 1)
	if amount <= 0 then
		return false
	end

	local inventory = getInventory(player)
	local current = inventory[itemName] or 0

	-- Bloqueia somente itens novos quando o inventario esta cheio;
	-- empilhar um item que ja existe continua permitido.
	if current <= 0 and countDistinctItems(inventory) >= MAX_INVENTORY_SLOTS then
		return false
	end

	inventory[itemName] = current + amount
	return true
end

-- ===== Equipar: cria uma Tool no Backpack/personagem do jogador =====

local function buildGenericTool(itemName)
	local tool = Instance.new("Tool")
	tool.Name = itemName
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 2)
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	return tool
end

local function getToolForItem(itemName)
	if itemAssets then
		local toolsFolder = itemAssets:FindFirstChild("Tools")
		local template = toolsFolder and toolsFolder:FindFirstChild(itemName)
		if template and template:IsA("Tool") then
			return template:Clone()
		end
	end

	return buildGenericTool(itemName)
end

local function equipItem(player, itemName)
	if getInventoryItemCount(player, itemName) <= 0 then
		return false
	end

	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not character and not backpack then
		return false
	end

	removeFromInventory(player, itemName, 1)

	local tool = getToolForItem(itemName)
	-- Coloca no Backpack; o jogador equipa pela hotbar do Roblox.
	tool.Parent = backpack or character
	return true
end

-- ===== Dropar: gera um item fisico no chao com a tag DroppedItem =====

local function buildGenericWorldModel(itemName)
	local part = Instance.new("Part")
	part.Name = itemName
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Color = Color3.fromRGB(200, 180, 90)
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function getWorldModelForItem(itemName)
	if itemAssets then
		local modelsFolder = itemAssets:FindFirstChild("WorldModels")
		local template = modelsFolder and modelsFolder:FindFirstChild(itemName)
		if template and (template:IsA("Model") or template:IsA("BasePart")) then
			return template:Clone()
		end
	end

	return buildGenericWorldModel(itemName)
end

local function anchorAndQuery(model)
	if model:IsA("BasePart") then
		model.Anchored = true
		model.CanQuery = true
		model.CanTouch = true
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanQuery = true
			descendant.CanTouch = true
		end
	end
end

local function placeWorldModel(model, cframe)
	if model:IsA("Model") then
		if not model.PrimaryPart then
			model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
		end
		if model.PrimaryPart then
			model:PivotTo(cframe)
		end
	elseif model:IsA("BasePart") then
		model.CFrame = cframe
	end

	-- Ancora o item para ele ficar parado e facil de mirar com o mouse.
	anchorAndQuery(model)
end

local function dropItem(player, itemName)
	local available = getInventoryItemCount(player, itemName)
	if available <= 0 then
		return false
	end

	local rootPart = getRootPart(player)
	if not rootPart then
		return false
	end

	removeFromInventory(player, itemName, available)

	local model = getWorldModelForItem(itemName)
	model.Name = itemName

	-- Joga um pouco a frente do jogador, acima do chao.
	local dropCFrame = rootPart.CFrame * CFrame.new(0, 0, -4) + Vector3.new(0, 2, 0)
	placeWorldModel(model, dropCFrame)

	model:SetAttribute("ItemName", itemName)
	model:SetAttribute("Count", available)
	CollectionService:AddTag(model, DROPPED_TAG)
	model.Parent = worldItemsFolder

	return true
end

-- ===== Pegar: item dropado volta para o inventario =====

local function getDroppedPart(instance)
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return nil
end

local function pickupItem(player, droppedInstance)
	if not droppedInstance or not CollectionService:HasTag(droppedInstance, DROPPED_TAG) then
		return false
	end

	local rootPart = getRootPart(player)
	local droppedPart = getDroppedPart(droppedInstance)
	if not rootPart or not droppedPart then
		return false
	end

	if (rootPart.Position - droppedPart.Position).Magnitude > MAX_PICKUP_DISTANCE then
		return false
	end

	local itemName = droppedInstance:GetAttribute("ItemName")
	local count = math.floor(droppedInstance:GetAttribute("Count") or 1)
	if typeof(itemName) ~= "string" or itemName == "" or count <= 0 then
		return false
	end

	if not addToInventory(player, itemName, count) then
		return false
	end

	CollectionService:RemoveTag(droppedInstance, DROPPED_TAG)
	droppedInstance:Destroy()
	return true
end

-- ===== Eventos da caixa =====

interactionRemote.OnServerEvent:Connect(function(player, action, lootInstance, itemName)
	if not isLootInstance(lootInstance) then
		return
	end

	if not isPlayerInRange(player, lootInstance) then
		return
	end

	if action == "RequestState" then
		sendLootState(player, lootInstance, nil, normalizeSoundId(OPEN_SOUND_ID))
		return
	end

	if action == "TakeItem" then
		if typeof(itemName) ~= "string" then
			return
		end

		-- Transfere o stack INTEIRO (toda a quantidade), de uma vez.
		local available = getLootItemCount(lootInstance, itemName)
		if available <= 0 then
			sendLootState(player, lootInstance, "Item indisponivel.")
			return
		end

		if not addToInventory(player, itemName, available) then
			sendLootState(player, lootInstance, "Inventario cheio.")
			return
		end

		removeLootItem(lootInstance, itemName)
		sendLootState(player, lootInstance, nil, normalizeSoundId(TAKE_SOUND_ID))
		return
	end

	if action == "StoreItem" then
		if typeof(itemName) ~= "string" then
			return
		end

		-- Devolve o stack INTEIRO do inventario para a caixa.
		local available = getInventoryItemCount(player, itemName)
		if available <= 0 then
			sendLootState(player, lootInstance, "Item indisponivel.")
			return
		end

		addToLoot(lootInstance, itemName, available)
		removeFromInventory(player, itemName)
		sendLootState(player, lootInstance, nil, normalizeSoundId(TAKE_SOUND_ID))
		return
	end

	if action == "Close" then
		-- Evento separado: so toca o som, nao reenvia o estado (senao a UI reabriria).
		interactionRemote:FireClient(
			player,
			"Closed",
			lootInstance,
			normalizeSoundId(CLOSE_SOUND_ID),
			LOOT_SOUND_VOLUME
		)
		return
	end
end)

-- ===== Eventos de inventario / mundo (sem depender de caixa) =====

inventoryRemote.OnServerEvent:Connect(function(player, action, payload)
	if action == "Request" then
		sendInventoryUpdate(player)
		return
	end

	if action == "Equip" then
		if typeof(payload) ~= "string" then
			return
		end

		if equipItem(player, payload) then
			sendInventoryUpdate(player)
		else
			sendInventoryUpdate(player, "Nao foi possivel equipar.")
		end
		return
	end

	if action == "Drop" then
		if typeof(payload) ~= "string" then
			return
		end

		if dropItem(player, payload) then
			sendInventoryUpdate(player)
		else
			sendInventoryUpdate(player, "Nao foi possivel dropar.")
		end
		return
	end

	if action == "Pickup" then
		-- payload = instancia do item dropado.
		if pickupItem(player, payload) then
			sendInventoryUpdate(player)
		end
		return
	end
end)

Players.PlayerRemoving:Connect(function(player)
	inventories[player] = nil
end)
