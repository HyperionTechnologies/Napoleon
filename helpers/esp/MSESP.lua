--!nocheck
--!nolint UnknownGlobal
--[[

		▄▄▄▄███▄▄▄▄      ▄████████         ▄████████    ▄████████    ▄███████▄
		▄██▀▀▀███▀▀▀██▄   ███    ███        ███    ███   ███    ███   ███    ███
		███   ███   ███   ███    █▀         ███    █▀    ███    █▀    ███    ███
		███   ███   ███   ███              ▄███▄▄▄       ███          ███    ███
		███   ███   ███ ▀███████████      ▀▀███▀▀▀     ▀███████████ ▀█████████▀
		███   ███   ███          ███        ███    █▄           ███   ███
		███   ███   ███    ▄█    ███        ███    ███    ▄█    ███   ███
		▀█   ███   █▀   ▄████████▀         ██████████  ▄████████▀   ▄████▀
								   v2.1.3

						Created by mstudio45 (Discord)
				Contributors: Dottik, Master Oogway, deividcomsono
						https://docs.mstudio45.com/
--]]

--[[
	Trimmed build. Differences from stock v2.1.3:

	  - Removed: Box3D, Tracer, the Highlighter component and with it every
	    ESPType (Highlight/chams, SelectionBox, Sphere/Cylinder/Adornment), and
	    the whole Rainbow system including its second RenderStepped loop.
	    ESPType is still accepted on Add() so old loaders don't error, but it no
	    longer does anything.
	  - Kept: Box2D, Skeleton, off-screen Arrows.
	  - Text: was one BillboardGui pinned to the model in 3D, which is why the
	    name and distance both sat in the middle of the player. Now two
	    screen-space labels hung off the 2D box - name above it, distance below -
	    and the distance reads in metres rather than studs.
	    StudsOffset is gone with the billboard; it had nothing left to offset.
	  - Added: a Health component. Vertical bar down the left of the 2D box,
	    green to red, sized off the same bounds so the two can't drift apart.
	  - Added: a weapon line, under the distance. The library has no idea what a
	    weapon is in your game, so ESPSettings.Weapon is either a string or a
	    function it calls each frame - the caller does the looking up.
	  - Added: Box2D.Corner, which draws the box as four corner brackets instead
	    of a closed rectangle. Same frame, same bounds, eight child frames.
	  - GetModelCorners now runs once per ESP per frame in Render, and Box2D,
	    Text and Health all read the result. It used to be eight projections per
	    component that wanted a box to hang off.

	The box is still traced from the model's bounding-box corners, so it changes
	size with the camera angle. That is deliberate - it always contains the model.
--]]

local getgenv = getgenv or function() return shared end

local VERSION = "2.1.3";
local DEBUG_ENABLED = getgenv().mstudio45_ESP_DEBUG == true;

local debug_print = if DEBUG_ENABLED then (function(...) print("[mstudio45's ESP]", ...) end) else (function() end);
local debug_warn  = if DEBUG_ENABLED then (function(...) warn("[mstudio45's ESP]", ...) end) else (function() end);
-- local debug_error = if DEBUG_ENABLED then (function(...) error("[mstudio45's ESP] " .. table.concat({ ... }, " ")) end) else (function() end);

if getgenv().mstudio45_ESP then
	debug_warn("Already loaded, returning currently loaded Library table.")
	return getgenv().mstudio45_ESP
end

-- // Type Definitions // --
export type ArrowESPSettings = {
	Enabled: boolean,

	Color: Color3?,
	CenterOffset: number?,
}

export type Box2DESPSettings = {
	Enabled: boolean,

	Color: Color3?,
	Thickness: number?,
	Transparency: number?,
	Filled: boolean?,

	Corner: boolean?,
	CornerSize: number?,
}

export type SkeletonESPSettings = {
	Enabled: boolean,

	Color: Color3?,
	Thickness: number?,
	Transparency: number?,
}

export type HealthESPSettings = {
	Enabled: boolean,

	Width: number?,
	Offset: number?,

	FullColor: Color3?,
	MidColor: Color3?,
	EmptyColor: Color3?,
}

export type ESPSettings = {
	Name: string,
	Model: Object,
	TextModel: Object?,

	-- // General Settings // --
	Visible: boolean?,
	Color: Color3?,
	MaxDistance: number?,

	TextSize: number?,

	-- A string, or a function called every frame and handed the ESP instance.
	-- Anything else (including nil) hides the line.
	Weapon: (string | (ESPInstance) -> string?)?,

	-- // Components // --
	Arrow: ArrowESPSettings?,
	Box2D: Box2DESPSettings?,
	Skeleton: SkeletonESPSettings?,
	Health: HealthESPSettings?,

	-- // Callbacks // --
	OnDestroy: BindableEvent?,
	OnDestroyFunc: (() -> nil)?,

	BeforeUpdate: ((self: ESPSettings) -> nil)?,
	AfterUpdate: ((self: ESPSettings) -> nil)?
}

export type ESPInstance = {
	Index: string,
	Hidden: boolean,
	Deleted: boolean,

	OriginalSettings: ESPSettings,
	CurrentSettings: ESPSettings,

	Connections: { RBXScriptConnection },
	Components: {},

	Show: (self, Force: boolean?) -> nil,
	Hide: (self, Force: boolean?) -> nil,
	ToggleVisibility: (self, Force: boolean?) -> nil,
	SetEveryColor: (self, Color: Color3, IncludeComponents: boolean) -> nil,
	Destroy: (self) -> nil
}

local DefaultSettings: ESPSettings = {
	Name = "New ESP",
	Model = nil,
	TextModel = nil,

	-- // General Settings // --
	Visible = true,
	Color = Color3.new(1, 1, 1),
	MaxDistance = 5000,

	TextSize = 16,

	-- Not in stock. Nothing in here knows what a weapon is in your game, so this
	-- is whatever the caller wants it to be: a plain string, or a function that
	-- gets handed the ESP instance and returns one.
	Weapon = nil,

	-- // Components // --
	Arrow = {
		Enabled = false,
		Color = Color3.new(1, 1, 1),
		CenterOffset = 300,
	},

	Box2D = {
		Enabled = false,
		Color = Color3.new(1, 1, 1),
		Thickness = 1,
		Transparency = 0,
		Filled = false,

		-- Four brackets instead of a closed rectangle. CornerSize is the length of
		-- each arm as a fraction of that side, clamped to half so two arms on the
		-- same edge can never meet in the middle and quietly become a full box.
		Corner = false,
		CornerSize = 0.25,
	},
	Skeleton = {
		Enabled = false,
		Color = Color3.new(1, 1, 1),
		Thickness = 1,
		Transparency = 0,
	},

	-- // Not in stock. Needs a Humanoid in the Model - without one the
	-- component isn't created at all. Sizes itself off the 2D box's bounds, so
	-- it lines up whether or not the box itself is being drawn.
	Health = {
		Enabled = false,
		Width = 4, -- px, the coloured part only
		Offset = 3, -- px between the bar's outline and the box's left edge

		FullColor = Color3.fromRGB(0, 255, 0),
		MidColor = Color3.fromRGB(255, 255, 0),
		EmptyColor = Color3.fromRGB(255, 0, 0),
	},

	-- // Callbacks // --
	OnDestroy = nil,
	OnDestroyFunc = nil,

	BeforeUpdate = nil,
	AfterUpdate = nil,
}

-- // Executor Variables // --
local cloneref = getgenv().cloneref or function(inst) return inst; end

-- // GUI Variables // --
local GuiParent, StorageParent;
local CoreGuiAllowed = false;
local RobloxStorageAllowed = false;

-- // Services // --
local RobloxReplicatedStorage = nil
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))

-- // Core Functions // --
local table_freeze = function<T>(provided_table: T): T
	local data = table.clone(provided_table)

	return setmetatable({}, {
		__index = function(table, key) return rawget(data, key) end,
		__newindex = function(table, key, value) end,
		__iter = function(_) return next, data end,
		__metatable = "The metatable is locked"
	}) :: typeof(provided_table)
end

-- // Functions // --
local function GetPivot(Instance: Bone | Attachment | CFrame | PVInstance)
	if Instance.ClassName == "Bone" then
		return Instance.TransformedWorldCFrame

	elseif Instance.ClassName == "Attachment" then
		return Instance.WorldCFrame

	elseif Instance.ClassName == "Camera" then
		return Instance.CFrame

	else
		return Instance:GetPivot()
	end
end

local function RandomString(name: string?)
	if DEBUG_ENABLED and name then
		return name
	end

	local length = math.random(10, 20)
	local array = {}

	for i = 1, length do
		array[i] = string.char(math.random(32, 126))
	end

	return table.concat(array)
end

local function SafeCallback(Func: (...any) -> ...any, ...: any)
	if not (Func and typeof(Func) == "function") then
		return
	end

	local Result = table.pack(xpcall(Func, function(Error)
		task.defer(error, debug.traceback(Error, 2))
		return Error
	end, ...))

	if not Result[1] then
		return nil
	end

	return table.unpack(Result, 2, Result.n)
end

local Validate; Validate = function(Table: { [string]: any }, Template: { [string]: any }): { [string]: any }
	if typeof(Table) ~= "table" then
		return Template
	end

	for k, v in Template do
		if typeof(k) == "number" then
			continue
		end

		if typeof(v) == "table" then
			Table[k] = Validate(Table[k], v)
		elseif Table[k] == nil then
			Table[k] = v
		end
	end

	return Table
end

-- // Instances // --
local InstancesLib = {
	Create = function(instanceType, properties)
		assert(typeof(instanceType) == "string", "Argument #1 must be a string.")
		assert(typeof(properties) == "table", "Argument #2 must be a table.")

		local instance = Instance.new(instanceType)
		for name, val in properties do
			if name == "Parent" then
				continue -- // Parenting is expensive, do last.
			end

			if instanceType == "Path2D" and name == "Transparency" and not CoreGuiAllowed then
				continue -- // Locked behind RobloxSecurity (why roblox?)
			end

			instance[name] = val
		end

		if properties["Parent"] ~= nil then
			instance.Parent = properties["Parent"]
		end

		return instance
	end,

	TryGetProperty = function(instance, propertyName)
		assert(typeof(instance) == "Instance", "Argument #1 must be an Instance.")
		assert(typeof(propertyName) == "string", "Argument #2 must be a string.")

		local success, property = pcall(function()
			return instance[propertyName]
		end)

		return if success then property else nil;
	end,

	FindPrimaryPart = function(instance)
		if typeof(instance) ~= "Instance" then
			return nil
		end

		return (instance:IsA("Model") and instance.PrimaryPart or nil)
			or instance:FindFirstChildWhichIsA("BasePart")
			or instance:FindFirstChildWhichIsA("UnionOperation")
			or instance;
	end,

	DistanceFrom = function(inst, from)
		if not (inst and from) then
			return 9e9;
		end

		local position     = if typeof(inst) == "Instance" then GetPivot(inst).Position else inst;
		local fromPosition = if typeof(from) == "Instance" then GetPivot(from).Position else from;
		return (fromPosition - position).Magnitude;
	end
}

-- // Thread Identity Test // --
do
	--// Test
	local testGui = Instance.new("ScreenGui")
	local successCoreGui = pcall(function()
		if not CoreGui then error("CoreGui is nil") end

		testGui.Parent = CoreGui;
	end)

	local testFolder = Instance.new("Folder")
	local successStorage = pcall(function(...)
		RobloxReplicatedStorage = cloneref(game:GetService("RobloxReplicatedStorage"))

		testFolder.Parent = RobloxReplicatedStorage
	end)

	CoreGuiAllowed = successCoreGui and CoreGui ~= nil;
	RobloxStorageAllowed = successStorage and RobloxReplicatedStorage ~= nil;

	--// UI
	if CoreGuiAllowed then
		GuiParent = CoreGui;
	else
		debug_warn("CoreGui is not accessible!")
		GuiParent = Players.LocalPlayer.PlayerGui;
	end

	--// Storage
	if RobloxStorageAllowed then
		StorageParent = RobloxReplicatedStorage;
	else
		debug_warn("RobloxReplicatedStorage is not accessible!")
		StorageParent = ReplicatedStorage;
	end

	--// Destroy
	testGui:Destroy()
	testFolder:Destroy()
end

-- // Storage // --
local StorageFolder = InstancesLib.Create("Folder", {
	Parent = StorageParent,
	Name = RandomString("StorageFolder")
})

local ActiveFolder = InstancesLib.Create("Folder", {
	Parent = if CoreGuiAllowed then GuiParent else InstancesLib.Create("ScreenGui", {
		Parent = GuiParent,
		Name = RandomString("ActiveContainer"),
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ClipToDeviceSafeArea = false,
		DisplayOrder = 10 -- under the menu (999), like the FOV circles
	}),
	Name = RandomString("ActiveFolder")
})

local MainGUI = InstancesLib.Create("ScreenGui", {
	Parent = GuiParent,
	Name = RandomString("MainGUI"),
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ClipToDeviceSafeArea = false,
	DisplayOrder = 10 -- under the menu (999), like the FOV circles
})

local BillboardGUI = InstancesLib.Create("ScreenGui", {
	Parent = GuiParent,
	Name = RandomString("BillboardGUI"),
	IgnoreGuiInset = true,
	ResetOnSpawn = false,
	ClipToDeviceSafeArea = false,
	DisplayOrder = 10 -- under the menu (999), like the FOV circles
})

-- // Library // --
local Library = {
	Destroyed = false,

	-- // Storages // --
	ActiveFolder = ActiveFolder,
	MainGUI = MainGUI,
	BillboardGUI = BillboardGUI,
	StorageFolder = StorageFolder,

	-- // Connections // --
	Connections = {},

	-- // ESP // --
	ESP = {},

	-- // Global Config // --
	GlobalConfig = {
		IgnoreCharacter = false,

		Billboards = true, -- master switch for the name and distance text
		Distance = true,
		Weapons = true,
		MetersPerStud = 0.28, -- a Roblox stud really is 0.28 m; set 1 for studs
		TextGap = 2, -- px between the box edge and the text

		Arrows = true,
		Boxes2D = true,
		Skeleton = true,
		HealthBars = true,

		Font = Enum.Font.RobotoCondensed,

		-- Not in stock. A turning gradient on the boxes, arrows and text, like the
		-- FOV circles: { Enabled, Colors = { start, middle, end }, Speed = turns a second }
		Gradient = nil,
	}
}

-- // Gradient // --
-- A UIGradient multiplies whatever colour it sits on, so while one is showing, the
-- thing under it goes white (Plain) and the gradient's own colours are what you see.
local Plain = Color3.new(1, 1, 1)

local function ApplyGradient(Gradient: UIGradient): boolean
	local Config = Library.GlobalConfig.Gradient
	local Colors = Config and Config.Enabled == true and Config.Colors

	if not (Colors and #Colors >= 3) then
		if Gradient.Enabled then Gradient.Enabled = false end
		return false
	end

	Gradient.Enabled = true
	Gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Colors[1]),
		ColorSequenceKeypoint.new(0.5, Colors[2]),
		ColorSequenceKeypoint.new(1, Colors[3]),
	})
	Gradient.Rotation = (os.clock() * (Config.Speed or 1) * 360) % 360

	return true
end

function Library:Clear()
	if Library.Destroyed == true then
		return
	end

	for _, ESP in Library.ESP do
		if not ESP then continue end
		ESP:Destroy()
	end

	debug_print("Cleared ESPs.")
end

function Library:Destroy()
	if Library.Destroyed == true then
		return
	end

	-- // Destroy Library // --
	Library:Clear();
	Library.Destroyed = true;

	-- // Destroy Folders // --
	ActiveFolder:Destroy();
	StorageFolder:Destroy();
	MainGUI:Destroy();
	BillboardGUI:Destroy();

	Library.ActiveFolder = nil;
	Library.MainGUI = nil;
	Library.BillboardGUI = nil;
	Library.StorageFolder = nil;

	-- // Clear connections // --
	for _, connection in Library.Connections do
		if connection and connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(Library.Connections)

	-- // Clear getgenv // --
	getgenv().mstudio45_ESP = nil;
	debug_print("Unloaded!");
end

-- // Player Variables // --
local Character: Model?;
local RootPart: Part?;
local Camera: Camera = workspace.CurrentCamera;

local function WorldToViewport(...)
	Camera = (Camera or workspace.CurrentCamera);
	if Camera == nil then
		return Vector2.new(0, 0), false;
	end

	return Camera:WorldToViewportPoint(...);
end

local function UpdatePlayerVariables(newCharacter: Instance?, force: boolean?)
	-- // Update Root Part // --
	if force ~= true and Library.GlobalConfig.IgnoreCharacter == true then
		debug_warn("UpdatePlayerVariables: IgnoreCharacter enabled.");
		return;
	end;

	debug_print("Updating Player Variables...");
	Character = newCharacter or Players.LocalPlayer.Character or Players.LocalPlayer.CharacterAdded:Wait();
	RootPart = Character:WaitForChild("HumanoidRootPart", 2.5) or Character:WaitForChild("UpperTorso", 2.5) or Character:WaitForChild("Torso", 2.5) or Character.PrimaryPart or Character:WaitForChild("Head", 2.5);
end
task.spawn(UpdatePlayerVariables, nil, true);

-- // Helper Functions // --
local function GetModelCorners(Model: Instance?)
	if not Model then
		return false, {}, {}, 0, 0, 0, 0;
	end

	-- // Calculate Bounding Box // --
	local ModelCFrame, ModelSize = nil, nil

	if Model:IsA("Model") then
		ModelCFrame, ModelSize = Model:GetBoundingBox()
	else
		if not InstancesLib.TryGetProperty(Model, "Size") then
			local PrimaryPart = InstancesLib.FindPrimaryPart(Model)

			if InstancesLib.TryGetProperty(PrimaryPart, "Size") then
				ModelCFrame = PrimaryPart.CFrame
				ModelSize = PrimaryPart.Size
			end
		else
			ModelCFrame = Model.CFrame
			ModelSize = Model.Size
		end
	end

	if not (ModelCFrame and ModelSize) then
		return false, {}, {}, 0, 0, 0, 0
	end

	-- // Corners // --
	local sx, sy, sz = ModelSize.X / 2, ModelSize.Y / 2, ModelSize.Z / 2
	local corners = {
		ModelCFrame * Vector3.new(sx, sy, sz),      -- Top Right Back
		ModelCFrame * Vector3.new(sx, sy, -sz),     -- Top Right Front
		ModelCFrame * Vector3.new(sx, -sy, sz),     -- Bottom Right Back
		ModelCFrame * Vector3.new(sx, -sy, -sz),    -- Bottom Right Front

		ModelCFrame * Vector3.new(-sx, sy, sz),     -- Top Left Back
		ModelCFrame * Vector3.new(-sx, sy, -sz),    -- Top Left Front
		ModelCFrame * Vector3.new(-sx, -sy, sz),    -- Bottom Left Back
		ModelCFrame * Vector3.new(-sx, -sy, -sz),   -- Bottom Left Front
	}

	-- // Screen Position for Corners // --
	local screenCorners = {}
	local cornersOnScreen = 0;

	local minX, maxX = math.huge, -math.huge;
	local minY, maxY = math.huge, -math.huge;
	
	for idx, corner in corners do
		local cornerPos, cornerOnScreen = WorldToViewport(corner)
		screenCorners[idx] = cornerPos;

		if not cornerOnScreen then continue end
		cornersOnScreen = cornersOnScreen + 1;

		minX = math.min(minX, cornerPos.X);
		minY = math.min(minY, cornerPos.Y);
		maxX = math.max(maxX, cornerPos.X);
		maxY = math.max(maxY, cornerPos.Y);
	end

	return cornersOnScreen > 0, corners, screenCorners, minX, minY, maxX, maxY;
end

-- // ESP Instances // --
local Components = {}; do
	-- // Text // --
	-- Stock built one BillboardGui per ESP, adorned to the model, holding
	-- "Name\n[distance]" in a single label. Being anchored in 3D it always
	-- landed in the middle of the player. These are plain screen-space labels
	-- positioned off the box bounds instead: the name sits on top of the box and
	-- the distance underneath it, and neither cares where the model's pivot is.
	Components.Text = function(ESP)
		if Library.Destroyed == true then
			debug_warn("Library is destroyed, please reload it.")
			return
		end

		if not ESP then
			return
		end

		debug_print("Creating Text...")

		local function CreateLabel(anchorY)
			return InstancesLib.Create("TextLabel", {
				Parent = BillboardGUI,
				Name = (if DEBUG_ENABLED then "Text_" else "") .. ESP.Index,

				-- AutomaticSize does the measuring, so the label is exactly as wide
				-- as its text and the anchor point alone decides where it lands
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.XY,
				AnchorPoint = Vector2.new(0.5, anchorY),

				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 5,

				Text = "",
				Font = Library.GlobalConfig.Font,
				TextSize = ESP.CurrentSettings.TextSize,
				TextColor3 = ESP.CurrentSettings.Color,
				TextStrokeColor3 = Color3.new(),
				TextStrokeTransparency = 0.4,
			})
		end

		local function AddGradient(Label)
			return InstancesLib.Create("UIGradient", { Parent = Label, Enabled = false })
		end

		-- anchor 1 = grows upward from the given Y, anchor 0 = downward
		local NameLabel = CreateLabel(1)
		local DistanceLabel = CreateLabel(0)
		local WeaponLabel = CreateLabel(0)

		local NameGradient = AddGradient(NameLabel)
		local DistanceGradient = AddGradient(DistanceLabel)
		local WeaponGradient = AddGradient(WeaponLabel)

		local LastName, LastMeters, LastWeapon

		-- // Text Data // --
		local TextData = {}
		TextData.Destroy = function(self)
			if NameLabel then NameLabel:Destroy(); NameLabel = nil; end
			if DistanceLabel then DistanceLabel:Destroy(); DistanceLabel = nil; end
			if WeaponLabel then WeaponLabel:Destroy(); WeaponLabel = nil; end
		end;

		TextData.Update = function(self)
			if not (NameLabel and DistanceLabel and WeaponLabel) then return end

			-- // ESP Settings // --
			if not ESP._LastScreenPos then return end

			local ESPSettings = ESP.CurrentSettings
			local _screenPos, isOnScreen = unpack(ESP._LastScreenPos)

			local TextEnabled = isOnScreen == true
				and Library.GlobalConfig.Billboards == true
				and ESP._BoundsOK == true

			if not TextEnabled then
				if NameLabel.Visible then NameLabel.Visible = false end
				if DistanceLabel.Visible then DistanceLabel.Visible = false end
				if WeaponLabel.Visible then WeaponLabel.Visible = false end
				return
			end

			local centerX = (ESP._MinX + ESP._MaxX) * 0.5
			local gap = Library.GlobalConfig.TextGap or 2
			local gradient = ApplyGradient(NameGradient)
			ApplyGradient(DistanceGradient)
			ApplyGradient(WeaponGradient)

			local color = if gradient then Plain else ESPSettings.Color
			local font = Library.GlobalConfig.Font
			local small = math.max(ESPSettings.TextSize - 3, 1)

			-- // Name, on top of the box // --
			NameLabel.Visible = true
			NameLabel.Position = UDim2.fromOffset(centerX, ESP._MinY - gap)
			NameLabel.TextColor3 = color
			NameLabel.TextSize = ESPSettings.TextSize
			NameLabel.Font = font

			-- guarded: setting Text re-measures the label, and a name never changes
			if LastName ~= ESPSettings.Name then
				LastName = ESPSettings.Name
				NameLabel.Text = ESPSettings.Name
			end

			-- Everything under the box stacks, so each line that draws pushes the next
			-- one down by its own height. AbsoluteSize is zero until the label has been
			-- laid out once, so TextSize stands in for it on that first frame - without
			-- that the weapon line starts on top of the distance and jumps.
			local below = ESP._MaxY + gap

			-- // Distance, under the box // --
			if Library.GlobalConfig.Distance == true then
				DistanceLabel.Visible = true
				DistanceLabel.Position = UDim2.fromOffset(centerX, below)
				DistanceLabel.TextColor3 = color
				DistanceLabel.TextSize = small
				DistanceLabel.Font = font

				-- stock printed math.floor(studs). A stud is 0.28 m.
				local meters = math.floor(
					(ESP._LastDistance or 0) * (Library.GlobalConfig.MetersPerStud or 0.28) + 0.5
				)

				if LastMeters ~= meters then
					LastMeters = meters
					DistanceLabel.Text = string.format("%d m", meters)
				end

				below = below + math.max(DistanceLabel.AbsoluteSize.Y, small)
			elseif DistanceLabel.Visible then
				DistanceLabel.Visible = false
			end

			-- // Weapon, under that // --
			-- Nothing in this library knows what a weapon is, so Weapon is whatever the
			-- caller made it: a string, or a function asked every frame. The function
			-- form is pcall'd because it is somebody else's code running inside our
			-- render loop, and a mistake in it should cost one blank line, not the ESP.
			local weapon = ESPSettings.Weapon

			if type(weapon) == "function" then
				local ok, result = pcall(weapon, ESP)
				weapon = ok and result or nil
			end

			if Library.GlobalConfig.Weapons ~= true or type(weapon) ~= "string" or weapon == "" then
				if WeaponLabel.Visible then WeaponLabel.Visible = false end
				return
			end

			WeaponLabel.Visible = true
			WeaponLabel.Position = UDim2.fromOffset(centerX, below)
			WeaponLabel.TextColor3 = color
			WeaponLabel.TextSize = small
			WeaponLabel.Font = font

			if LastWeapon ~= weapon then
				LastWeapon = weapon
				WeaponLabel.Text = weapon
			end
		end;

		return setmetatable({}, {
			__newindex = function(table, key, value)
				if not NameLabel then return end

				if key == "Visible" then
					assert(
						typeof(value) == "boolean",
						string.format("Visible; expected boolean, got %s", typeof(value))
					);

					NameLabel.Visible = value;
					DistanceLabel.Visible = value;
					WeaponLabel.Visible = value;
				else
					rawset(TextData, key, value);
				end
			end,

			__index = function(table, key)
				if not NameLabel then return nil end

				if key == "Visible" then
					return NameLabel.Visible;
				else
					return rawget(TextData, key);
				end
			end,

			__iter = function(_) return next, TextData end,
			__metatable = "The metatable is locked"
		}) :: typeof(TextData)
	end

	-- // Health // --
	-- Not in stock, which had no health bar of any kind. Two frames: a black
	-- backing sized to the box's outline, and a fill inset 1px inside it that
	-- grows from the bottom. Both come off the shared bounds, so the bar and the
	-- box can't drift apart.
	Components.Health = function(ESP)
		if Library.Destroyed == true then
			debug_warn("Library is destroyed, please reload it.")
			return
		end

		if not ESP then
			return
		end

		if not ESP.CurrentSettings.Health.Enabled then
			return
		end

		local Humanoid = ESP.CurrentSettings.Model:FindFirstChildWhichIsA("Humanoid")
		if not Humanoid then
			debug_warn("No Humanoid on", ESP.CurrentSettings.Name, "- skipping health bar.")
			return
		end

		debug_print("Creating Health...")

		local Outline = InstancesLib.Create("Frame", {
			Parent = MainGUI,
			Name = (if DEBUG_ENABLED then "Health_" else "") .. ESP.Index,

			BackgroundColor3 = Color3.new(),
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,
		})

		-- anchored to its own bottom-left, 1px in from the backing on every side
		local Fill = InstancesLib.Create("Frame", {
			Parent = Outline,
			Name = "Fill",

			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 1, 1, -1),

			BackgroundColor3 = Color3.fromRGB(0, 255, 0),
			BorderSizePixel = 0,
			ZIndex = 3,
		})

		local function HealthColor(pct)
			local cfg = ESP.CurrentSettings.Health
			if pct > 0.5 then
				return cfg.MidColor:Lerp(cfg.FullColor, (pct - 0.5) * 2)
			end
			return cfg.EmptyColor:Lerp(cfg.MidColor, pct * 2)
		end

		-- // Health Data // --
		local HealthData = {}
		HealthData.Destroy = function(self)
			if not Outline then return end

			Outline:Destroy();
			Outline = nil;
			Fill = nil;
		end;

		HealthData.Update = function(self)
			if not Outline then return end

			-- // ESP Settings // --
			if not ESP._LastScreenPos then return end

			local ESPSettings = ESP.CurrentSettings;
			local _, isOnScreen = unpack(ESP._LastScreenPos);

			local HealthEnabled = isOnScreen == true
				and Library.GlobalConfig.HealthBars == true
				and ESPSettings.Health.Enabled == true
				and ESP._BoundsOK == true
				and Humanoid.Parent ~= nil

			if not HealthEnabled then
				if Outline.Visible then Outline.Visible = false end
				return
			end

			local barW = math.max(ESPSettings.Health.Width or 4, 1)
			local barH = math.max(ESP._MaxY - ESP._MinY, 1)
			local gap = ESPSettings.Health.Offset or 3

			-- // Update Position // --
			Outline.Visible = true
			Outline.Position = UDim2.fromOffset(ESP._MinX - gap - barW - 2, ESP._MinY - 1)
			Outline.Size = UDim2.fromOffset(barW + 2, barH + 2)

			-- // Update Visuals // --
			local maxHealth = Humanoid.MaxHealth
			local pct = if maxHealth > 0 then math.clamp(Humanoid.Health / maxHealth, 0, 1) else 0

			Fill.Size = UDim2.fromOffset(barW, barH * pct)
			Fill.BackgroundColor3 = HealthColor(pct)
		end;

		return setmetatable({}, {
			__newindex = function(table, key, value)
				if not Outline then return end

				if key == "Visible" then
					assert(
						typeof(value) == "boolean",
						string.format("Visible; expected boolean, got %s", typeof(value))
					);

					Outline.Visible = value;
				else
					rawset(HealthData, key, value);
				end
			end,

			__index = function(table, key)
				if not Outline then return nil end

				if key == "Visible" then
					return Outline.Visible;
				else
					return rawget(HealthData, key);
				end
			end,

			__iter = function(_) return next, HealthData end,
			__metatable = "The metatable is locked"
		}) :: typeof(HealthData)
	end

	-- // Arrow // --
	Components.Arrow = function(ESP)
		if Library.Destroyed == true then
			debug_warn("Library is destroyed, please reload it.")
			return
		end
		
		if not ESP then 
			return
		end

		if not ESP.CurrentSettings.Arrow.Enabled then
			return
		end

		-- // Create Arrow // --
		debug_print("Creating Arrow...")

		local Arrow = InstancesLib.Create("ImageLabel", {
			Parent = MainGUI,
			Name = (if DEBUG_ENABLED then "Arrow_" else "") .. ESP.Index,

			Size = UDim2.new(0, 48, 0, 48),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,

			AnchorPoint = Vector2.new(0.5, 0.5),

			BackgroundTransparency = 1,
			BorderSizePixel = 0,

			Image = "http://www.roblox.com/asset/?id=16368985219",
			ImageColor3 = ESP.CurrentSettings.Color or Color3.new(),
		});

		local ArrowGradient = InstancesLib.Create("UIGradient", { Parent = Arrow, Enabled = false })

		-- // Arrow Data // --
		local ArrowData = { }
		ArrowData.Destroy = function(self)
			if not Arrow then return end
			
			Arrow:Destroy();
			Arrow = nil;
		end;

		ArrowData.Update = function(self)
			if not Arrow then return end

			-- // ESP Settings // --
			if not ESP._LastScreenPos then return end

			local ESPSettings = ESP.CurrentSettings;
			local screenPos, isOnScreen = unpack(ESP._LastScreenPos);
			local ArrowEnabled = isOnScreen == false and (Library.GlobalConfig.Arrows == true and ESPSettings.Arrow.Enabled == true);
			
			Arrow.Visible = ArrowEnabled;
			if not ArrowEnabled then return end

			-- // Update Visuals // --
			local screenSize = Camera.ViewportSize
			local centerPos = Vector2.new(screenSize.X / 2, screenSize.Y / 2)

			-- use aspect to make oval circle
			-- local aspectRatioX = screenSize.X / screenSize.Y;
			-- local aspectRatioY = screenSize.Y / screenSize.X;
			-- local arrowPosPixel = Vector2.new(arrowTable.ArrowInstance.Position.X.Scale, arrowTable.ArrowInstance.Position.Y.Scale) * 1000;
			local partPos = Vector2.new(screenPos.X, screenPos.Y);

			local IsInverted = screenPos.Z <= 0;
			local invert = (IsInverted and -1 or 1);

			local direction = (partPos - centerPos);
			local arctan = math.atan2(direction.Y, direction.X);
			local angle = math.deg(arctan) + 90;
			local distance = (ESPSettings.Arrow.CenterOffset * 0.001) * screenSize.Y;

			-- // Update Position // --
			Arrow.Rotation = angle + 180 * (IsInverted and 0 or 1);
			Arrow.Position = UDim2.fromOffset(
				centerPos.X + (distance * math.cos(arctan) * invert),
				centerPos.Y + (distance * math.sin(arctan) * invert)
			);

			-- // Update Visuals // --
			Arrow.ImageColor3 = if ApplyGradient(ArrowGradient) then Plain else ESPSettings.Arrow.Color;
		end;

		return setmetatable({}, {
			__newindex = function(table, key, value)
				if not Arrow then return end

				if key == "Visible" then
					assert(
						typeof(value) == "boolean", 
						string.format("Visible; expected boolean, got %s", typeof(value))
					);

					Arrow.Visible = value;
				else
					rawset(ArrowData, key, value);
				end
			end,

			__index = function(table, key)
				if not Arrow then return nil end
				
				if key == "Visible" then
					return Arrow.Visible;
				else
					return rawget(ArrowData, key);
				end
			end,

			__iter = function(_) return next, ArrowData end,
			__metatable = "The metatable is locked"
		}) :: typeof(ArrowData)
	end

	-- // Box2D // --
	Components.Box2D = function(ESP)
		if Library.Destroyed == true then
			debug_warn("Library is destroyed, please reload it.")
			return
		end
		
		if not ESP then 
			return
		end

		if not ESP.CurrentSettings.Box2D.Enabled then
			return
		end

		debug_print("Creating Box2D...")

		-- // Create Frame // --
		local Frame = InstancesLib.Create("Frame", {
			Parent = MainGUI,
			Name = (if DEBUG_ENABLED then "Box2D_" else "") .. ESP.Index,

			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 2,

			-- // Settings // --
			BackgroundColor3 = ESP.CurrentSettings.Box2D.Color
		})
	
		local UIStroke = InstancesLib.Create("UIStroke", {
			Parent = Frame,

			-- // Settings // --
			Color = ESP.CurrentSettings.Box2D.Color,
			Thickness = ESP.CurrentSettings.Box2D.Thickness,
			Transparency = ESP.CurrentSettings.Box2D.Transparency,
		})

		local StrokeGradient = InstancesLib.Create("UIGradient", { Parent = UIStroke, Enabled = false })
		local FillGradient = InstancesLib.Create("UIGradient", { Parent = Frame, Enabled = false })

		-- // Corner brackets // --
		-- Eight frames parented to the box, so they move and resize with it and the
		-- bounds only have to be worked out in one place. Two arms per corner; the
		-- anchor point and the scale position are what put each one in its corner and
		-- never change, so Update only ever writes a size and a colour.
		local ArmSpec = {
			{ Anchor = Vector2.new(0, 0), Pos = UDim2.fromScale(0, 0), Across = true },
			{ Anchor = Vector2.new(0, 0), Pos = UDim2.fromScale(0, 0), Across = false },
			{ Anchor = Vector2.new(1, 0), Pos = UDim2.fromScale(1, 0), Across = true },
			{ Anchor = Vector2.new(1, 0), Pos = UDim2.fromScale(1, 0), Across = false },
			{ Anchor = Vector2.new(0, 1), Pos = UDim2.fromScale(0, 1), Across = true },
			{ Anchor = Vector2.new(0, 1), Pos = UDim2.fromScale(0, 1), Across = false },
			{ Anchor = Vector2.new(1, 1), Pos = UDim2.fromScale(1, 1), Across = true },
			{ Anchor = Vector2.new(1, 1), Pos = UDim2.fromScale(1, 1), Across = false },
		}

		local Arms = {}
		local ArmGradients = {}

		for Index, Spec in ipairs(ArmSpec) do
			Arms[Index] = InstancesLib.Create("Frame", {
				Parent = Frame,
				Name = "Corner",

				AnchorPoint = Spec.Anchor,
				Position = Spec.Pos,
				Size = UDim2.fromOffset(0, 0),

				BackgroundColor3 = ESP.CurrentSettings.Box2D.Color,
				BorderSizePixel = 0,
				Visible = false,
				ZIndex = 3,
			})

			ArmGradients[Index] = InstancesLib.Create("UIGradient", { Parent = Arms[Index], Enabled = false })
		end

		-- // Box2D Data // --
		local Box2DData = {}
		Box2DData.Destroy = function(self)
			if not Frame then return end
			
			Frame:Destroy();
			Frame = nil;
		end;

		Box2DData.Update = function(self)
			if not Frame then return end

			-- // ESP Settings // --
			if not ESP._LastScreenPos then return end

			local ESPSettings = ESP.CurrentSettings;
			local _, isOnScreen = unpack(ESP._LastScreenPos);
			local Box2DEnabled = isOnScreen == true and (Library.GlobalConfig.Boxes2D == true and ESPSettings.Box2D.Enabled == true);

			Frame.Visible = Box2DEnabled
			if not Box2DEnabled then return end

			-- // Corners // --
			-- Worked out once per frame in ESP:Render and shared with the text and
			-- the health bar. This used to call GetModelCorners itself.
			if ESP._BoundsOK ~= true then
				Frame.Visible = false
				return
			end

			local minX, minY, maxX, maxY = ESP._MinX, ESP._MinY, ESP._MaxX, ESP._MaxY

			-- // Update Position // --
			Frame.Position = UDim2.fromOffset(minX, minY)
			Frame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
			Frame.Visible = true
			
			-- // Update Visuals // --
			local corner = ESPSettings.Box2D.Corner == true
			local transparency = ESPSettings.Box2D.Transparency or 0

			local gradient = ApplyGradient(StrokeGradient)
			ApplyGradient(FillGradient)

			local boxColor = if gradient then Plain else ESPSettings.Box2D.Color

			Frame.BackgroundColor3 = boxColor;
			UIStroke.Color = boxColor;
			UIStroke.Thickness = ESPSettings.Box2D.Thickness;

			-- The stroke is the closed rectangle, so corner mode is it stepping aside
			-- for the arms. Filled still works either way - that is the frame itself.
			UIStroke.Transparency = if corner then 1 else transparency;
			Frame.BackgroundTransparency = if ESPSettings.Box2D.Filled then 0.5 else 1;

			if not corner then
				for _, Arm in ipairs(Arms) do
					if Arm.Visible then Arm.Visible = false end
				end

				return
			end

			local thickness = math.max(ESPSettings.Box2D.Thickness or 1, 1)

			-- Half is the ceiling: at exactly half the two arms on an edge meet and the
			-- brackets quietly become the closed box they were meant to replace
			local fraction = math.clamp(ESPSettings.Box2D.CornerSize or 0.25, 0.05, 0.5)

			local armX = math.max((maxX - minX) * fraction, thickness)
			local armY = math.max((maxY - minY) * fraction, thickness)

			for Index, Spec in ipairs(ArmSpec) do
				local Arm = Arms[Index]

				Arm.Visible = true
				ApplyGradient(ArmGradients[Index])
				Arm.BackgroundColor3 = boxColor
				Arm.BackgroundTransparency = transparency
				Arm.Size = if Spec.Across
					then UDim2.fromOffset(armX, thickness)
					else UDim2.fromOffset(thickness, armY)
			end
		end;

		return setmetatable({}, {
			__newindex = function(table, key, value)
				if not Frame then return end

				if key == "Visible" then
					assert(
						typeof(value) == "boolean", 
						string.format("Visible; expected boolean, got %s", typeof(value))
					);

					Frame.Visible = value;
				else
					rawset(Box2DData, key, value);
				end
			end,

			__index = function(table, key)
				if not Frame then return nil end
				
				if key == "Visible" then
					return Frame.Visible;
				else
					return rawget(Box2DData, key);
				end
			end,

			__iter = function(_) return next, Box2DData end,
			__metatable = "The metatable is locked"
		}) :: typeof(Box2DData)
	end

	-- // Skeleton // --
	local R15Sequence = {
		-- Root
		"LowerTorso",

		-- Left Leg
		"LeftUpperLeg",
		"LeftLowerLeg",
		"LeftFoot",
		"LeftLowerLeg",
		"LeftUpperLeg",
		"LowerTorso",

		-- Right Leg
		"RightUpperLeg",
		"RightLowerLeg",
		"RightFoot",
		"RightLowerLeg",
		"RightUpperLeg",
		"LowerTorso",

		-- Up torso
		"UpperTorso",

		-- Left Arm
		"LeftUpperArm",
		"LeftLowerArm",
		"LeftHand",
		"LeftLowerArm",
		"LeftUpperArm",
		"UpperTorso",

		-- Right Arm
		"RightUpperArm",
		"RightLowerArm",
		"RightHand",
		"RightLowerArm",
		"RightUpperArm",
		"UpperTorso",

		-- Finish
		"Head"
	}

	local R6Sequence = {
		"Torso",

		-- Left Arm
		"Left Arm",
		"Torso",

		-- Right Arm
		"Right Arm",
		"Torso",

		-- Left Leg
		"Left Leg",
		"Torso",

		-- Right Leg
		"Right Leg",
		"Torso",

		-- Head
		"Head"
	}

	Components.Skeleton = function(ESP)
		if Library.Destroyed == true then
			debug_warn("Library is destroyed, please reload it.")
			return
		end
		
		if not ESP then 
			return
		end

		if not ESP.CurrentSettings.Skeleton.Enabled then
			return
		end

		debug_print("Creating Skeleton...")

		-- // Detect Rig Type and Get Joints // --
		local Model = ESP.CurrentSettings.Model
		local RigType = "Unknown"

		if Model:FindFirstChild("Humanoid") then
			if Model.Humanoid.RigType == Enum.HumanoidRigType.R15 then
				RigType = "R15"
			else
				RigType = "R6"
			end
		end

		if RigType == "Unknown" then
			debug_warn("Could not detect rig type for", ESP.CurrentSettings.Name)
			return
		end

		debug_print("Detected", RigType, "rig for", ESP.CurrentSettings.Name)
		local Sequence = if RigType == "R15" then R15Sequence else R6Sequence

		-- // Create Path2D // --
		local SkeletonPath = InstancesLib.Create("Path2D", {
			Parent = Library.MainGUI,
			Name = (if DEBUG_ENABLED then "Skeleton_" else "") .. ESP.Index,
			Visible = false,
			
			-- // Settings // --
			Color3 = ESP.CurrentSettings.Skeleton.Color,
			Thickness = ESP.CurrentSettings.Skeleton.Thickness,
			Transparency = ESP.CurrentSettings.Skeleton.Transparency
		})

		-- // Skeleton Data // --
		local SkeletonData = {}
		local CachedParts = {}

		local function SetVisible(visible: boolean)
			if not SkeletonPath then return end
			if SkeletonPath.Visible == visible then return end

			SkeletonPath.Parent = if visible then Library.MainGUI else Library.StorageFolder
			SkeletonPath.Visible = visible
		end

		SkeletonData.Destroy = function(self)
			if not SkeletonPath then return end
			
			SkeletonPath:SetControlPoints({});
			SkeletonPath:Destroy();

			SkeletonPath = nil;
			Sequence = nil;
		end;

		SkeletonData.Update = function(self)
			if not SkeletonPath then return end

			-- // ESP Settings // --
			if not ESP._LastScreenPos then return end
			
			local ESPSettings = ESP.CurrentSettings;
			local _, isOnScreen = unpack(ESP._LastScreenPos);
			local SkeletonEnabled = isOnScreen == true and (Library.GlobalConfig.Skeleton == true and ESPSettings.Skeleton.Enabled == true);
			
			if not SkeletonEnabled then
				SetVisible(false);
				return
			end

			-- // Build Path from Joints // --
			local ControlPoints = {}
			local pointsMade = 0

			for idx, partName in Sequence do
				local part = CachedParts[partName]
				if not part then
					part = Model:FindFirstChild(partName)
					CachedParts[partName] = part

					if not part then 
						partName = 0
						break
					end
				end

				local pos, visible = WorldToViewport(part.Position)
				if not visible then
					partName = 0
					break
				end

				ControlPoints[idx] = Path2DControlPoint.new(UDim2.fromOffset(pos.X, pos.Y))
				pointsMade = pointsMade + 1 
			end

			if pointsMade == 0 then
				SetVisible(false);
				return
			end

			-- // Update Visuals // --
			SetVisible(true);
			SkeletonPath.Color3 = ESPSettings.Skeleton.Color;
			SkeletonPath.Thickness = ESPSettings.Skeleton.Thickness;
			
			if CoreGuiAllowed then
				SkeletonPath.Transparency = ESPSettings.Skeleton.Transparency;
			end;

			-- // Update Points // --
			SkeletonPath:SetControlPoints(ControlPoints);
		end;

		return setmetatable({}, {
			__newindex = function(table, key, value)
				if not SkeletonPath then return end

				if key == "Visible" then
					assert(
						typeof(value) == "boolean", 
						string.format("Visible; expected boolean, got %s", typeof(value))
					);

					SkeletonPath.Visible = value;
				else
					rawset(SkeletonData, key, value);
				end
			end,

			__index = function(table, key)
				if not SkeletonPath then return nil end
				
				if key == "Visible" then
					return SkeletonPath.Visible;
				else
					return rawget(SkeletonData, key);
				end
			end,

			__iter = function(_) return next, SkeletonData end,
			__metatable = "The metatable is locked"
		}) :: typeof(SkeletonData)
	end
end

function Library:Add(espSettings: ESPSettings)
	if Library.Destroyed == true then
		debug_warn("Library is destroyed, please reload it.")
		return
	end

	assert(
		typeof(espSettings) == "table", 
		string.format("espSettings; expected table, got %s", typeof(espSettings))
	)
	assert(
		typeof(espSettings.Model) == "Instance",
		string.format("espSettings.Model; expected Instance, got %s", typeof(espSettings.Model))
	)

	-- ESPType used to pick between Highlight, SelectionBox and three adornment
	-- shapes. All of those are gone, so it is accepted and ignored rather than
	-- validated - a loader that still passes one won't error.

	-- // Fix Settings // --
	espSettings.Name = if typeof(espSettings.Name) == "string" then espSettings.Name else espSettings.Model.Name;
	espSettings.TextModel = if typeof(espSettings.TextModel) == "Instance" then espSettings.TextModel else espSettings.Model;
	
	espSettings = Validate(espSettings, DefaultSettings)

	-- // ESP Data // --
	local ESP = {
		Index = RandomString(),
		OriginalSettings = table_freeze(espSettings) :: ESPSettings,
		CurrentSettings = setmetatable({}, {
			__tostring = function(_) return tostring(espSettings) end,

			__index = function(_, key) return rawget(espSettings, key); end,
			__newindex = function(_, key, value)
				if key == "Model" or key == "TextModel" or key == "ESPType" then
					error(string.format("%s cannot be changed, it is read-only.", key))
				end

				rawset(espSettings, key, value);
			end,

			__eq = function(_, other) return other == espSettings end,
			__iter = function(_) return next, espSettings end,
			__metatable = "The metatable is locked"
		}) :: ESPSettings,

		Hidden = false,
		Deleted = false,

		Connections = {} :: { RBXScriptConnection },
		Components = {}
	} :: ESPInstance;

	debug_print("Creating ESP...", ESP.Index, "-", ESP.CurrentSettings.Name)

	-- // Create Components // --
	-- keeps the old key so anything reaching into ESP.Components still finds it
	ESP.Components["Billboard"] = Components.Text(ESP)

	for Name, CreateFunc in Components do
		local Data = espSettings[Name]
		if not Data then continue end

		local Component = CreateFunc(ESP)
		if not Component then continue end

		ESP.Components[Name] = Component
	end

	-- // Setup Destroy Handler // --
	function ESP:Destroy()
		debug_print("Deleting ESP...", tostring(ESP.Index) .. " - " .. tostring(ESP.CurrentSettings.Name))
		
		if ESP.Deleted == true then
			debug_warn("ESP Instance is already deleted.")
			return;
		end

		-- // Change State // --
		ESP.Deleted = true

		-- // Remove from Library // --
		local TableIndex = table.find(Library.ESP, ESP.Index)
		if TableIndex then table.remove(Library.ESP, TableIndex) end
		Library.ESP[ESP.Index] = nil

		-- // Destroy Components // --
		for _, Component in ESP.Components do
			if not Component.Destroy then continue end

			Component:Destroy()
		end
		table.clear(ESP.Components)

		-- // Clear connections // --
		for _, connection in ESP.Connections do
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
		table.clear(ESP.Connections)

		-- // Callbacks // --
		if ESP.OriginalSettings.OnDestroy then
			SafeCallback(ESP.OriginalSettings.OnDestroy.Fire, ESP.OriginalSettings.OnDestroy)
		end

		if ESP.OriginalSettings.OnDestroyFunc then
			SafeCallback(ESP.OriginalSettings.OnDestroyFunc)
		end

		-- // Replace Render // --
		ESP.Render = function(...) end

		debug_print("ESP deleted.", ESP.Index, "-", ESP.CurrentSettings.Name)
	end

	-- // Setup Show/Hide Handler // --
	local function Show(forceShow: boolean?)
		if not (ESP and ESP.Deleted ~= true) then return end
		if forceShow ~= true and not ESP.Hidden then
			return
		end

		ESP.Hidden = false;
		for Name, Component in ESP.Components do
			Component.Visible = true
		end
	end

	local function Hide(forceHide: boolean?)
		if not (ESP and ESP.Deleted ~= true) then return end
		if forceHide ~= true and ESP.Hidden then
			return
		end

		ESP.Hidden = true;
		for Name, Component in ESP.Components do
			Component.Visible = false
		end
	end

	function ESP:Show(force: boolean?)
		if not (ESP and ESP.CurrentSettings and ESP.Deleted ~= true) then return end

		ESP.CurrentSettings.Visible = true;
		Show(force);
	end

	function ESP:Hide(force: boolean?)
		if not (ESP and ESP.CurrentSettings and ESP.Deleted ~= true) then return end

		ESP.CurrentSettings.Visible = false;
		Hide(force);
	end

	function ESP:ToggleVisibility(force: boolean?)
		if not (ESP and ESP.CurrentSettings and ESP.Deleted ~= true) then return end

		ESP.CurrentSettings.Visible = not ESP.CurrentSettings.Visible;
		if ESP.CurrentSettings.Visible then
			Show(force);
		else
			Hide(force);
		end
	end

	-- // Setup Setting Helpers // --
	function ESP:SetEveryColor(Color: Color3, IncludeComponents: boolean?)
		if not (ESP and ESP.CurrentSettings and ESP.Deleted ~= true) then return end
		local ESPSettings = ESP.CurrentSettings

		ESPSettings.Color = Color;

		-- // Components // --
		if IncludeComponents == true then
			for Name, Component in ESP.Components do
				local ComponentTable = ESPSettings[Name]
				if typeof(ComponentTable) ~= "table" then continue end

				ComponentTable.Color = Color;
			end
		end
	end

	-- // Setup Render Handler // --
	function ESP:Render()
		if not ESP then return end

		local ESPSettings = ESP.CurrentSettings
		if ESP.Deleted == true or not ESPSettings then return end
		
		-- // Early exit conditions // --
		if ESPSettings.Visible == false or not (
			Camera and (
				if Library.GlobalConfig.IgnoreCharacter == true then true else RootPart
			)
		) then
			Hide(true)
			return
		end

		-- // Check Distance // --
		if not ESPSettings.ModelRoot then
			ESPSettings.ModelRoot = InstancesLib.FindPrimaryPart(ESPSettings.Model)
		end

		local ModelRoot = ESPSettings.ModelRoot or ESPSettings.Model
		local DistanceFromPlayer = InstancesLib.DistanceFrom(ModelRoot, RootPart or Camera)
		ESP._LastDistance = DistanceFromPlayer

		if DistanceFromPlayer > ESPSettings.MaxDistance then
			Hide(true)
			return
		end

		-- // Get Screen Information // --
		local screenPos, isOnScreen = WorldToViewport(GetPivot(ModelRoot).Position)
		ESP._LastScreenPos = { screenPos, isOnScreen }

		-- // Bounding Box // --
		-- Eight corners projected once, then read by Box2D, the text and the
		-- health bar. Stock had Box2D do this itself, so anything else that wanted
		-- to hang off the box would have had to repeat all eight projections.
		local boundsOK, _corners, _screenCorners, minX, minY, maxX, maxY = GetModelCorners(ESPSettings.Model)
		ESP._BoundsOK = boundsOK
		ESP._MinX, ESP._MinY, ESP._MaxX, ESP._MaxY = minX, minY, maxX, maxY

		-- // Before Update Callback // --
		if ESPSettings.BeforeUpdate then
			SafeCallback(ESPSettings.BeforeUpdate, ESP)
		end

		-- // Update Components // --
		for Name, Component in ESP.Components do
			if not Component.Update then continue end

			local success, err = xpcall(Component.Update, debug.traceback, Component)
			if success then continue end

			debug_warn("Error updating component (" .. Name .. "):\n", err)
		end

		-- // After Update Callback // --
		if ESPSettings.AfterUpdate then
			SafeCallback(ESPSettings.AfterUpdate, ESP)
		end
	end

	if ESP.OriginalSettings.Visible == false then
		Hide()
	else
		Show()
	end

	Library.ESP[ESP.Index] = ESP
	debug_print("ESP created.", ESP.Index, "-", ESP.CurrentSettings.Name)
	return ESP
end

-- // Update Player Variables // --
table.insert(Library.Connections, workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() Camera = workspace.CurrentCamera; end))
table.insert(Library.Connections, Players.LocalPlayer.CharacterAdded:Connect(UpdatePlayerVariables))

-- // Main Handler // --
table.insert(Library.Connections, RunService.RenderStepped:Connect(function()
	for Index, ESP in Library.ESP do
		if not ESP then 
			Library.ESP[Index] = nil
			continue 
		end

		if 
			ESP.Deleted == true or 
			not (ESP.CurrentSettings and (ESP.CurrentSettings.Model and ESP.CurrentSettings.Model.Parent)) 
		then
			ESP:Destroy()
			continue
		end

		-- // Render ESP // --
		ESP.Render(ESP)
	end
end))

debug_print("Loaded! (" .. tostring(VERSION) ..")")
getgenv().mstudio45_ESP = Library
return Library