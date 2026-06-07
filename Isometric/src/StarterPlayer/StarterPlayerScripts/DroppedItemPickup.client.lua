local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = Workspace.CurrentCamera

local remoteFolder = ReplicatedStorage:WaitForChild("LootRemotes")
-- Crie este RemoteEvent manualmente em ReplicatedStorage > LootRemotes.
local inventoryRemote = remoteFolder:WaitForChild("InventoryRemote")

local DROPPED_TAG = "DroppedItem"
local PICKUP_KEY = Enum.KeyCode.F
local MAX_PICKUP_DISTANCE = 16
local RAY_DISTANCE = 300
local PROMPT_NAME = "DroppedItemPrompt"

-- Item atualmente sob o mouse (com prompt visivel).
local hoveredItem = nil
local activePrompt = nil

local function getDroppedPart(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end

	return nil
end

-- Sobe na hierarquia para achar o item dropado (a tag pode estar num pai).
local function resolveDroppedItem(instance)
	local current = instance
	while current and current ~= Workspace do
		if CollectionService:HasTag(current, DROPPED_TAG) then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function getCharacterRoot()
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function isInRange(droppedItem)
	local rootPart = getCharacterRoot()
	local itemPart = getDroppedPart(droppedItem)
	if not rootPart or not itemPart then
		return false
	end

	return (rootPart.Position - itemPart.Position).Magnitude <= MAX_PICKUP_DISTANCE
end

-- Cria (ou clona) o prompt F customizado preso ao item.
local function buildPrompt(droppedItem, itemName)
	local adornee = getDroppedPart(droppedItem)
	if not adornee then
		return nil
	end

	-- Usa um BillboardGui chamado "PickupPrompt" em ReplicatedStorage, se existir.
	local template = ReplicatedStorage:FindFirstChild("PickupPrompt")
	local billboard

	if template and template:IsA("BillboardGui") then
		billboard = template:Clone()
	else
		billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromOffset(140, 44)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = MAX_PICKUP_DISTANCE + 4

		local frame = Instance.new("Frame")
		frame.Size = UDim2.fromScale(1, 1)
		frame.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
		frame.BackgroundTransparency = 0.25
		frame.BorderSizePixel = 0
		frame.Parent = billboard

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = frame

		local key = Instance.new("TextLabel")
		key.Name = "KeyLabel"
		key.Size = UDim2.fromOffset(28, 28)
		key.Position = UDim2.new(0, 6, 0.5, 0)
		key.AnchorPoint = Vector2.new(0, 0.5)
		key.BackgroundColor3 = Color3.fromRGB(245, 245, 245)
		key.TextColor3 = Color3.fromRGB(20, 20, 24)
		key.Font = Enum.Font.GothamBold
		key.TextSize = 18
		key.Text = "F"
		key.Parent = frame

		local keyCorner = Instance.new("UICorner")
		keyCorner.CornerRadius = UDim.new(0, 6)
		keyCorner.Parent = key

		local label = Instance.new("TextLabel")
		label.Name = "ItemLabel"
		label.Size = UDim2.new(1, -44, 1, 0)
		label.Position = UDim2.fromOffset(40, 0)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(245, 245, 245)
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = "Pegar"
		label.Parent = frame
	end

	billboard.Name = PROMPT_NAME
	billboard.Adornee = adornee
	billboard.Parent = adornee

	-- Atualiza o texto do item, se houver um label conhecido.
	local itemLabel = billboard:FindFirstChild("ItemLabel", true)
	if itemLabel and itemLabel:IsA("TextLabel") then
		itemLabel.Text = ("Pegar %s"):format(itemName or "item")
	end

	return billboard
end

local function clearPrompt()
	if activePrompt then
		activePrompt:Destroy()
		activePrompt = nil
	end
	hoveredItem = nil
end

local function showPromptFor(droppedItem)
	if droppedItem == hoveredItem then
		return
	end

	clearPrompt()

	local itemName = droppedItem:GetAttribute("ItemName")
	activePrompt = buildPrompt(droppedItem, itemName)
	if activePrompt then
		hoveredItem = droppedItem
	end
end

-- Atualiza o item sob o mouse a cada frame.
RunService.RenderStepped:Connect(function()
	local target = mouse.Target
	local droppedItem = target and resolveDroppedItem(target) or nil

	if droppedItem and isInRange(droppedItem) and droppedItem.Parent then
		showPromptFor(droppedItem)
	else
		clearPrompt()
	end

	-- Some o prompt se o item sair de alcance enquanto o mouse continua nele.
	if hoveredItem and (not hoveredItem.Parent or not isInRange(hoveredItem)) then
		clearPrompt()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode ~= PICKUP_KEY then
		return
	end

	if hoveredItem and hoveredItem.Parent and isInRange(hoveredItem) then
		inventoryRemote:FireServer("Pickup", hoveredItem)
		clearPrompt()
	end
end)
