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
	it("without a pet out, stands where it would sit beside the Pet Frame, then attaches when that shows", function()
		local G = NewGame()
		G.Login()
		G.Tick()
		local frame = G.SimplePetTargetFrame
		G.OpenEditMode()
		G.Tick(2)
		no(G.PetFrame:IsVisible(), "Pet Frame shown without a pet")
		ok(Previewed(G), "frame and its selection shown")
		eq(frame:GetParent(), G.UIParent, "parent while the Pet Frame is hidden")
		G.EditModeManagerFrame:SetPetFrameCheckbox(true)
		G.Tick(2)
		ok(G.PetFrame:IsVisible(), "Pet Frame shown by its checkbox")
		eq(frame:GetParent(), G.PetFrame, "parent once the Pet Frame shows")
		eq(Problems(G), "", "problems")
	end)

	it("closes the frame's settings when combat starts", function()
		local G = Start()
		G.OpenEditMode()
		G.Tick()
		SelectFrame(G)
		ok(Dialog(G):IsShown(), "settings open")
		G.SetCombat(true)
		no(Dialog(G):IsShown(), "settings still open in combat")
		eq(Dialog(G).selection, nil, "settings still bound to the frame")
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
	it("saves a detached frame's position in screen units, whatever its size", function()
		local G = Start()
		local LEM = G.NS.LibEditMode
		local layout = LEM:GetActiveLayoutName()
		local moved = LEM.frameCallbacks[G.SimplePetTargetFrame]
		moved(G.SimplePetTargetFrame, layout, "TOPLEFT", 10, -20)
		eq(G.SimplePetTargetDB.layouts[layout].point, nil, "an attached frame's position")
		eq(G.SimplePetTargetFrame:GetParent(), G.PetFrame, "an attached frame goes back to the Pet Frame")

		Setting(G, "Attach to Pet Frame").set(layout, false)
		Setting(G, "Frame Size").set(layout, 150)
		moved(G.SimplePetTargetFrame, layout, "TOPLEFT", 10, -20)
		local settings = G.SimplePetTargetDB.layouts[layout]
		eq(settings.point .. " " .. settings.x .. " " .. settings.y, "TOPLEFT 15 -30", "saved position")
		local point, _, _, x, y = G.SimplePetTargetFrame:GetPoint(1)
		eq(point .. " " .. x .. " " .. y, "TOPLEFT 10 -20", "the frame's anchor, in its own units")
		eq(Problems(G), "", "problems")
	end)
end)

-- The game keeps account-wide layouts before character-specific ones.
local function TwoLayouts(active)
	return function(G)
		G.LAYOUTS.layouts = { { layoutName = "Acct", layoutType = 1 }, { layoutName = "Char", layoutType = 2 } }
		G.LAYOUTS.activeLayout = G.NUM_PRESET_LAYOUTS + active
	end
end

local function Detach(G, layout)
	Setting(G, "Attach to Pet Frame").set(layout, false)
	Setting(G, "Frame Size").set(layout, 150)
end

local function IsCopy(settings)
	return settings ~= nil and settings.attached == false and settings.frameSize == 150
end

describe("Edit Mode › Layouts", function()
	it("a new layout starts with the settings of the layout it was copied from", function()
		local G = Start(TwoLayouts(2))
		local LEM = G.NS.LibEditMode
		eq(LEM:GetActiveLayoutName(), "Char", "active layout")
		Detach(G, "Char")
		G.MakeNewLayout("Char 2", 2, "Char")
		eq(LEM:GetActiveLayoutName(), "Char 2", "the new layout is active")
		ok(IsCopy(G.SimplePetTargetDB.layouts["Char 2"]), "settings copied")
		ok(G.SimplePetTargetDB.layouts["Char 2"] ~= G.SimplePetTargetDB.layouts.Char, "a copy, not the same table")
		eq(G.SimplePetTargetFrame:GetScale(), 1.5, "the frame keeps its size")
		eq(Problems(G), "", "problems")
	end)

	it("a new account-wide layout gets the copy though it lands before the character-specific ones", function()
		local G = Start(TwoLayouts(1))
		local LEM = G.NS.LibEditMode
		Detach(G, "Acct")
		G.MakeNewLayout("New", 1, "Acct")
		eq(G.LAYOUTS.layouts[2].layoutName, "New", "the new layout is second in the list")
		eq(LEM:GetActiveLayoutName(), "New", "the new layout is active")
		ok(IsCopy(G.SimplePetTargetDB.layouts.New), "settings copied to the new layout")
		eq(G.SimplePetTargetDB.layouts.Char, nil, "the character-specific layout is left alone")
		eq(G.SimplePetTargetFrame:GetScale(), 1.5, "the frame keeps its size")
		eq(Problems(G), "", "problems")
	end)

	it("follows a new layout that takes the active layout's place in the list", function()
		local G = Start(TwoLayouts(2))
		local LEM = G.NS.LibEditMode
		Detach(G, "Char")
		eq(G.SimplePetTargetFrame:GetScale(), 1.5, "scale in the detached layout")
		G.MakeNewLayout("New", 1, "Acct") -- a copy of the attached layout
		eq(G.LAYOUTS.activeLayout, G.NUM_PRESET_LAYOUTS + 2, "the active index hasn't changed")
		eq(LEM:GetActiveLayoutName(), "New", "the new layout is active")
		eq(G.SimplePetTargetFrame:GetParent(), G.PetFrame, "attached, as the new layout says")
		eq(G.SimplePetTargetFrame:GetScale(), 1, "scale in the new layout")
		ok(IsCopy(G.SimplePetTargetDB.layouts.Char), "the other layout keeps its settings")
		eq(Problems(G), "", "problems")
	end)

	it("copies from a preset layout, which the game reports by its localized name", function()
		local G = Start(function(G) G.LAYOUT_STYLE_CLASSIC = "Klassisch" end)
		local LEM = G.NS.LibEditMode
		G.EditModeManagerFrame:SelectLayout(2)
		eq(LEM:GetActiveLayoutName(), "Classic", "active layout")
		Detach(G, "Classic")
		G.MakeNewLayout("Mine too", 1, "Klassisch")
		ok(IsCopy(G.SimplePetTargetDB.layouts["Mine too"]), "settings copied")
		eq(Problems(G), "", "problems")
	end)

	it("keeps a layout's settings when it is renamed, and drops them when it is deleted", function()
		local G = Start(TwoLayouts(1))
		local LEM = G.NS.LibEditMode
		Detach(G, "Acct")
		G.RenameLayout("Acct", "Raid")
		eq(LEM:GetActiveLayoutName(), "Raid", "active layout")
		ok(IsCopy(G.SimplePetTargetDB.layouts.Raid), "settings under the new name")
		eq(G.SimplePetTargetDB.layouts.Acct, nil, "settings under the old name")
		eq(G.SimplePetTargetFrame:GetScale(), 1.5, "the frame keeps its size")

		G.DeleteLayout("Raid")
		eq(LEM:GetActiveLayoutName(), "Modern", "the game falls back to a preset")
		eq(G.SimplePetTargetDB.layouts.Raid, nil, "settings of the deleted layout")
		eq(G.SimplePetTargetFrame:GetParent(), G.PetFrame, "attached in the preset")
		eq(Problems(G), "", "problems")
	end)
end)
