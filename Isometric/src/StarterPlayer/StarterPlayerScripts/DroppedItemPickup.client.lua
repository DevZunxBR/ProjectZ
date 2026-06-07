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

-- Avisa apenas uma vez se o template manual nao existir.
local warnedMissingTemplate = false

-- Clona o prompt que VOCE cria manualmente em ReplicatedStorage > PickupPrompt.
-- Nada e gerado automaticamente: o design e todo seu.
local function buildPrompt(droppedItem)
	local adornee = getDroppedPart(droppedItem)
	if not adornee then
		return nil
	end

	local template = ReplicatedStorage:FindFirstChild("PickupPrompt")
	if not template or not template:IsA("BillboardGui") then
		if not warnedMissingTemplate then
			warnedMissingTemplate = true
			warn("[DroppedItemPickup] Crie um BillboardGui chamado 'PickupPrompt' em ReplicatedStorage para o prompt aparecer. "
				.. "Opcional: um TextLabel chamado 'ItemLabel' dentro dele recebe o nome do item.")
		end
		return nil
	end

	local billboard = template:Clone()
	billboard.Name = PROMPT_NAME
	billboard.Adornee = adornee
	billboard.Enabled = true
	billboard.Parent = adornee

	-- O texto e 100% manual: o script NAO altera nada do design do prompt.

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

	activePrompt = buildPrompt(droppedItem)
	if activePrompt then
		hoveredItem = droppedItem
	end
end

-- Faz um raycast da camera pelo mouse e devolve o primeiro item dropado encontrado.
local function raycastDroppedItem()
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true

	local character = player.Character
	local ignored = character and { character } or {}
	params.FilterDescendantsInstances = ignored

	for _ = 1, 10 do
		local result = Workspace:Raycast(ray.Origin, ray.Direction * RAY_DISTANCE, params)
		if not result then
			return nil
		end

		local dropped = resolveDroppedItem(result.Instance)
		if dropped then
			return dropped
		end

		-- Ignora o que bateu e continua o raio (ex: parede na frente).
		table.insert(ignored, result.Instance)
		params.FilterDescendantsInstances = ignored
	end

	return nil
end

-- Atualiza o item sob o mouse a cada frame.
RunService.RenderStepped:Connect(function()
	-- Usa raycast (mais confiavel) e cai no mouse.Target como reserva.
	local droppedItem = raycastDroppedItem()
	if not droppedItem then
		local target = mouse.Target
		droppedItem = target and resolveDroppedItem(target) or nil
	end

	if droppedItem and droppedItem.Parent and isInRange(droppedItem) then
		showPromptFor(droppedItem)
	else
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
