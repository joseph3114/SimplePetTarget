-- Loading the addon and logging in.

describe("Loading", function()
	it("loads and logs in without errors", function()
		local G = NewGame()
		G.Login()
		G.Tick(5)
		eq(Problems(G), "", "problems")
	end)

	it("creates a secure unit button for pettarget, hidden until the pet has a target", function()
		local G = NewGame()
		G.Login()
		local frame = G.SimplePetTargetFrame
		ok(frame, "SimplePetTargetFrame exists")
		ok(rawget(frame, "__protected"), "the frame is protected")
		eq(rawget(frame, "__secureUnit"), "pettarget", "SecureUnitButton_OnLoad unit")
		eq(frame.unit, "pettarget", "frame.unit for pings")
		no(frame:IsShown(), "shown without a pet")
	end)

	it("adds the Options checkbox, on by default", function()
		local G = NewGame()
		G.Login()
		local setting = G.SETTINGS_REGISTERED.SIMPLE_PET_TARGET_ENABLED
		ok(setting, "SIMPLE_PET_TARGET_ENABLED is registered")
		eq(setting:GetValue(), true, "default value")
		eq(G.SimplePetTargetDB.enabled, true, "saved in SimplePetTargetDB.enabled")
	end)

	it("registers the frame with LibEditMode as Pet Target Frame", function()
		local G = NewGame()
		G.Login()
		local LEM = G.NS.LibEditMode
		local selection = LEM.frameSelections[G.SimplePetTargetFrame]
		ok(selection, "the frame has an Edit Mode selection")
		eq(selection.system:GetSystemName(), "Pet Target Frame", "system name")
	end)

	it("cleans up settings saved by older versions", function()
		local G = NewGame()
		G.SimplePetTargetDB = { dispelTypeIDs = { 1, 2 }, layouts = { Mine = { enabled = false, attached = true, frameSize = 100 } } }
		G.Login()
		eq(G.SimplePetTargetDB.dispelTypeIDs, nil, "dispelTypeIDs")
		eq(G.SimplePetTargetDB.layouts.Mine.enabled, nil, "per-layout enabled")
		eq(G.SimplePetTargetDB.layouts.Mine.attached, true, "other per-layout settings are kept")
	end)
end)
