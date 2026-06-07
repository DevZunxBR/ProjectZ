local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local remoteFolder = ReplicatedStorage:WaitForChild("LootRemotes")
local interactionRemote = remoteFolder:WaitForChild("LootInteraction")

local LOOT_TAG = "LootContainer"
local LOOT_FOLDER_NAME = "Loot"
local DEFAULT_TITLE = "Loot"
local OPEN_SOUND_ID = "rbxassetid://115636166700655"
local CLOSE_SOUND_ID = "rbxassetid://140470748655921"
local TAKE_SOUND_ID = ""
local LOOT_SOUND_VOLUME = 0.6
local MAX_LOOT_DISTANCE = 22

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

local function getLootItems(lootInstance)
	local items = {}
	local folder = getLootFolder(lootInstance)
	if not folder then
		return items
	end

	for _, entry in ipairs(folder:GetChildren()) do
		if entry:IsA("IntValue") or entry:IsA("NumberValue") then
			local count = math.floor(entry.Value)
			if count > 0 then
				table.insert(items, {
					name = entry.Name,
					count = count,
				})
			end
		end
	end

	table.sort(items, function(a, b)
		return a.name < b.name
	end)

	return items
end

local function getLootState(lootInstance)
	return {
		title = lootInstance:GetAttribute("Title") or DEFAULT_TITLE,
		items = getLootItems(lootInstance),
	}
end

local function sendLootState(player, lootInstance, errorMessage, soundId)
	interactionRemote:FireClient(
		player,
		"State",
		lootInstance,
		getLootState(lootInstance),
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

local function takeItem(lootInstance, itemName)
	local folder = getLootFolder(lootInstance)
	if not folder then
		return false
	end

	local entry = folder:FindFirstChild(itemName)
	if not entry or not (entry:IsA("IntValue") or entry:IsA("NumberValue")) then
		return false
	end

	local newCount = math.floor(entry.Value) - 1
	if newCount <= 0 then
		entry:Destroy()
	else
		entry.Value = newCount
	end

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

		local taken = takeItem(lootInstance, itemName)
		if taken then
			sendLootState(player, lootInstance, nil, normalizeSoundId(TAKE_SOUND_ID))
		else
			sendLootState(player, lootInstance, "Item indisponivel.")
		end
		return
	end

	if action == "Close" then
		sendLootState(player, lootInstance, nil, normalizeSoundId(CLOSE_SOUND_ID))
		return
	end
end)
