local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local CAMERA_DISTANCE = 70
local INDOOR_CAMERA_DISTANCE = 34
local CAMERA_HEIGHT = 50
local INDOOR_CAMERA_HEIGHT = 25
local CAMERA_FOV = 20
local ROTATION_STEP = 45
local ROTATION_SMOOTHNESS = 12
local POSITION_SMOOTHNESS = 14
local ZOOM_SMOOTHNESS = 10
local FOCUS_HEIGHT = 2.5
local WALL_TRANSPARENCY = 0.55
local ROOF_TRANSPARENCY = 1
local OCCLUSION_CHECK_HEIGHT = 18
local OCCLUSION_CHECK_RADIUS = 6
local OCCLUSION_CLEAR_DELAY = 0.15
local OCCLUSION_FADE_SMOOTHNESS = 12
local WALL_HEIGHT_THRESHOLD = 5
local ROOF_THICKNESS_THRESHOLD = 3
local INDOOR_WALL_NEARBY_COUNT = 2
local INDOOR_WALL_RADIUS = 10
local MAX_OCCLUSION_RAYCASTS = 12
local WALL_RAY_HEIGHT_OFFSETS = { 1.5, 3.5, 5.5 }
local FLOOR_HEIGHT = 16
local FLOOR_CUT_HEIGHT = 10
local FLOOR_CUT_RADIUS = 90
local UPPER_FLOOR_TRANSPARENCY = 1
local WALL_TAG = "Wall"
local ROOF_TAG = "Roof"
local FLOOR_TAG = "Floor"
local DOOR_TAG = "Door"

local currentYaw = 45
local targetYaw = currentYaw
local fadedParts = {}
local lastOcclusionHitAt = 0
local smoothedFocusPosition = nil
local smoothedCameraPosition = nil
local currentCameraDistance = CAMERA_DISTANCE
local currentCameraHeight = CAMERA_HEIGHT

local function getCharacterParts()
	local character = player.Character
	if not character then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return nil, nil, nil
	end

	return character, humanoid, rootPart
end

local function restoreOcclusionTransparency()
	for part, data in pairs(fadedParts) do
		if part and part.Parent then
			part.LocalTransparencyModifier = data.original
		end
	end

	table.clear(fadedParts)
end

local function smoothValue(currentValue, targetValue, deltaTime, speed)
	local alpha = 1 - math.exp(-speed * deltaTime)
	return currentValue + (targetValue - currentValue) * alpha
end

local function smoothVector(currentValue, targetValue, deltaTime, speed)
	if not currentValue then
		return targetValue
	end

	local alpha = 1 - math.exp(-speed * deltaTime)
	return currentValue:Lerp(targetValue, alpha)
end

local function markOccludedParts(parts)
	local nextFadedParts = {}

	for part, targetTransparency in pairs(parts) do
		if part and part:IsA("BasePart") then
			if fadedParts[part] == nil then
				fadedParts[part] = {
					original = part.LocalTransparencyModifier,
					target = targetTransparency,
				}
			else
				fadedParts[part].target = targetTransparency
			end

			nextFadedParts[part] = true
		end
	end

	for part, data in pairs(fadedParts) do
		if not nextFadedParts[part] then
			data.target = data.original
		end
	end
end

local function updateOcclusionTransparency(deltaTime)
	for part, data in pairs(fadedParts) do
		if not part or not part.Parent then
			fadedParts[part] = nil
		else
			part.LocalTransparencyModifier = smoothValue(
				part.LocalTransparencyModifier,
				data.target,
				deltaTime,
				OCCLUSION_FADE_SMOOTHNESS
			)

			if math.abs(part.LocalTransparencyModifier - data.original) < 0.01
				and math.abs(data.target - data.original) < 0.001 then
				part.LocalTransparencyModifier = data.original
				fadedParts[part] = nil
			end
		end
	end
end

local function isDoorPart(part)
	if CollectionService:HasTag(part, DOOR_TAG) then
		return true
	end

	local doorModel = part:FindFirstAncestorWhichIsA("Model")
	return doorModel and CollectionService:HasTag(doorModel, DOOR_TAG)
end

local function isTaggedBuildingPart(part)
	return CollectionService:HasTag(part, WALL_TAG)
		or CollectionService:HasTag(part, ROOF_TAG)
		or CollectionService:HasTag(part, FLOOR_TAG)
end

local function getPartOcclusionTarget(part, rootPart)
	if isDoorPart(part) then
		return nil
	end

	if CollectionService:HasTag(part, ROOF_TAG) then
		return ROOF_TRANSPARENCY
	end

	if CollectionService:HasTag(part, WALL_TAG) then
		return WALL_TRANSPARENCY
	end

	local partHeight = part.Size.Y
	local isAbovePlayer = part.Position.Y > rootPart.Position.Y + WALL_HEIGHT_THRESHOLD
	local isRoofLike = isAbovePlayer and partHeight <= ROOF_THICKNESS_THRESHOLD

	if isRoofLike then
		return ROOF_TRANSPARENCY
	end

	if isAbovePlayer or partHeight > ROOF_THICKNESS_THRESHOLD then
		return WALL_TRANSPARENCY
	end

	return nil
end

local function getCurrentFloorCutY(rootPart)
	local floorBaseY = math.floor(rootPart.Position.Y / FLOOR_HEIGHT) * FLOOR_HEIGHT
	return floorBaseY + FLOOR_CUT_HEIGHT
end

local function getIndoorOverlapParts(character, rootPart, radius, height)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local size = Vector3.new(radius, height, radius)
	local center = rootPart.Position + Vector3.new(0, height * 0.5, 0)
	return Workspace:GetPartBoundsInBox(CFrame.new(center), size, overlapParams)
end

local function collectUpperFloorParts(character, rootPart)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character }

	local cutY = getCurrentFloorCutY(rootPart)
	local size = Vector3.new(FLOOR_CUT_RADIUS, FLOOR_HEIGHT * 4, FLOOR_CUT_RADIUS)
	local center = Vector3.new(rootPart.Position.X, cutY + size.Y * 0.5, rootPart.Position.Z)
	local parts = Workspace:GetPartBoundsInBox(CFrame.new(center), size, overlapParams)
	local upperFloorParts = {}

	for _, part in ipairs(parts) do
		if part:IsA("BasePart")
			and part.CanCollide
			and not isDoorPart(part)
			and isTaggedBuildingPart(part)
			and part.Position.Y - part.Size.Y * 0.5 > cutY then
			upperFloorParts[part] = UPPER_FLOOR_TRANSPARENCY
		end
	end

	return upperFloorParts
end

local function isPlayerIndoors(character, rootPart)
	local nearbyParts = getIndoorOverlapParts(character, rootPart, INDOOR_WALL_RADIUS, OCCLUSION_CHECK_HEIGHT)
	local nearbyWallCount = 0

	for _, part in ipairs(nearbyParts) do
		if part.CanCollide then
			local targetTransparency = getPartOcclusionTarget(part, rootPart)
			if targetTransparency == ROOF_TRANSPARENCY then
				return true
			end

			if targetTransparency == WALL_TRANSPARENCY then
				nearbyWallCount += 1
				if nearbyWallCount >= INDOOR_WALL_NEARBY_COUNT then
					return true
				end
			end
		end
	end

	return false
end

local function collectRoofParts(character, rootPart)
	local parts = getIndoorOverlapParts(character, rootPart, OCCLUSION_CHECK_RADIUS, OCCLUSION_CHECK_HEIGHT)
	local occludedParts = {}

	for _, part in ipairs(parts) do
		if part.CanCollide then
			local targetTransparency = getPartOcclusionTarget(part, rootPart)
			if targetTransparency == ROOF_TRANSPARENCY then
				occludedParts[part] = targetTransparency
			end
		end
	end

	return occludedParts
end

local function collectWallPartsBetweenCamera(character, rootPart, cameraPosition)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = true

	local occludedParts = {}

	for _, heightOffset in ipairs(WALL_RAY_HEIGHT_OFFSETS) do
		local ignoredInstances = { character }
		raycastParams.FilterDescendantsInstances = ignoredInstances
		local targetPosition = rootPart.Position + Vector3.new(0, heightOffset, 0)
		local origin = cameraPosition
		local direction = targetPosition - origin
		local hits = 0

		while hits < MAX_OCCLUSION_RAYCASTS do
			local result = Workspace:Raycast(origin, direction, raycastParams)
			if not result then
				break
			end

			local part = result.Instance
			if part and part:IsA("BasePart") then
				local targetTransparency = getPartOcclusionTarget(part, rootPart)
				if targetTransparency == WALL_TRANSPARENCY then
					occludedParts[part] = WALL_TRANSPARENCY
				end

				table.insert(ignoredInstances, part)
				raycastParams.FilterDescendantsInstances = ignoredInstances
			end

			hits += 1
			origin = result.Position + direction.Unit * 0.05
			direction = targetPosition - origin

			if direction.Magnitude <= 0.05 then
				break
			end
		end
	end

	return occludedParts
end

local function collectOccludedParts(character, rootPart, cameraPosition, focusPosition)
	local roofParts = collectRoofParts(character, rootPart)
	local wallParts = collectWallPartsBetweenCamera(character, rootPart, cameraPosition)
	local upperFloorParts = collectUpperFloorParts(character, rootPart)

	for part, targetTransparency in pairs(wallParts) do
		roofParts[part] = targetTransparency
	end

	for part, targetTransparency in pairs(upperFloorParts) do
		roofParts[part] = targetTransparency
	end

	return roofParts
end

local function updateOcclusionFade(character, rootPart, cameraPosition, focusPosition, deltaTime)
	if not isPlayerIndoors(character, rootPart) then
		for _, data in pairs(fadedParts) do
			data.target = data.original
		end

		updateOcclusionTransparency(deltaTime)
		return
	end

	local occludedParts = collectOccludedParts(character, rootPart, cameraPosition, focusPosition)

	if next(occludedParts) ~= nil then
		lastOcclusionHitAt = tick()
		markOccludedParts(occludedParts)
	elseif tick() - lastOcclusionHitAt >= OCCLUSION_CLEAR_DELAY then
		for _, data in pairs(fadedParts) do
			data.target = data.original
		end
	end

	updateOcclusionTransparency(deltaTime)
end

local function updateCamera(deltaTime)
	local character, humanoid, rootPart = getCharacterParts()
	if not character or humanoid.Health <= 0 then
		restoreOcclusionTransparency()
		smoothedFocusPosition = nil
		smoothedCameraPosition = nil
		currentCameraDistance = CAMERA_DISTANCE
		currentCameraHeight = CAMERA_HEIGHT
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = CAMERA_FOV

	local isIndoors = isPlayerIndoors(character, rootPart)
	currentYaw = smoothValue(currentYaw, targetYaw, deltaTime, ROTATION_SMOOTHNESS)
	currentCameraDistance = smoothValue(
		currentCameraDistance,
		isIndoors and INDOOR_CAMERA_DISTANCE or CAMERA_DISTANCE,
		deltaTime,
		ZOOM_SMOOTHNESS
	)
	currentCameraHeight = smoothValue(
		currentCameraHeight,
		isIndoors and INDOOR_CAMERA_HEIGHT or CAMERA_HEIGHT,
		deltaTime,
		ZOOM_SMOOTHNESS
	)

	local yaw = math.rad(currentYaw)
	local lookDirection = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	local cameraOffset = (-lookDirection * currentCameraDistance) + Vector3.new(0, currentCameraHeight, 0)
	local focusPosition = rootPart.Position + Vector3.new(0, FOCUS_HEIGHT, 0)
	local targetCameraPosition = focusPosition + cameraOffset

	smoothedFocusPosition = smoothVector(smoothedFocusPosition, focusPosition, deltaTime, POSITION_SMOOTHNESS)
	smoothedCameraPosition = smoothVector(smoothedCameraPosition, targetCameraPosition, deltaTime, POSITION_SMOOTHNESS)

	camera.CFrame = CFrame.lookAt(smoothedCameraPosition, smoothedFocusPosition)
	updateOcclusionFade(character, rootPart, smoothedCameraPosition, smoothedFocusPosition, deltaTime)
end

local function rotateCamera(direction)
	targetYaw += ROTATION_STEP * direction
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == Enum.KeyCode.Q then
		rotateCamera(-1)
	elseif input.KeyCode == Enum.KeyCode.E then
		rotateCamera(1)
	end
end)

player.CharacterRemoving:Connect(function()
	restoreOcclusionTransparency()
end)

RunService:BindToRenderStep("IsometricCamera", Enum.RenderPriority.Camera.Value + 1, updateCamera)
