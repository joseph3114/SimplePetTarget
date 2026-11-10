-- Edit Mode: the side panel's checkbox, the frame's own settings, and combat.

local function Panel(G)
	local checkbox = G.FindFrameByTemplate("EditModeManagerSettingCheckButtonTemplate")
	return checkbox:GetParent(), checkbox
end

local function Selection(G)
	return G.NS.LibEditMode.frameSelections[G.SimplePetTargetFrame]
end

local function Dialog(G)
	return G.NS.LibEditMode.internal.dialog
end

local function ClickCheckbox(G)
	local _, checkbox = Panel(G)
	return checkbox.Button:Click()
end

local function SelectFrame(G)
	G.FireScript(Selection(G), "OnMouseDown", "LeftButton")
end

local function Setting(G, name)
	local settings = G.NS.LibEditMode.internal:GetFrameSettings(G.SimplePetTargetFrame)
	for _, s in ipairs(settings) do
		if s.name == name then return s end
	end
end

local function Previewed(G)
	local frame = G.SimplePetTargetFrame
	return frame:IsVisible() and frame:GetAlpha() == 1 and Selection(G):IsVisible()
end

describe("Edit Mode", function()
	it("shows the frame with you as a stand-in, and the side panel with its checkbox on", function()
		local G = Start()
		G.OpenEditMode()
		G.Tick(3)
		local panel, checkbox = Panel(G)
		ok(panel:IsShown(), "panel shown")
		ok(checkbox:IsControlChecked(), "checkbox checked")
		ok(checkbox.Button:IsEnabled(), "checkbox enabled")
		ok(Previewed(G), "frame and its selection shown")
		eq(Text(G.SimplePetTargetFrame.Name), "Me", "stand-in name")
		eq(Problems(G), "", "problems")
	end)

	it("offers only Attach to Pet Frame and Frame Size in the frame's settings", function()
		local G = Start()
		local names = {}
		for _, s in ipairs((G.NS.LibEditMode.internal:GetFrameSettings(G.SimplePetTargetFrame))) do
			names[#names + 1] = s.name
		end
		eq(table.concat(names, ", "), "Attach to Pet Frame, Frame Size", "settings")
	end)

	it("unchecking the panel checkbox leaves the frame out of Edit Mode, for later sessions too", function()
		local G = Start()
		G.OpenEditMode()
		G.Tick()
		ClickCheckbox(G)
		G.Tick()
		no(Previewed(G), "frame still shown in Edit Mode")
		no(Selection(G):IsShown(), "selection shown")
		eq(G.SimplePetTargetDB.showInEditMode, false, "saved")
		G.CloseEditMode()
		G.OpenEditMode()
		G.Tick()
		local _, checkbox = Panel(G)
		no(checkbox:IsControlChecked(), "checked in the next session")
		no(Previewed(G), "shown in the next session")
		eq(Problems(G), "", "problems")
	end)

	it("checks itself for the session when the frame is already showing, like Blizzard's Pet Frame checkbox", function()
		local G = Start(function(G) G.SimplePetTargetDB = { showInEditMode = false, layouts = {} } end)
		G.SetPetTarget(G.NewUnit({ canAttack = true }))
		G.OpenEditMode()
		G.Tick()
		local _, checkbox = Panel(G)
		ok(checkbox:IsControlChecked(), "checked")
		ok(Previewed(G), "frame placeable")
		eq(G.SimplePetTargetDB.showInEditMode, false, "not saved")
	end)

	it("greys out the checkbox and leaves the frame out while Options has it turned off", function()
		local G = Start()
		G.SETTINGS_REGISTERED.SIMPLE_PET_TARGET_ENABLED:SetValue(false)
		G.OpenEditMode()
		G.Tick()
		local _, checkbox = Panel(G)
		no(checkbox.Button:IsEnabled(), "checkbox enabled")
		no(Previewed(G), "frame shown")
		G.SETTINGS_REGISTERED.SIMPLE_PET_TARGET_ENABLED:SetValue(true)
		G.Tick()
		ok(checkbox.Button:IsEnabled(), "checkbox enabled after turning it on")
		ok(Previewed(G), "frame shown after turning it on")
	end)

	it("closes the frame's settings when the frame leaves Edit Mode", function()
		local G = Start()
		G.OpenEditMode()
		G.Tick()
		SelectFrame(G)
		ok(Selection(G).isSelected, "selected")
		ok(Dialog(G):IsShown(), "settings open")
		ClickCheckbox(G)
		no(Dialog(G):IsShown(), "settings still open")
		eq(Dialog(G).selection, nil, "settings still bound to the frame")
	end)

	it("cleans up when Edit Mode closes: panel hidden, settings unbound, frame hidden without a target", function()
		local G = Start()
		G.OpenEditMode()
		G.Tick()
		SelectFrame(G)
		G.CloseEditMode()
		G.Tick()
		local panel = Panel(G)
		no(panel:IsShown(), "panel shown")
		no(Dialog(G):IsShown(), "settings shown")
		eq(Dialog(G).selection, nil, "settings bound")
		no(G.SimplePetTargetFrame:IsShown(), "frame shown")
		eq(Problems(G), "", "problems")
	end)

	it("opens and closes in combat without protected calls, and catches up when combat ends", function()
		local G = Start()
		G.SetCombat(true)
		G.OpenEditMode()
		G.Tick(3)
		no(G.SimplePetTargetFrame:IsShown(), "shown in combat, which the client wouldn't allow")
		ClickCheckbox(G)
		ClickCheckbox(G)
		G.CloseEditMode()
		G.Tick(3)
		eq(Problems(G), "", "problems")
		G.OpenEditMode()
		G.SetCombat(false)
		G.Tick(3)
		ok(Previewed(G), "shown in Edit Mode once combat ended")
		G.CloseEditMode()
		G.Tick()
		no(G.SimplePetTargetFrame:IsShown(), "shown after Edit Mode closed")
		eq(Problems(G), "", "problems")
	end)
end)

describe("Edit Mode › Frame settings", function()
	it("is attached to the Pet Frame by default", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		eq(frame:GetParent(), G.PetFrame, "parent")
		local point, rel, relPoint, x = frame:GetPoint(1)
		eq(point .. " " .. relPoint .. " " .. x, "TOPLEFT TOPRIGHT 28", "anchor, leaving room for the happiness icon")
		eq(rel, G.PetFrame, "anchored to the Pet Frame")
	end)

	it("detaches in place, at the Pet Frame's size, and attaches again", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		local LEM = G.NS.LibEditMode
		G.OpenEditMode()
		G.Tick()
		local layout = LEM:GetActiveLayoutName()
		Setting(G, "Attach to Pet Frame").set(layout, false)
		G.Tick()
		local settings = G.SimplePetTargetDB.layouts[layout]
		eq(settings.attached, false, "saved")
		eq(settings.frameSize, 100, "Frame Size taken from the Pet Frame")
		ok(settings.point, "position saved")
		eq(frame:GetParent(), G.UIParent, "parent")
		Setting(G, "Attach to Pet Frame").set(layout, true)
		eq(frame:GetParent(), G.PetFrame, "parent after attaching again")
		eq(Problems(G), "", "problems")
	end)

	it("scales a detached frame with Frame Size", function()
		local G = Start()
		local LEM = G.NS.LibEditMode
		local layout = LEM:GetActiveLayoutName()
		ok(Setting(G, "Frame Size").disabled(layout), "Frame Size is disabled while attached")
		Setting(G, "Attach to Pet Frame").set(layout, false)
		no(Setting(G, "Frame Size").disabled(layout), "Frame Size is disabled while detached")
		Setting(G, "Frame Size").set(layout, 150)
		eq(G.SimplePetTargetFrame:GetScale(), 1.5, "scale")
	end)

	it("can't be dragged while attached", function()
		local G = Start()
		G.OpenEditMode()
		G.Tick()
		G.FireScript(Selection(G), "OnDragStart")
		no(rawget(G.SimplePetTargetFrame, "__moving"), "moving while attached")
		Setting(G, "Attach to Pet Frame").set(G.NS.LibEditMode:GetActiveLayoutName(), false)
		G.FireScript(Selection(G), "OnDragStart")
		ok(rawget(G.SimplePetTargetFrame, "__moving"), "moving while detached")
	end)

	it("keeps settings per Edit Mode layout", function()
		local G = Start(function(G)
			table.insert(G.LAYOUTS.layouts, { layoutName = "Raid", layoutType = 1 })
		end)
		local LEM = G.NS.LibEditMode
		local first = LEM:GetActiveLayoutName()
		Setting(G, "Attach to Pet Frame").set(first, false)
		Setting(G, "Frame Size").set(first, 150)
		G.EditModeManagerFrame:SelectLayout(G.LAYOUTS.activeLayout + 1)
		local second = LEM:GetActiveLayoutName()
		ok(second and second ~= first, "switched layouts (" .. tostring(first) .. " → " .. tostring(second) .. ")")
		eq(G.SimplePetTargetFrame:GetParent(), G.PetFrame, "attached in the other layout")
		eq(G.SimplePetTargetFrame:GetScale(), 1, "scale in the other layout")
		G.EditModeManagerFrame:SelectLayout(G.LAYOUTS.activeLayout - 1)
		eq(G.SimplePetTargetFrame:GetScale(), 1.5, "scale back in the first layout")
	end)
end)
