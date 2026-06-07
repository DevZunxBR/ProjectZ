local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
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

local LOOT_TAG = "LootContainer"
local MAX_CLICK_DISTANCE = 20
local LOOT_RAY_DISTANCE = 300
local UI_CURSOR_OFFSET = Vector2.new(12, 12)
local PANEL_GAP = 12
local HIGHLIGHT_COLOR = Color3.fromRGB(170, 226, 255)
local SOUND_LIFETIME = 8
local SOUND_ROLLOFF_DISTANCE = 45
local ITEM_BUTTON_NAME = "LootItemButton"
local INVENTORY_HIGHLIGHT_COLOR = Color3.fromRGB(120, 200, 120)

local currentLoot = nil
local currentLootState = nil
local currentInventoryState = nil
local lastClickPosition = nil
local currentHighlight = nil

-- Estado do arraste atual: { itemName, ghost, originalColor }
local dragging = nil

local function getGuiReferences()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("LootUi")
	if not gui then
		return nil
	end

	-- Alinha o espaco da UI com UserInputService:GetMouseLocation(),
	-- senao o drop fica deslocado pela barra de topo (~36px).
	gui.IgnoreGuiInset = true

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

	local inventoryFrame = gui:FindFirstChild("InventoryFrame")
	if inventoryFrame then
		references.inventoryFrame = inventoryFrame
		references.inventoryList = inventoryFrame:FindFirstChild("ItemList")
		references.inventoryTitle = inventoryFrame:FindFirstChild("TitleLabel")
	end

	return references
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

local function isPositionInsideUi(position)
	local refs = getGuiReferences()
	if not refs or not refs.gui.Enabled then
		return false
	end

	if isPositionInsideFrame(refs.lootFrame, position) then
		return true
	end

	if refs.inventoryFrame and isPositionInsideFrame(refs.inventoryFrame, position) then
		return true
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

local function positionPanels()
	local refs = getGuiReferences()
	if not refs or not lastClickPosition then
		return
	end

	local viewport = camera.ViewportSize
	local lootSize = refs.lootFrame.AbsoluteSize
	local invSize = (refs.inventoryFrame and refs.inventoryFrame.AbsoluteSize) or Vector2.zero

	local totalWidth = lootSize.X
	if refs.inventoryFrame then
		totalWidth += PANEL_GAP + invSize.X
	end
	local maxHeight = math.max(lootSize.Y, invSize.Y)

	local startX = lastClickPosition.X + UI_CURSOR_OFFSET.X
	local startY = lastClickPosition.Y + UI_CURSOR_OFFSET.Y

	-- Mantem os dois paineis dentro da tela para sempre dar para soltar no inventario.
	if viewport.X > 0 then
		startX = math.clamp(startX, 8, math.max(8, viewport.X - totalWidth - 8))
	end
	if viewport.Y > 0 then
		startY = math.clamp(startY, 8, math.max(8, viewport.Y - maxHeight - 8))
	end

	refs.lootFrame.AnchorPoint = Vector2.new(0, 0)
	refs.lootFrame.Position = UDim2.fromOffset(startX, startY)

	if refs.inventoryFrame then
		refs.inventoryFrame.AnchorPoint = Vector2.new(0, 0)
		refs.inventoryFrame.Position = UDim2.fromOffset(startX + lootSize.X + PANEL_GAP, startY)
	end
end

local function setUiVisible(visible)
	local refs = getGuiReferences()
	if not refs then
		return
	end

	if visible then
		positionPanels()
	end

	refs.gui.Enabled = visible
	refs.lootFrame.Visible = visible
	if refs.inventoryFrame then
		refs.inventoryFrame.Visible = visible
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

local function cancelDrag()
	if not dragging then
		return
	end

	if dragging.ghost then
		dragging.ghost:Destroy()
	end

	local refs = getGuiReferences()
	if refs and refs.inventoryFrame then
		refs.inventoryFrame.BackgroundColor3 = dragging.inventoryColor
	end

	dragging = nil
end

local function updateDragGhost(position)
	if dragging and dragging.ghost then
		dragging.ghost.Position = UDim2.fromOffset(position.X + 8, position.Y + 8)
	end

	-- Realca o painel de inventario quando o item esta sobre ele.
	local refs = getGuiReferences()
	if dragging and refs and refs.inventoryFrame then
		if isPositionInsideFrame(refs.inventoryFrame, position) then
			refs.inventoryFrame.BackgroundColor3 = INVENTORY_HIGHLIGHT_COLOR
		else
			refs.inventoryFrame.BackgroundColor3 = dragging.inventoryColor
		end
	end
end

local function startDrag(item)
	cancelDrag()

	local refs = getGuiReferences()
	if not refs then
		return
	end

	local ghost = Instance.new("TextLabel")
	ghost.Name = "LootDragGhost"
	ghost.Size = UDim2.fromOffset(150, 28)
	ghost.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	ghost.BackgroundTransparency = 0.15
	ghost.TextColor3 = Color3.fromRGB(245, 245, 245)
	ghost.TextSize = 14
	ghost.Font = Enum.Font.GothamMedium
	ghost.BorderSizePixel = 0
	ghost.ZIndex = 50
	ghost.Text = ("%s  x1"):format(item.name)
	ghost.Parent = refs.gui

	dragging = {
		itemName = item.name,
		ghost = ghost,
		inventoryColor = refs.inventoryFrame and refs.inventoryFrame.BackgroundColor3 or nil,
	}

	updateDragGhost(UserInputService:GetMouseLocation())
end

local function finishDrag(position)
	if not dragging then
		return
	end

	local itemName = dragging.itemName
	local refs = getGuiReferences()

	if not refs or not refs.inventoryFrame then
		warn("[LootInteraction] InventoryFrame nao encontrado dentro de LootUi. Crie um Frame chamado exatamente 'InventoryFrame'.")
		cancelDrag()
		return
	end

	local droppedOnInventory = isPositionInsideFrame(refs.inventoryFrame, position)

	cancelDrag()

	if droppedOnInventory and currentLoot then
		interactionRemote:FireServer("TakeItem", currentLoot, itemName)
	end
end

local function populateList(itemList, items, makeDraggable)
	ensureListLayout(itemList)
	clearItemButtons(itemList)

	for index, item in ipairs(items) do
		local button = createItemButton(itemList, item, index)
		if makeDraggable then
			local capturedItem = item
			button.MouseButton1Down:Connect(function()
				startDrag(capturedItem)
			end)
		end
	end
end

local function refreshUi(errorMessage)
	local refs = getGuiReferences()
	if not refs or not currentLoot or not currentLootState then
		setUiVisible(false)
		return
	end

	refs.gui.Enabled = true
	refs.lootFrame.Visible = true
	if refs.inventoryFrame then
		refs.inventoryFrame.Visible = true
	end
	positionPanels()
	-- Reposiciona depois que o layout calcula AbsoluteSize (1o frame apos abrir).
	task.defer(positionPanels)

	local lootItems = currentLootState.items or {}
	populateList(refs.lootList, lootItems, true)

	if refs.lootTitle then
		refs.lootTitle.Text = currentLootState.title or "Loot"
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
		populateList(refs.inventoryList, currentInventoryState.items or {}, false)
		if refs.inventoryTitle then
			refs.inventoryTitle.Text = currentInventoryState.title or "Inventario"
		end
	end
end

local function hideUi()
	local closingLoot = currentLoot
	cancelDrag()
	currentLoot = nil
	currentLootState = nil
	currentInventoryState = nil
	clearHighlight()
	setUiVisible(false)

	if closingLoot then
		interactionRemote:FireServer("Close", closingLoot)
	end
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

interactionRemote.OnClientEvent:Connect(function(eventName, lootInstance, lootState, inventoryState, errorMessage, soundId, soundVolume)
	if eventName ~= "State" then
		return
	end

	playLocalSound(lootInstance, soundId, soundVolume)

	lastClickPosition = lastClickPosition or UserInputService:GetMouseLocation()
	currentLoot = lootInstance
	currentLootState = lootState
	currentInventoryState = inventoryState
	highlightLoot(lootInstance)
	refreshUi(errorMessage)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if input.KeyCode == Enum.KeyCode.Escape then
		hideUi()
		return
	end

	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end

	-- Clique processado pela GUI (botoes/itens) ou dentro dos paineis: nao fecha.
	if gameProcessedEvent then
		return
	end

	local clickPosition = UserInputService:GetMouseLocation()
	if isPositionInsideUi(clickPosition) then
		return
	end

	local clickedLoot = raycastLootAtMouse() or getClickedLoot(mouse.Target)
	if clickedLoot and isLootInRange(clickedLoot) then
		lastClickPosition = clickPosition
		interactionRemote:FireServer("RequestState", clickedLoot)
	else
		-- Clicou fora da UI e fora de um loot valido: fecha tudo.
		hideUi()
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
		updateDragGhost(UserInputService:GetMouseLocation())
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and dragging then
		finishDrag(UserInputService:GetMouseLocation())
	end
end)

RunService.Heartbeat:Connect(function()
	if currentLoot and not isLootInRange(currentLoot) then
		hideUi()
	end
end)
