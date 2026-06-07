local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

local remoteFolder = ReplicatedStorage:WaitForChild("LootRemotes")
local interactionRemote = remoteFolder:WaitForChild("LootInteraction")

-- Espera com timeout: se o servidor (LootSystem.server.lua) nao criar o
-- InventoryRemote, NAO trava o script inteiro. Sem isso, clicar na caixa,
-- Tab e tudo mais parariam de funcionar.
local inventoryRemote = remoteFolder:WaitForChild("InventoryRemote", 10)
if not inventoryRemote then
	warn("[LootInteraction] InventoryRemote nao encontrado em ReplicatedStorage.LootRemotes. "
		.. "Confirme que o LootSystem.server.lua ATUALIZADO esta em ServerScriptService. "
		.. "Equipar/Dropar/pegar do chao nao vao funcionar ate isso ser corrigido.")
	-- Fallback local apenas para o restante da UI continuar funcionando.
	inventoryRemote = Instance.new("RemoteEvent")
	inventoryRemote.Name = "InventoryRemote"
	inventoryRemote.Parent = remoteFolder
end

local LOOT_TAG = "LootContainer"
local MAX_CLICK_DISTANCE = 20
local LOOT_RAY_DISTANCE = 300
local HIGHLIGHT_COLOR = Color3.fromRGB(170, 226, 255)
local SOUND_LIFETIME = 8
local SOUND_ROLLOFF_DISTANCE = 45
local ITEM_BUTTON_NAME = "LootItemButton"
local INVENTORY_TOGGLE_KEY = Enum.KeyCode.Tab

-- Fases da interface: "closed" -> "inspect" -> "open"
local uiPhase = "closed"
local currentLoot = nil
local currentLootState = nil
local currentInventoryState = nil
local selectedItemName = nil
local selectedItemSource = nil
local currentHighlight = nil

-- Inventario standalone (aberto pelo Tab, sem caixa).
local inventoryOnlyOpen = false

-- Evita conectar o mesmo botao mais de uma vez.
local connectedButtons = {}

-- Declaracoes adiantadas (funcoes que se referenciam entre si).
local hideUi
local showInspectPhase
local showOpenPhase
local refreshLists
local showActionPanel
local onInspectClicked
local onTransferClicked
local onEquipClicked
local onDropClicked
local openInventoryOnly
local closeActionPanel
local refreshInventoryOnly

local function getGuiReferences()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("LootUi")
	if not gui then
		return nil
	end

	local lootFrame = gui:FindFirstChild("LootFrame") or gui:FindFirstChild("Frame")
	if not lootFrame then
		return nil
	end

	local lootList = lootFrame:FindFirstChild("ItemList")
	if not lootList then
		return nil
	end

	local references = {
		gui = gui,
		lootFrame = lootFrame,
		lootList = lootList,
		lootTitle = lootFrame:FindFirstChild("TitleLabel"),
		lootStatus = lootFrame:FindFirstChild("StatusLabel"),
	}

	-- Buscas recursivas: os elementos podem estar em qualquer lugar dentro da LootUi.
	local inspectFrame = gui:FindFirstChild("InspectFrame", true)
	if inspectFrame then
		references.inspectFrame = inspectFrame
		references.inspectButton = inspectFrame:FindFirstChild("InspectButton", true)
	end

	local inventoryFrame = gui:FindFirstChild("InventoryFrame", true)
	if inventoryFrame then
		references.inventoryFrame = inventoryFrame
		-- Usa o ItemList se existir; senao, usa o proprio InventoryFrame como lista.
		references.inventoryList = inventoryFrame:FindFirstChild("ItemList") or inventoryFrame
		references.inventoryTitle = inventoryFrame:FindFirstChild("TitleLabel")
	end

	local actionFrame = gui:FindFirstChild("ActionFrame", true)
	if actionFrame then
		references.actionFrame = actionFrame
		references.actionTitle = actionFrame:FindFirstChild("ItemName") or actionFrame:FindFirstChild("TitleLabel")
		references.transferButton = actionFrame:FindFirstChild("TransferButton", true)
		references.dropButton = actionFrame:FindFirstChild("DropButton", true)
		references.equipButton = actionFrame:FindFirstChild("EquipButton", true)
	end

	return references
end

local function connectOnce(button, callback)
	if not button or connectedButtons[button] then
		return
	end

	connectedButtons[button] = true
	button.MouseButton1Click:Connect(callback)
end

local function getLootPart(lootInstance)
	if not lootInstance then
		return nil
	end

	if lootInstance:IsA("BasePart") then
		return lootInstance
	end

	if lootInstance:IsA("Model") then
		return lootInstance.PrimaryPart or lootInstance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function getClickedLoot(target)
	if not target then
		return nil
	end

	if CollectionService:HasTag(target, LOOT_TAG) then
		return target
	end

	local ancestor = target:FindFirstAncestorWhichIsA("Model")
	if ancestor and CollectionService:HasTag(ancestor, LOOT_TAG) then
		return ancestor
	end

	return nil
end

local function raycastLootAtMouse()
	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local character = player.Character
	local ignoredInstances = character and { character } or {}
	raycastParams.FilterDescendantsInstances = ignoredInstances

	for _ = 1, 10 do
		local result = Workspace:Raycast(ray.Origin, ray.Direction * LOOT_RAY_DISTANCE, raycastParams)
		if not result then
			return nil
		end

		local clickedLoot = getClickedLoot(result.Instance)
		if clickedLoot then
			return clickedLoot
		end

		table.insert(ignoredInstances, result.Instance)
		raycastParams.FilterDescendantsInstances = ignoredInstances
	end

	return nil
end

local function isLootInRange(lootInstance)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local lootPart = getLootPart(lootInstance)
	if not rootPart or not lootPart then
		return false
	end

	return (rootPart.Position - lootPart.Position).Magnitude <= MAX_CLICK_DISTANCE
end

local function isPositionInsideFrame(frame, position)
	if not frame or not frame.Visible then
		return false
	end

	local topLeft = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	return position.X >= topLeft.X
		and position.X <= topLeft.X + size.X
		and position.Y >= topLeft.Y
		and position.Y <= topLeft.Y + size.Y
end

-- Converte a posicao do mouse (que inclui a barra de topo) para o espaco da UI.
local function toGuiSpace(gui, position)
	if not gui or gui.IgnoreGuiInset then
		return position
	end

	local inset = GuiService:GetGuiInset()
	return position - inset
end

local function isPositionInsideUi(position)
	local refs = getGuiReferences()
	if not refs or not refs.gui.Enabled then
		return false
	end

	local guiPosition = toGuiSpace(refs.gui, position)
	local frames = { refs.inspectFrame, refs.lootFrame, refs.inventoryFrame, refs.actionFrame }
	for _, frame in ipairs(frames) do
		if frame and isPositionInsideFrame(frame, guiPosition) then
			return true
		end
	end

	return false
end

local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
end

local function highlightLoot(lootInstance)
	clearHighlight()

	currentHighlight = Instance.new("Highlight")
	currentHighlight.Name = "SelectedLootHighlight"
	currentHighlight.Adornee = lootInstance
	currentHighlight.FillTransparency = 1
	currentHighlight.OutlineTransparency = 0
	currentHighlight.OutlineColor = HIGHLIGHT_COLOR
	currentHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	currentHighlight.Parent = lootInstance
end

local function hideAllFrames(refs)
	if refs.inspectFrame then
		refs.inspectFrame.Visible = false
	end
	refs.lootFrame.Visible = false
	if refs.inventoryFrame then
		refs.inventoryFrame.Visible = false
	end
	if refs.actionFrame then
		refs.actionFrame.Visible = false
	end
end

local function ensureListLayout(itemList)
	local layout = itemList:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = itemList
	end

	-- Se a lista for um ScrollingFrame, configura a area de rolagem automaticamente.
	-- Sem isso, os botoes existem mas ficam invisiveis (CanvasSize = 0).
	if itemList:IsA("ScrollingFrame") then
		itemList.AutomaticCanvasSize = Enum.AutomaticSize.Y
		itemList.CanvasSize = UDim2.new(0, 0, 0, 0)
		itemList.ScrollingDirection = Enum.ScrollingDirection.Y
	end
end

local function clearItemButtons(itemList)
	for _, child in ipairs(itemList:GetChildren()) do
		if child.Name == ITEM_BUTTON_NAME then
			child:Destroy()
		end
	end
end

local function createItemButton(itemList, item, layoutOrder)
	local template = itemList:FindFirstChild("ItemTemplate")
	local button

	if template and template:IsA("GuiButton") then
		button = template:Clone()
		button.Visible = true
		-- Garante que o layout controle a posicao do clone.
		button.Position = UDim2.new(0, 0, 0, 0)
	else
		button = Instance.new("TextButton")
		button.Size = UDim2.new(1, 0, 0, 28)
		button.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
		button.TextColor3 = Color3.fromRGB(235, 235, 235)
		button.TextSize = 14
		button.Font = Enum.Font.Gotham
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
	end

	button.Name = ITEM_BUTTON_NAME
	button.LayoutOrder = layoutOrder
	button.Text = ("%s  x%d"):format(item.name, item.count)
	button.Parent = itemList

	return button
end

local function populateList(itemList, items, onItemClick)
	ensureListLayout(itemList)
	clearItemButtons(itemList)

	for index, item in ipairs(items) do
		local button = createItemButton(itemList, item, index)
		if onItemClick then
			local capturedItem = item
			button.MouseButton1Click:Connect(function()
				onItemClick(capturedItem)
			end)
		end
	end
end

local function lootHasItem(itemName)
	if not currentLootState or not itemName then
		return false
	end

	for _, item in ipairs(currentLootState.items or {}) do
		if item.name == itemName then
			return true
		end
	end

	return false
end

local function inventoryHasItem(itemName)
	if not currentInventoryState or not itemName then
		return false
	end

	for _, item in ipairs(currentInventoryState.items or {}) do
		if item.name == itemName then
			return true
		end
	end

	return false
end

-- Verifica se o item selecionado ainda existe na sua origem.
local function selectedItemStillExists()
	if selectedItemSource == "inventory" then
		return inventoryHasItem(selectedItemName)
	end

	return lootHasItem(selectedItemName)
end

function onInspectClicked()
	if currentLoot and isLootInRange(currentLoot) then
		-- Pede o estado ao servidor; a resposta abre os paineis (fase "open").
		interactionRemote:FireServer("RequestState", currentLoot)
	end
end

function onTransferClicked()
	if not selectedItemName then
		return
	end

	if selectedItemSource == "inventory" then
		if currentLoot then
			-- Item do inventario com caixa aberta: devolve para a caixa.
			interactionRemote:FireServer("StoreItem", currentLoot, selectedItemName)
		end
	else
		if currentLoot then
			-- Item da caixa: envia para o inventario.
			interactionRemote:FireServer("TakeItem", currentLoot, selectedItemName)
		end
	end
end

function onEquipClicked()
	if selectedItemName and selectedItemSource == "inventory" then
		inventoryRemote:FireServer("Equip", selectedItemName)
		closeActionPanel()
	end
end

function onDropClicked()
	if selectedItemName and selectedItemSource == "inventory" then
		inventoryRemote:FireServer("Drop", selectedItemName)
		closeActionPanel()
	end
end

function closeActionPanel()
	selectedItemName = nil
	selectedItemSource = nil

	local refs = getGuiReferences()
	if refs and refs.actionFrame then
		refs.actionFrame.Visible = false
	end
end

function showInspectPhase()
	local refs = getGuiReferences()
	if not refs then
		return
	end

	uiPhase = "inspect"
	selectedItemName = nil
	selectedItemSource = nil
	hideAllFrames(refs)
	refs.gui.Enabled = true

	if refs.inspectFrame then
		refs.inspectFrame.Visible = true
		connectOnce(refs.inspectButton, onInspectClicked)
	else
		warn("[LootInteraction] InspectFrame nao encontrado dentro de LootUi. Crie um Frame 'InspectFrame' com um TextButton 'InspectButton'.")
	end
end

function showOpenPhase()
	local refs = getGuiReferences()
	if not refs then
		return
	end

	uiPhase = "open"
	if refs.inspectFrame then
		refs.inspectFrame.Visible = false
	end
	refs.gui.Enabled = true
	refs.lootFrame.Visible = true
	if refs.inventoryFrame then
		refs.inventoryFrame.Visible = true
	end
	if refs.actionFrame then
		refs.actionFrame.Visible = false
	end

	connectOnce(refs.transferButton, onTransferClicked)
	connectOnce(refs.equipButton, onEquipClicked)
	connectOnce(refs.dropButton, onDropClicked)
end

function showActionPanel(itemName, source)
	selectedItemName = itemName
	selectedItemSource = source or "loot"

	local refs = getGuiReferences()
	if not refs then
		return
	end

	if not refs.actionFrame then
		warn("[LootInteraction] ActionFrame nao encontrado dentro de LootUi. Crie um Frame 'ActionFrame' com botoes 'TransferButton', 'DropButton' e 'EquipButton'.")
		return
	end

	-- Garante os listeners (caso a telinha seja aberta pelo inventario via Tab).
	connectOnce(refs.transferButton, onTransferClicked)
	connectOnce(refs.equipButton, onEquipClicked)
	connectOnce(refs.dropButton, onDropClicked)

	if refs.actionTitle and (refs.actionTitle:IsA("TextLabel") or refs.actionTitle:IsA("TextButton")) then
		refs.actionTitle.Text = itemName
	end

	local fromInventory = selectedItemSource == "inventory"

	-- Transferir/Guardar so faz sentido com uma caixa aberta.
	if refs.transferButton then
		refs.transferButton.Visible = currentLoot ~= nil
		if refs.transferButton:IsA("TextButton") then
			refs.transferButton.Text = fromInventory and "Guardar" or "Transferir"
		end
	end

	-- Equipar e Dropar so valem para itens do inventario.
	if refs.equipButton then
		refs.equipButton.Visible = fromInventory
	end
	if refs.dropButton then
		refs.dropButton.Visible = fromInventory
	end

	refs.actionFrame.Visible = true
end

function refreshLists(errorMessage)
	local refs = getGuiReferences()
	if not refs then
		return
	end

	local lootItems = (currentLootState and currentLootState.items) or {}
	populateList(refs.lootList, lootItems, function(item)
		showActionPanel(item.name, "loot")
	end)

	if refs.lootTitle then
		refs.lootTitle.Text = (currentLootState and currentLootState.title) or "Loot"
	end

	if refs.lootStatus then
		if errorMessage and errorMessage ~= "" then
			refs.lootStatus.Text = errorMessage
		elseif #lootItems == 0 then
			refs.lootStatus.Text = "Vazio"
		else
			refs.lootStatus.Text = ("%d item(s)"):format(#lootItems)
		end
	end

	if refs.inventoryList and currentInventoryState then
		populateList(refs.inventoryList, currentInventoryState.items or {}, function(item)
			showActionPanel(item.name, "inventory")
		end)
		if refs.inventoryTitle then
			refs.inventoryTitle.Text = currentInventoryState.title or "Inventario"
		end
	elseif not refs.inventoryFrame then
		warn("[LootInteraction] InventoryFrame nao encontrado dentro de LootUi. Os itens transferidos nao tem onde aparecer.")
	end

	-- Se o item selecionado nao existe mais na sua origem, fecha a telinha de acoes.
	if refs.actionFrame and refs.actionFrame.Visible and not selectedItemStillExists() then
		refs.actionFrame.Visible = false
		selectedItemName = nil
		selectedItemSource = nil
	end
end

-- Redesenha apenas a lista do inventario (modo Tab, sem caixa).
function refreshInventoryOnly(errorMessage)
	local refs = getGuiReferences()
	if not refs or not refs.inventoryList then
		return
	end

	populateList(refs.inventoryList, (currentInventoryState and currentInventoryState.items) or {}, function(item)
		showActionPanel(item.name, "inventory")
	end)

	if refs.inventoryTitle then
		refs.inventoryTitle.Text = (currentInventoryState and currentInventoryState.title) or "Inventario"
	end

	if errorMessage and errorMessage ~= "" and refs.lootStatus then
		refs.lootStatus.Text = errorMessage
	end

	-- Fecha a telinha de acoes se o item sumiu do inventario.
	if refs.actionFrame and refs.actionFrame.Visible and not inventoryHasItem(selectedItemName) then
		closeActionPanel()
	end
end

function hideUi()
	local closingLoot = currentLoot
	uiPhase = "closed"
	inventoryOnlyOpen = false
	currentLoot = nil
	currentLootState = nil
	currentInventoryState = nil
	selectedItemName = nil
	selectedItemSource = nil
	clearHighlight()

	local refs = getGuiReferences()
	if refs then
		hideAllFrames(refs)
		refs.gui.Enabled = false
	end

	if closingLoot then
		interactionRemote:FireServer("Close", closingLoot)
	end
end

-- Abre apenas o inventario (Tab), sem caixa.
function openInventoryOnly()
	local refs = getGuiReferences()
	if not refs then
		return
	end

	if not refs.inventoryFrame then
		warn("[LootInteraction] InventoryFrame nao encontrado dentro de LootUi. Nao da para abrir o inventario com Tab.")
		return
	end

	inventoryOnlyOpen = true
	uiPhase = "inventory"
	currentLoot = nil
	currentLootState = nil
	clearHighlight()

	hideAllFrames(refs)
	refs.gui.Enabled = true
	refs.inventoryFrame.Visible = true

	connectOnce(refs.equipButton, onEquipClicked)
	connectOnce(refs.dropButton, onDropClicked)

	-- Pede o inventario atual ao servidor; a resposta preenche a lista.
	inventoryRemote:FireServer("Request")
end

local function playLocalSound(lootInstance, soundId, volume)
	if not soundId or soundId == "" then
		return
	end

	local lootPart = getLootPart(lootInstance)
	if not lootPart then
		warn("Loot sound could not play because the container has no BasePart.")
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.6
	sound.RollOffMaxDistance = SOUND_ROLLOFF_DISTANCE
	sound.Parent = lootPart

	sound.Ended:Once(function()
		sound:Destroy()
	end)

	task.delay(SOUND_LIFETIME, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)

	task.spawn(function()
		local loadedSuccessfully = pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)

		if not loadedSuccessfully or not sound.Parent then
			warn(("Loot sound failed to load: %s"):format(soundId))
			return
		end

		sound.TimePosition = 0
		sound:Play()
	end)
end

interactionRemote.OnClientEvent:Connect(function(eventName, lootInstance, a, b, c, d, e)
	if eventName == "Closed" then
		-- a = soundId, b = volume
		playLocalSound(lootInstance, a, b)
		return
	end

	if eventName ~= "State" then
		return
	end

	-- a = lootState, b = inventoryState, c = errorMessage, d = soundId, e = volume
	playLocalSound(lootInstance, d, e)

	currentLoot = lootInstance
	currentLootState = a
	currentInventoryState = b
	highlightLoot(lootInstance)

	if uiPhase ~= "open" then
		showOpenPhase()
	end

	refreshLists(c)
end)

-- Atualizacoes do inventario (UI standalone via Tab e sincronia geral).
inventoryRemote.OnClientEvent:Connect(function(eventName, inventoryState, errorMessage)
	if eventName ~= "Update" then
		return
	end

	currentInventoryState = inventoryState

	-- So redesenha se alguma UI estiver aberta.
	if uiPhase == "open" then
		refreshLists(errorMessage)
	elseif inventoryOnlyOpen then
		refreshInventoryOnly(errorMessage)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == INVENTORY_TOGGLE_KEY then
		-- Tab abre/fecha o inventario (so quando nao ha caixa aberta).
		if uiPhase == "open" or uiPhase == "inspect" then
			return
		end

		if inventoryOnlyOpen then
			hideUi()
		else
			openInventoryOnly()
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		hideUi()
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	-- Clique processado pela GUI (botoes/itens): nao fecha nem reinspeciona.
	if gameProcessedEvent then
		return
	end

	local clickPosition = UserInputService:GetMouseLocation()
	if isPositionInsideUi(clickPosition) then
		return
	end

	local clickedLoot = raycastLootAtMouse() or getClickedLoot(mouse.Target)
	if clickedLoot and isLootInRange(clickedLoot) then
		-- Clicou numa caixa: mostra a UI de inspecionar (igual a porta).
		inventoryOnlyOpen = false
		currentLoot = clickedLoot
		highlightLoot(clickedLoot)
		showInspectPhase()
	else
		-- Clicou fora da UI e fora de uma caixa: fecha tudo.
		hideUi()
	end
end)

RunService.Heartbeat:Connect(function()
	if currentLoot and not isLootInRange(currentLoot) then
		hideUi()
	end
end)
