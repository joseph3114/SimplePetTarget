-- Debuffs, shown by Blizzard's secure aura container.

local function Container(G)
	return G.FindFrameByTemplate("CustomAuraContainerTemplate")
end

local function Group(G)
	return Container(G):GetAuraGroup("debuffs")
end

describe("Debuffs", function()
	it("sets up a container for pettarget with 4 debuff buttons, beside the frame like Debuff1", function()
		local G = Start()
		local container = Container(G)
		ok(container, "a CustomAuraContainerTemplate container exists")
		eq(container:GetParent(), G.SimplePetTargetFrame, "parent")
		eq(container:GetUnit(), "pettarget", "unit")
		ok(container:IsShown(), "the container is shown")
		eq(container:GetAuraGroupFrameCount("debuffs"), 4, "buttons, like the Target of Target")
		local point, rel, relPoint, x, y = container:GetPoint(1)
		eq(point .. " " .. relPoint .. " " .. x .. "," .. y, "TOPLEFT TOPRIGHT 4,-10", "anchor")
		eq(rel, G.SimplePetTargetFrame, "anchored to the frame")
		eq(Problems(G), "", "problems")
	end)

	it("gives every button its icon, cooldown swipe and a dispel-type border that is kept for typeless debuffs", function()
		local G = Start()
		for i, button in ipairs(Group(G).frames) do
			eq(button:GetIcon(), button.Icon, "button " .. i .. " icon")
			eq(button:GetDurationCooldown(), button.Cooldown, "button " .. i .. " cooldown")
			eq(button:GetDispelTypeTextureCount(), 1, "button " .. i .. " dispel textures")
			local dispel = button:GetDispelTypeTexture(1)
			eq(dispel.texture, button.Border, "button " .. i .. " border")
			eq(dispel.options.style, G.Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset, "button " .. i .. " border style")
			eq(dispel.options.showWithoutDispelType, true, "button " .. i .. " showWithoutDispelType")
		end
	end)

	it("lets Edit Mode show Blizzard's sample debuffs", function()
		local G = Start()
		eq(Container(G):IsEditModePreviewEnabled(), true, "SetEditModePreviewEnabled")
	end)

	it("lists only your own debuffs on an enemy, like Blizzard", function()
		local G = Start()
		G.SetPetTarget(G.NewUnit({ canAttack = true }))
		G.Tick(3)
		eq(Group(G).filter, "HARMFUL|PLAYER", "filter")
		eq(Group(G).sortMethod, G.AuraContainerSortMethod.Default, "sort")
	end)

	it("lists dispellable debuffs on a friend when Display Dispellable Debuffs is on", function()
		local G = Start()
		G.SetPetTarget(G.NewUnit({ canAttack = false, canAssist = true }))
		G.Tick(3)
		eq(Group(G).filter, "HARMFUL|RAID", "filter")
		eq(Group(G).sortMethod, G.AuraContainerSortMethod.AuraInstanceIDOnly, "sort")
		G.CVARS.showDispelDebuffs = "0"
		G.Tick(3)
		eq(Group(G).filter, "HARMFUL", "filter with the setting off")
	end)

	it("asks the container to re-read auras on updates, in and out of combat", function()
		local G = Start()
		G.SetPetTarget(G.NewUnit({ canAttack = true }))
		local before = Container(G):GetUpdateCount()
		G.Tick(5)
		ok(Container(G):GetUpdateCount() > before, "UpdateAllAuras out of combat")
		G.SetCombat(true)
		before = Container(G):GetUpdateCount()
		G.Tick(5)
		ok(Container(G):GetUpdateCount() > before, "UpdateAllAuras in combat")
		eq(Problems(G), "", "problems: nothing touched the locked buttons")
	end)

	it("opens tooltips on the side away from the screen edge, changing it only out of combat", function()
		local G = Start()
		local frame = G.SimplePetTargetFrame
		local button = Group(G).frames[1]
		G.SetPetTarget(G.NewUnit({ canAttack = true }))
		G.Tick(3)
		eq(button:GetTooltipAnchorPoint(), "ANCHOR_RIGHT", "on the left half of the screen")

		frame.GetRight = function() return 1500 end
		G.SetCombat(true)
		G.Tick(5)
		eq(button:GetTooltipAnchorPoint(), "ANCHOR_RIGHT", "unchanged in combat")
		G.SetCombat(false)
		G.Tick(3)
		eq(button:GetTooltipAnchorPoint(), "ANCHOR_LEFT", "on the right half of the screen")
		eq(Problems(G), "", "problems")
	end)

	it("never builds Edit Mode's sample auras from addon code (the cause of the Cooldown Manager taint)", function()
		local G = Start()
		G.SetPetTarget(G.NewUnit({ canAttack = true }))
		G.OpenEditMode()
		G.Tick(10)
		G.CloseEditMode()
		G.Tick(3)
		eq(Problems(G), "", "problems (AuraUtil calls show up here)")
	end)

	it("does without debuffs, and says so once, if the client refuses pettarget aura events", function()
		local G = Start(function(G)
			G.VALID_UNIT_EVENT_TOKENS.pettarget = nil
		end)
		G.SetPetTarget(G.NewUnit({ canAttack = true }))
		G.Tick(5)
		no(Container(G), "a container was created")
		local reported = 0
		for _, e in ipairs(G.ERRORS) do
			if e:find("debuffs are unavailable", 1, true) then reported = reported + 1 end
		end
		eq(reported, 1, "times reported")
		eq(#G.ERRORS, 1, "other errors")
		ok(G.SimplePetTargetFrame:IsShown(), "the frame still works")
	end)
end)
