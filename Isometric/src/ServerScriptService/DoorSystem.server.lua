local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remoteFolder = ReplicatedStorage:WaitForChild("DoorRemotes")
local interactionRemote = remoteFolder:WaitForChild("DoorInteraction")

local DOOR_TAG = "Door"
local DEFAULT_OPEN_ANGLE = 90
local DEFAULT_HINGE_SIDE = "Right"
local DEFAULT_OPEN_DIRECTION = "Forward"
local OPEN_SOUND_ID = "rbxassetid://115636166700655"
local CLOSE_SOUND_ID = "rbxassetid://140470748655921"
local LOCKED_SOUND_ID = "rbxassetid://116795526593480"
local DOOR_SOUND_VOLUME = 0.65

local closedCFrames = {}

local function getDoorPart(doorInstance)
	if doorInstance:IsA("BasePart") then
		return doorInstance
	end

	if doorInstance:IsA("Model") then
		return doorInstance.PrimaryPart or doorInstance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

local function getDoorStateContainer(doorInstance)
	if doorInstance:IsA("Model") then
		return doorInstance
	end

	return doorInstance
end

local function isDoorInstance(instance)
	return instance and CollectionService:HasTag(instance, DOOR_TAG)
end

local function getDoorState(doorInstance)
	local container = getDoorStateContainer(doorInstance)

	return {
		isOpen = container:GetAttribute("IsOpen") == true,
		isLocked = container:GetAttribute("IsLocked") == true,
		canOpen = container:GetAttribute("CanOpen") ~= false,
	}
end

local function sendDoorState(player, doorInstance, errorMessage, soundId)
	interactionRemote:FireClient(player, "State", doorInstance, getDoorState(doorInstance), errorMessage, soundId, DOOR_SOUND_VOLUME)
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

local function getClosedCFrame(doorPart)
	if not closedCFrames[doorPart] then
		closedCFrames[doorPart] = doorPart.CFrame
	end

	return closedCFrames[doorPart]
end

local function getOpenCFrame(doorInstance, doorPart)
	local container = getDoorStateContainer(doorInstance)
	local closedCFrame = getClosedCFrame(doorPart)
	local openAngle = container:GetAttribute("OpenAngle") or DEFAULT_OPEN_ANGLE
	local hingeSide = container:GetAttribute("HingeSide") or DEFAULT_HINGE_SIDE
	local openDirection = container:GetAttribute("OpenDirection") or DEFAULT_OPEN_DIRECTION
	local hingeOffset = (hingeSide == "Left") and -doorPart.Size.X * 0.5 or doorPart.Size.X * 0.5
	local angleDirection = (hingeSide == "Left") and 1 or -1

	if openDirection == "Backward" then
		angleDirection *= -1
	end

	return closedCFrame
		* CFrame.new(hingeOffset, 0, 0)
		* CFrame.Angles(0, math.rad(openAngle * angleDirection), 0)
		* CFrame.new(-hingeOffset, 0, 0)
end

local function setDoorOpenState(doorInstance, isOpen)
	local doorPart = getDoorPart(doorInstance)
	if not doorPart then
		return false
	end

	local container = getDoorStateContainer(doorInstance)
	doorPart.CFrame = isOpen and getOpenCFrame(doorInstance, doorPart) or getClosedCFrame(doorPart)
	doorPart.CanCollide = true
	doorPart.CanQuery = true
	doorPart.CanTouch = true
	container:SetAttribute("IsOpen", isOpen)
	return true
end

local function prepareDoor(doorInstance)
	local doorPart = getDoorPart(doorInstance)
	if not doorPart then
		warn(("Door tagged instance %s has no BasePart or PrimaryPart."):format(doorInstance:GetFullName()))
		return
	end

	getClosedCFrame(doorPart)
	doorPart.CanCollide = true
	doorPart.CanQuery = true
	doorPart.CanTouch = true
end

for _, doorInstance in ipairs(CollectionService:GetTagged(DOOR_TAG)) do
	prepareDoor(doorInstance)
end

CollectionService:GetInstanceAddedSignal(DOOR_TAG):Connect(prepareDoor)

interactionRemote.OnServerEvent:Connect(function(player, action, doorInstance)
	if not isDoorInstance(doorInstance) then
		return
	end

	local state = getDoorState(doorInstance)

	if action == "RequestState" then
		sendDoorState(player, doorInstance)
		return
	end

	if action == "ToggleOpen" then
		if not state.canOpen then
			sendDoorState(player, doorInstance, "Essa porta nao abre.", normalizeSoundId(LOCKED_SOUND_ID))
			return
		end

		if state.isOpen then
			setDoorOpenState(doorInstance, false)
			sendDoorState(player, doorInstance, nil, normalizeSoundId(CLOSE_SOUND_ID))
			return
		end

		if state.isLocked then
			sendDoorState(player, doorInstance, "A porta esta trancada.", normalizeSoundId(LOCKED_SOUND_ID))
			return
		end

		setDoorOpenState(doorInstance, true)
		sendDoorState(player, doorInstance, nil, normalizeSoundId(OPEN_SOUND_ID))
	end
end)
