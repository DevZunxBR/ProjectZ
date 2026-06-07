local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local remoteFolder = ReplicatedStorage:WaitForChild("LootRemotes")
local interactionRemote = remoteFolder:WaitForChild("LootInteraction")

local LOOT_TAG = "LootContainer"
local LOOT_FOLDER_NAME = "Loot"
local DEFAULT_TITLE = "Loot"
local INVENTORY_TITLE = "Inventario"
local OPEN_SOUND_ID = "rbxassetid://115636166700655"
local CLOSE_SOUND_ID = "rbxassetid://140470748655921"
local TAKE_SOUND_ID = ""
local LOOT_SOUND_VOLUME = 0.6
local MAX_LOOT_DISTANCE = 22
local MAX_INVENTORY_SLOTS = 24

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
end

local function isPlayerInRange(player, lootInstance)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
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

-- Remove o stack INTEIRO do item do inventario.
local function removeFromInventory(player, itemName)
	local inventory = getInventory(player)
	inventory[itemName] = nil
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

Players.PlayerRemoving:Connect(function(player)
	inventories[player] = nil
end)
