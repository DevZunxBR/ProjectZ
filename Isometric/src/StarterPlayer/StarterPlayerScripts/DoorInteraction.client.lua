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

local remoteFolder = ReplicatedStorage:WaitForChild("DoorRemotes")
local interactionRemote = remoteFolder:WaitForChild("DoorInteraction")

local DOOR_TAG = "Door"
local MAX_CLICK_DISTANCE = 20
local DOOR_RAY_DISTANCE = 300
local UI_CURSOR_OFFSET = Vector2.new(12, 12)
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 238, 170)
local SOUND_LIFETIME = 8
local SOUND_ROLLOFF_DISTANCE = 45

local currentDoor = nil
local currentState = nil
local lastClickPosition = nil
local currentHighlight = nil
local suppressNextStateForDoor = nil

local function getGuiReferences()
	local playerGui = player:WaitForChild("PlayerGui")
	local gui = playerGui:FindFirstChild("DoorUi")
	if not gui then
		return nil
	end

	local frame = gui:FindFirstChild("Frame")
	if not frame then
		return nil
	end

	local openButton = frame:FindFirstChild("OpenButton")
	local lockButton = frame:FindFirstChild("LockButton")
	local statusLabel = frame:FindFirstChild("StatusLabel")
	if not openButton then
		return nil
	end

	return gui, frame, openButton, lockButton, statusLabel
end

local function getDoorPart(doorInstance)
	if not doorInstance then
		return nil
	end

	if doorInstance:IsA("BasePart") then
		return doorInstance
	end

	if doorInstance:IsA("Model") then
		return doorInstance.PrimaryPart or doorInstance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function getClickedDoor(target)
	if not target then
		return nil
	end

	if CollectionService:HasTag(target, DOOR_TAG) then
		return target
	end

	local ancestor = target:FindFirstAncestorWhichIsA("Model")
	if ancestor and CollectionService:HasTag(ancestor, DOOR_TAG) then
		return ancestor
	end

	return nil
end

local function raycastDoorAtMouse()
	local mousePosition = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePosition.X, mousePosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local character = player.Character
	local ignoredInstances = character and { character } or {}
	raycastParams.FilterDescendantsInstances = ignoredInstances

	for _ = 1, 10 do
		local result = Workspace:Raycast(ray.Origin, ray.Direction * DOOR_RAY_DISTANCE, raycastParams)
		if not result then
			return nil
		end

		local clickedDoor = getClickedDoor(result.Instance)
		if clickedDoor then
			return clickedDoor
		end

		table.insert(ignoredInstances, result.Instance)
		raycastParams.FilterDescendantsInstances = ignoredInstances
	end

	return nil
end

local function isDoorInRange(doorInstance)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local doorPart = getDoorPart(doorInstance)
	if not rootPart or not doorPart then
		return false
	end

	return (rootPart.Position - doorPart.Position).Magnitude <= MAX_CLICK_DISTANCE
end

local function clearHighlight()
	if currentHighlight then
		currentHighlight:Destroy()
		currentHighlight = nil
	end
end

local function highlightDoor(doorInstance)
	clearHighlight()

	currentHighlight = Instance.new("Highlight")
	currentHighlight.Name = "SelectedDoorHighlight"
	currentHighlight.Adornee = doorInstance
	currentHighlight.FillTransparency = 1
	currentHighlight.OutlineTransparency = 0
	currentHighlight.OutlineColor = HIGHLIGHT_COLOR
	currentHighlight.DepthMode = Enum.HighlightDepthMode.Occluded
	currentHighlight.Parent = doorInstance
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

local function refreshUi(errorMessage)
	local gui, frame, openButton, lockButton, statusLabel = getGuiReferences()
	if not gui or not currentDoor or not currentState then
		setUiVisible(false)
		return
	end

	gui.Enabled = true
	frame.Visible = true
	moveUiToCursor()

	if currentState.canOpen == false then
		openButton.Text = "Bloqueada"
		openButton.Active = false
		openButton.AutoButtonColor = false
	elseif currentState.isLocked then
		openButton.Text = "Trancada"
		openButton.Active = false
		openButton.AutoButtonColor = false
	else
		openButton.Text = currentState.isOpen and "Fechar" or "Abrir"
		openButton.Active = true
		openButton.AutoButtonColor = true
	end

	if lockButton then
		lockButton.Visible = false
	end

	if statusLabel then
		if errorMessage and errorMessage ~= "" then
			statusLabel.Text = errorMessage
		elseif currentState.canOpen == false then
			statusLabel.Text = "Essa porta nao abre"
		elseif currentState.isLocked then
			statusLabel.Text = "Porta trancada"
		elseif currentState.isOpen then
			statusLabel.Text = "Porta aberta"
		else
			statusLabel.Text = "Porta fechada"
		end
	end
end

local function hideUi()
	currentDoor = nil
	currentState = nil
	clearHighlight()
	setUiVisible(false)
end

local function playLocalSound(doorInstance, soundId, volume)
	if not soundId or soundId == "" then
		return
	end

	local doorPart = getDoorPart(doorInstance)
	if not doorPart then
		warn("Door sound could not play because the door has no BasePart.")
		return
	end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume or 0.65
	sound.RollOffMaxDistance = SOUND_ROLLOFF_DISTANCE
	sound.Parent = doorPart

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
			warn(("Door sound failed to load: %s"):format(soundId))
			return
		end

		sound.TimePosition = 0
		sound:Play()
	end)
end

interactionRemote.OnClientEvent:Connect(function(eventName, doorInstance, state, errorMessage, soundId, soundVolume)
	if eventName ~= "State" then
		return
	end

	playLocalSound(doorInstance, soundId, soundVolume)

	if suppressNextStateForDoor == doorInstance then
		suppressNextStateForDoor = nil
		return
	end

	lastClickPosition = lastClickPosition or UserInputService:GetMouseLocation()
	currentDoor = doorInstance
	currentState = state
	highlightDoor(doorInstance)
	refreshUi(errorMessage)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		hideUi()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		local clickedDoor = raycastDoorAtMouse() or getClickedDoor(mouse.Target)
		if clickedDoor and isDoorInRange(clickedDoor) then
			lastClickPosition = UserInputService:GetMouseLocation()
			interactionRemote:FireServer("RequestState", clickedDoor)
		else
			hideUi()
		end
	end
end)

local function connectButtons()
	local gui, _, openButton = getGuiReferences()
	if not gui then
		return false
	end

	openButton.MouseButton1Click:Connect(function()
		if currentDoor and currentState and currentState.canOpen and not currentState.isLocked then
			suppressNextStateForDoor = currentDoor
			interactionRemote:FireServer("ToggleOpen", currentDoor)
			hideUi()
		end
	end)

	return true
end

task.spawn(function()
	while not connectButtons() do
		task.wait(1)
	end
end)

RunService.Heartbeat:Connect(function()
	if currentDoor and not isDoorInRange(currentDoor) then
		hideUi()
	end
end)
