-- Name, bars, status text and portrait, with the values the client hides from addons.

local function Target(G, fields)
	local u = G.NewUnit({ name = "Boar", canAttack = true, health = 50, maxHealth = 200, power = 30, maxPower = 120 })
	for k, v in pairs(fields or {}) do u[k] = v end
	G.SetPetTarget(u)
	G.Tick(3)
	return u
end

local function Bars(G) return G.SimplePetTargetFrame.HealthBar, G.SimplePetTargetFrame.ManaBar end

describe("Bars", function()
	it("shows the name and fills the bars from the unit's values", function()
		local G = Start()
		Target(G)
		local frame = G.SimplePetTargetFrame
		local health, mana = Bars(G)
		eq(Text(frame.Name), "Boar", "name")
		eq(G.Reveal(health:GetValue()), 50, "health")
		eq(G.Reveal(select(2, health:GetMinMaxValues())), 200, "max health")
		eq(G.Reveal(mana:GetValue()), 30, "power")
		eq(Problems(G), "", "problems")
	end)

	it("runs in combat, when name, health and power are secret, without errors", function()
		local G = Start()
		G.CVARS.statusText = "1"
		G.SetCombat(true)
		Target(G)
		G.Tick(10)
		ok(G.issecretvalue(G.UnitName("pettarget")), "the stand-in hides the name in combat")
		eq(Text(G.SimplePetTargetFrame.Name), "Boar", "name drawn from the secret")
		eq(Problems(G), "", "problems")
	end)

	it("has no status text while Status Text is off", function()
		local G = Start()
		Target(G)
		local health, mana = Bars(G)
		no(health.TextString:IsShown(), "health text shown")
		no(mana.TextString:IsShown(), "power text shown")
	end)

	it("follows the Status Text setting like the Pet Frame: numbers, percent, both", function()
		local G = Start()
		G.CVARS.statusText = "1"
		Target(G)
		local health, mana = Bars(G)
		eq(Text(health.TextString), "50 / 200", "health, numeric")
		eq(Text(mana.TextString), "30 / 120", "power, numeric")

		G.CVARS.statusTextDisplay = "PERCENT"
		G.Tick(3)
		eq(Text(health.TextString), "25%", "health, percent")
		eq(Text(mana.TextString), "25%", "power, percent")

		G.CVARS.statusTextDisplay = "BOTH"
		G.Tick(3)
		no(health.TextString:IsShown(), "single text shown with Both")
		eq(Text(health.LeftText), "25%", "health percent on the left")
		eq(Text(health.RightText), "50", "health value on the right")
		eq(Text(mana.LeftText), "25%", "mana percent on the left")
		eq(Problems(G), "", "problems")
	end)

	it("rounds percentages up, like Blizzard", function()
		local G = Start()
		G.CVARS.statusText = "1"
		G.CVARS.statusTextDisplay = "PERCENT"
		Target(G, { health = 1, maxHealth = 300 })
		eq(Text(G.SimplePetTargetFrame.HealthBar.TextString), "1%", "1/300 of health")
	end)

	it("leaves the power text blank for a unit without power, though its maximum is secret", function()
		local G = Start()
		G.CVARS.statusText = "1"
		Target(G, { power = 0, maxPower = 0 })
		ok(G.issecretvalue(G.UnitPowerMax("pettarget")), "the stand-in hides the maximum")
		local health, mana = Bars(G)
		eq(Text(mana.TextString), "", "power text")
		eq(Text(health.TextString), "50 / 200", "health text is unaffected")

		G.CVARS.statusTextDisplay = "BOTH"
		G.Tick(3)
		eq(Text(mana.LeftText), "", "power percent with Both")
		eq(Text(mana.RightText), "", "power value with Both")
		eq(Problems(G), "", "problems")
	end)

	it("never leaves hyperlink markup in the text", function()
		local G = Start()
		G.CVARS.statusText = "1"
		for _, mode in ipairs({ "NUMERIC", "PERCENT", "BOTH" }) do
			G.CVARS.statusTextDisplay = mode
			Target(G)
			local health, mana = Bars(G)
			for _, fs in ipairs({ health.TextString, health.LeftText, health.RightText, mana.TextString, mana.LeftText, mana.RightText }) do
				no((Text(fs) or ""):find("|H", 1, true), mode .. " text has markup: " .. tostring(Text(fs)))
			end
		end
	end)

	it("shows DEAD and no health text on a dead target", function()
		local G = Start()
		G.CVARS.statusText = "1"
		Target(G, { dead = true, health = 0 })
		local health = Bars(G)
		ok(health.DeadText:IsShown(), "DEAD shown")
		no(health.UnconsciousText:IsShown(), "UNCONSCIOUS shown")
		no(health.TextString:IsShown(), "health text shown")
	end)

	it("shows UNCONSCIOUS instead of DEAD", function()
		local G = Start()
		Target(G, { unconscious = true })
		local health = Bars(G)
		ok(health.UnconsciousText:IsShown(), "UNCONSCIOUS shown")
		no(health.DeadText:IsShown(), "DEAD shown")
	end)
end)

describe("Portrait", function()
	it("tints a player's portrait red at 20% health or less, through curves", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		Target(G, { isPlayer = true, playerControlled = true, health = 30, maxHealth = 100 })
		eq(G.Reveal(frame.PortraitRed:GetAlpha()), 0, "red copy at 30%")
		eq(G.Reveal(frame.Portrait:GetAlpha()), 1, "normal copy at 30%")
		Target(G, { isPlayer = true, playerControlled = true, health = 20, maxHealth = 100 })
		eq(G.Reveal(frame.PortraitRed:GetAlpha()), 1, "red copy at 20%")
		eq(G.Reveal(frame.Portrait:GetAlpha()), 0, "normal copy at 20%")
	end)

	it("never tints a creature's portrait", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		Target(G, { health = 5, maxHealth = 100 })
		eq(G.Reveal(frame.PortraitRed:GetAlpha()), 0, "red copy")
		eq(G.Reveal(frame.Portrait:GetAlpha()), 1, "normal copy")
	end)
end)
