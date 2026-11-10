-- When the frame shows, in and out of combat.

local function Enemy(G, fields)
	local u = G.NewUnit({ name = "Boar", canAttack = true })
	for k, v in pairs(fields or {}) do u[k] = v end
	return u
end

local function Showing(frame)
	return frame:IsVisible() and frame:GetAlpha() == 1
end

describe("Visibility", function()
	it("shows when the pet has a target and hides when it loses it", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		no(Showing(frame), "showing with no pet target")
		G.SetPetTarget(Enemy(G))
		ok(Showing(frame), "showing once the pet has a target")
		G.SetPetTarget(nil)
		no(frame:IsShown(), "shown after the target is gone")
		eq(Problems(G), "", "problems")
	end)

	it("hides while the pet is dead, like the Target of Target needs a living target", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		G.SetPetTarget(Enemy(G))
		G.SetPet(true, true)
		G.Tick()
		no(frame:IsShown(), "shown with a dead pet")
	end)

	it("follows a new target in combat through its state driver and alpha", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		G.SetCombat(true)
		G.SetPetTarget(Enemy(G))
		G.Tick()
		ok(Showing(frame), "showing in combat")
		G.SetPetTarget(nil)
		G.Tick()
		no(frame:IsShown(), "shown in combat after the target is gone")
		eq(Problems(G), "", "no protected calls refused in combat")
	end)

	it("Options › Show Pet Target Frame off hides it and keeps it hidden", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		G.SetPetTarget(Enemy(G))
		G.SETTINGS_REGISTERED.SIMPLE_PET_TARGET_ENABLED:SetValue(false)
		G.Tick()
		no(frame:IsShown(), "shown after turning it off")
		G.SetPetTarget(Enemy(G, { name = "Wolf" }))
		G.Tick()
		no(frame:IsShown(), "shown for a new target while off")
		G.SETTINGS_REGISTERED.SIMPLE_PET_TARGET_ENABLED:SetValue(true)
		G.Tick()
		ok(Showing(frame), "showing after turning it back on")
	end)

	it("turning it off in combat waits for combat to end, so no invisible frame takes clicks", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		G.SetPetTarget(Enemy(G))
		G.SetCombat(true)
		G.SETTINGS_REGISTERED.SIMPLE_PET_TARGET_ENABLED:SetValue(false)
		G.Tick()
		ok(Showing(frame), "a shown frame stays fully visible until combat ends")
		eq(Problems(G), "", "no protected calls refused in combat")
		G.SetCombat(false)
		G.Tick()
		no(frame:IsShown(), "shown once combat ended")
	end)
end)
