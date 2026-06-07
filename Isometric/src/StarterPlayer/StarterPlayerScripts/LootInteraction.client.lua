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
local HIGHLIGHT_COLOR = Color3.fromRGB(170, 226, 255)
local SOUND_LIFETIME = 8
local SOUND_ROLLOFF_DISTANCE = 45
local ITEM_BUTTON_NAME = "LootItemButton"

local currentLoot = nil
local currentState = nil
local lastClickPosition = nil
local currentHighlight = nil

local function getGuiReferences()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("LootUi")
	if not gui then
		return nil
	end

	local frame = gui:FindFirstChild("Frame")
	if not frame then
		return nil
	end

	local itemList = frame:FindFirstChild("ItemList")
	if not itemList then
		return nil
	end

	local titleLabel = frame:FindFirstChild("TitleLabel")
	local statusLabel = frame:FindFirstChild("StatusLabel")

	return gui, frame, itemList, titleLabel, statusLabel
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

local function moveUiToCursor()
	local _, frame = getGuiReferences()
	if not frame or not lastClickPosition then
		return
	end

	frame.AnchorPoint = Vector2.new(0, 0)
	frame.Position = UDim2.fromOffset(
		lastClickPosition.X + UI_CURSOR_OFFSET.X,
		lastClickPosition.Y + UI_CURSOR_OFFSET.Y
	)
end

local function setUiVisible(visible)
	local gui, frame = getGuiReferences()
	if gui and frame then
		if visible then
			moveUiToCursor()
		end

		gui.Enabled = visible
		frame.Visible = visible
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

	button.MouseButton1Click:Connect(function()
		if currentLoot then
			interactionRemote:FireServer("TakeItem", currentLoot, item.name)
		end
	end)

	return button
end

local function refreshUi(errorMessage)
	local gui, frame, itemList, titleLabel, statusLabel = getGuiReferences()
	if not gui or not currentLoot or not currentState then
		setUiVisible(false)
		return
	end

	gui.Enabled = true
	frame.Visible = true
	moveUiToCursor()

	ensureListLayout(itemList)
	clearItemButtons(itemList)

	local items = currentState.items or {}
	for index, item in ipairs(items) do
		createItemButton(itemList, item, index)
	end

	if titleLabel then
		titleLabel.Text = currentState.title or "Loot"
	end

	if statusLabel then
		if errorMessage and errorMessage ~= "" then
			statusLabel.Text = errorMessage
		elseif #items == 0 then
			statusLabel.Text = "Vazio"
		else
			statusLabel.Text = ("%d item(s)"):format(#items)
		end
	end
end

local function hideUi()
	local closingLoot = currentLoot
	currentLoot = nil
	currentState = nil
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

interactionRemote.OnClientEvent:Connect(function(eventName, lootInstance, state, errorMessage, soundId, soundVolume)
	if eventName ~= "State" then
		return
	end

	playLocalSound(lootInstance, soundId, soundVolume)

	lastClickPosition = lastClickPosition or UserInputService:GetMouseLocation()
	currentLoot = lootInstance
	currentState = state
	highlightLoot(lootInstance)
	refreshUi(errorMessage)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		hideUi()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local clickedLoot = raycastLootAtMouse() or getClickedLoot(mouse.Target)
		if clickedLoot and isLootInRange(clickedLoot) then
			lastClickPosition = UserInputService:GetMouseLocation()
			interactionRemote:FireServer("RequestState", clickedLoot)
		else
			hideUi()
		end
	end
end)

RunService.Heartbeat:Connect(function()
	if currentLoot and not isLootInRange(currentLoot) then
		hideUi()
	end
end)
