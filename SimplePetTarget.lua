local addonName, ns = ...
local LEM = ns.LibEditMode

-- A copy of Blizzard's Target of Target frame (TargetOfTargetMixin in
-- Blizzard_UnitFrame/Mainline/TargetFrame.lua) for "pettarget".
--
-- This client hides many unit values from addons ("secret values"): health always, and names,
-- power and aura details in combat. Addon code may not compare them, do math on them or test them
-- in an if, but it may hand them to widgets such as StatusBar:SetValue and FontString:SetText,
-- which draw them natively. Wherever Blizzard's code compares health or aura fields, this file uses
-- an equivalent that never looks at the value itself (non-secret unit flags, curves, aura filters).

local UNIT = "pettarget"
local SYSTEM_NAME = "Pet Target Frame"
local NUM_DEBUFFS = 4 -- MAX_PARTY_DEBUFFS, the number of debuffs the Target of Target shows
local FULL_UPDATE_INTERVAL = 0.1

-- Shown while the pet is alive and has a target, like the Target of Target needs a living target.
local VISIBILITY_DRIVER = "[@pettarget,noexists][@pet,dead] hide; show"

-- When attached, the frame sits to the right of the Pet Frame, the way the Target of Target hangs
-- off the Target frame. PetFrameHappiness (24 px wide) is anchored to the Pet Frame's right edge,
-- so leave room for it.
local ATTACH_POINT, ATTACH_RELATIVE_POINT, ATTACH_X, ATTACH_Y = "TOPLEFT", "TOPRIGHT", 28, 0

-- The range of Blizzard's Frame Size slider for unit frames.
local FRAME_SIZE_MIN, FRAME_SIZE_MAX, FRAME_SIZE_STEP = 100, 200, 5

-- Per Edit Mode layout. Whether the frame is used at all, and whether Edit Mode shows it, are
-- account-wide (db.enabled and db.showInEditMode), like Blizzard's own options.
local DEFAULT_SETTINGS = {
	attached = true,
	frameSize = 100,
	-- point, x, y: the detached position, with offsets in UIParent units at 100% size.
}

-- Starting point for the dispel type IDs that C_UnitAuras.GetAuraDispelTypeColor uses as curve
-- input. They aren't documented, so the real IDs are learned out of combat (LearnDispelTypeID).
local KNOWN_DISPEL_TYPE_IDS = { Magic = 1, Curse = 2, Disease = 3, Poison = 4 }

local issecretvalue = issecretvalue or function() return false end
local canaccesstable = canaccesstable or function() return true end

local db -- SimplePetTargetDB, available from ADDON_LOADED
local previewing = false -- Edit Mode is open and shows the frame, with a stand-in unit (Lua state only)
local previewShown = false -- shown for Edit Mode with the state driver off (protected, so may lag in combat)
local pendingLayout = false -- protected changes waiting for combat to end
local appliedEnabled = true -- IsEnabled() as last applied out of combat; the frame follows this one
local checkedForSession = false -- the Edit Mode checkbox is on for this Edit Mode session only

local frame = CreateFrame("Button", "SimplePetTargetFrame", UIParent, "SimplePetTargetFrameTemplate")
frame.unit = UNIT -- read by PingableType_UnitFrameMixin
frame:SetDontSavePosition(true)
-- Left click targets the unit and right click does nothing, exactly like the Target of Target.
SecureUnitButton_OnLoad(frame, UNIT)

frame.HealthBar:GetStatusBarTexture():AddMaskTexture(frame.HealthBar.HealthBarMask)
frame.ManaBar:GetStatusBarTexture():AddMaskTexture(frame.ManaBar.ManaBarMask)
frame.PortraitRed:SetVertexColor(1, 0, 0)

local FRAME_WIDTH, FRAME_HEIGHT = frame:GetSize()
local MANA_BAR_HEIGHT = frame.ManaBar:GetHeight()
local debuffs = { frame.Debuff1, frame.Debuff2, frame.Debuff3, frame.Debuff4 }

-- Report each distinct error once instead of every frame.
local reportedErrors = {}
local function RunProtected(func, unit)
	local ok, err = pcall(func, unit)
	if not ok then
		local key = issecretvalue(err) and "<secret error>" or err -- secrets can't be table keys
		if not reportedErrors[key] then
			reportedErrors[key] = true
			geterrorhandler()(err)
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Settings (one set per Edit Mode layout)
---------------------------------------------------------------------------------------------------

local function GetSettings(layoutName)
	if not db or not layoutName then
		return DEFAULT_SETTINGS -- read-only; setters always have a layout name
	end
	local settings = db.layouts[layoutName]
	if not settings then
		settings = CopyTable(DEFAULT_SETTINGS)
		db.layouts[layoutName] = settings
	end
	return settings
end

local function GetActiveSettings()
	return GetSettings(LEM:GetActiveLayoutName())
end

-- "Show Pet Target Frame" in Options > AddOns > Simple Pet Target, like Blizzard's Target of Target
-- option.
local function IsEnabled()
	return not db or db.enabled ~= false
end

-- The "Pet Target Frame" checkbox beside the HUD Edit Mode window, like Blizzard's "Pet Frame"
-- checkbox in that window, including its checking itself for the session when the frame is already
-- showing (OnEditModeEnter).
local function IsEditModeChecked()
	return checkedForSession or not db or db.showInEditMode ~= false
end

-- Whether Edit Mode shows the frame so it can be placed. A frame that is turned off doesn't show
-- there, like the Target of Target.
local function ShowsInEditMode()
	return IsEnabled() and IsEditModeChecked()
end

-- LibEditMode keeps its settings dialog bound to the frame after Edit Mode closes, and a later
-- layout change can show it again outside Edit Mode, where its position panel takes keyboard input.
-- Its position edit box also moves the frame without checking for combat. Clearing the dialog the
-- way its close button does avoids both.
local function ResetEditModeDialog()
	local dialog = LEM.internal and LEM.internal.dialog
	if dialog then
		dialog:Hide()
		dialog:Reset()
	end
end

---------------------------------------------------------------------------------------------------
-- Position, size and visibility (protected: only out of combat)
---------------------------------------------------------------------------------------------------

-- LibEditMode reads this table whenever it needs the default position, so ApplyPosition keeps it
-- current. Offsets are in the frame's own units at its current size.
local defaultPosition = { point = "CENTER", x = 0, y = 0 }

-- The anchor LibEditMode would pick for this rectangle (the rules of its normalizePosition), with
-- offsets in UIParent units. Storing positions this way keeps the anchor point fixed on screen when
-- the frame size changes, like Blizzard's Edit Mode does.
local function NormalizeRect(left, top, right, bottom)
	local parentWidth, parentHeight = UIParent:GetSize()
	local centerX, centerY = (left + right) / 2, (bottom + top) / 2
	local point, x, y
	if left < parentWidth - right and left < math.abs(centerX - parentWidth / 2) then
		point, x = "LEFT", left
	elseif parentWidth - right < math.abs(centerX - parentWidth / 2) then
		point, x = "RIGHT", right - parentWidth
	else
		point, x = "", centerX - parentWidth / 2
	end
	if bottom < parentHeight - top and bottom < math.abs(centerY - parentHeight / 2) then
		point, y = "BOTTOM" .. point, bottom
	elseif parentHeight - top < math.abs(centerY - parentHeight / 2) then
		point, y = "TOP" .. point, top - parentHeight
	else
		y = centerY - parentHeight / 2
	end
	if point == "" then
		point = "CENTER"
	end
	return point, x, y
end

-- Where the attached frame sits: its top left corner in UIParent units, and its size relative to
-- UIParent (it takes the Pet Frame's scale, which includes the Player Frame's).
local function GetAttachedPlacement()
	local right, top = PetFrame:GetRight(), PetFrame:GetTop()
	if not right or not top or issecretvalue(right) or issecretvalue(top) then
		return nil
	end
	local scale = PetFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return (right + ATTACH_X) * scale, (top + ATTACH_Y) * scale, scale
end

-- A detached frame defaults to the spot it would have next to the Pet Frame.
local function GetDefaultDetachedPosition(scale)
	local left, top = GetAttachedPlacement()
	if not left then
		return "CENTER", 0, 0
	end
	return NormalizeRect(left, top, left + FRAME_WIDTH * scale, top - FRAME_HEIGHT * scale)
end

local function ApplyPosition()
	local settings = GetActiveSettings()
	frame:ClearAllPoints()
	frame:SetClampedToScreen(not settings.attached)
	if settings.attached and (not previewing or PetFrame:IsVisible()) then
		-- A child of the Pet Frame, like the Target of Target is a child of the Target frame: it
		-- moves, scales and hides with it.
		frame:SetParent(PetFrame)
		frame:SetScale(1)
		frame:SetPoint(ATTACH_POINT, PetFrame, ATTACH_RELATIVE_POINT, ATTACH_X, ATTACH_Y)
		-- Matches the anchor, so Edit Mode's Reset To Default Position button stays disabled.
		defaultPosition.point, defaultPosition.x, defaultPosition.y = ATTACH_POINT, ATTACH_X, ATTACH_Y
	elseif settings.attached then
		-- Edit Mode with the Pet Frame hidden (no pet out): stand in the attached spot under
		-- UIParent, so the frame can still be selected to change its settings.
		local left, top, scale = GetAttachedPlacement()
		frame:SetParent(UIParent)
		frame:SetScale(scale or 1)
		if left then
			frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
			defaultPosition.point, defaultPosition.x, defaultPosition.y = "TOPLEFT", left / scale, top / scale
		else
			frame:SetPoint("CENTER")
			defaultPosition.point, defaultPosition.x, defaultPosition.y = "CENTER", 0, 0
		end
	else
		local scale = settings.frameSize / 100
		frame:SetParent(UIParent)
		frame:SetScale(scale)
		local defaultPoint, defaultX, defaultY = GetDefaultDetachedPosition(scale)
		local point, x, y = defaultPoint, defaultX, defaultY
		if settings.point then
			point, x, y = settings.point, settings.x, settings.y
		end
		frame:SetPoint(point, UIParent, point, x / scale, y / scale)
		defaultPosition.point, defaultPosition.x, defaultPosition.y = defaultPoint, defaultX / scale, defaultY / scale
	end
end

-- Alpha may change in combat, so it covers what the protected visibility can't do right away: the
-- state driver re-checks only every 0.2 s, and a frame Edit Mode showed stays shown until combat
-- ends. Turning the frame off waits for combat to end like the rest (appliedEnabled): fading it
-- out early would leave an invisible button that still targets the pet's target when clicked.
local function UpdateAlpha()
	local shown = previewing or (appliedEnabled and UnitExists(UNIT) and not UnitIsDead("pet"))
	frame:SetAlpha(shown and 1 or 0)
end

-- Out of combat, follow the pet's target at once instead of waiting for the state driver.
local function SyncVisibility()
	if InCombatLockdown() or previewShown then
		return
	end
	frame:SetShown(appliedEnabled and UnitExists(UNIT) and not UnitIsDead("pet"))
end

-- Like Blizzard's Edit Mode systems, the frame can be selected only while Edit Mode shows it. The
-- selection overlay isn't protected, so this works in combat too.
local function UpdateSelection()
	local selection = LEM.frameSelections[frame]
	if not selection or not LEM:IsInEditMode() then
		return -- LibEditMode shows and hides it with Edit Mode
	end
	if previewing then
		if not selection:IsShown() then
			selection:ShowHighlighted()
		end
	else
		-- LibEditMode can leave its dialog bound to the frame without the frame being selected (when
		-- another addon's LibEditMode frame is clicked), and then shows it again on a layout change.
		local dialog = LEM.internal and LEM.internal.dialog
		if selection.isSelected or (dialog and dialog.selection == selection) then
			ResetEditModeDialog() -- closes and unbinds the settings dialog
		end
		selection:Hide()
	end
end

-- Edit Mode can open and close in combat. The Lua side follows at once; showing the frame and
-- swapping its state driver are protected, so ApplyLayout does that when combat allows.
local function UpdatePreviewState()
	previewing = LEM:IsInEditMode() and ShowsInEditMode()
	UpdateAlpha()
	UpdateSelection()
end

local function UpdatePreviewShown()
	if previewing and not previewShown then
		previewShown = true
		UnregisterStateDriver(frame, "visibility")
		frame:Show()
	elseif not previewing and previewShown then
		previewShown = false
		frame:StopMovingOrSizing()
	end
end

local function UpdateVisibility()
	if not previewShown then
		RegisterStateDriver(frame, "visibility", appliedEnabled and VISIBILITY_DRIVER or "hide")
	end
end

local function ApplyLayout()
	if not InCombatLockdown() then
		appliedEnabled = IsEnabled()
	end
	UpdatePreviewState()
	if InCombatLockdown() then
		pendingLayout = true
		return
	end
	pendingLayout = false
	ApplyPosition()
	UpdatePreviewShown()
	UpdateVisibility()
end

---------------------------------------------------------------------------------------------------
-- Frame contents
---------------------------------------------------------------------------------------------------

local function GetDisplayUnit()
	if UnitExists(UNIT) then
		return UNIT
	elseif previewing then
		-- Stand-in while placing the frame, as Edit Mode shows you in the Target frame.
		return "player"
	end
end

local function IsPlayerUnit(unit)
	local isPlayer = UnitIsUnit(unit, "player")
	return not issecretvalue(isPlayer) and isPlayer
end

-- UnitFrame_Update's name logic, with WoW Forever's GetUnitName (name plus surname). A name is only
-- secret for units that aren't player-controlled, and those have no surname.
local function UpdateName(unit)
	local name, surname = UnitName(unit)
	if not name then
		return
	end
	local nameText = name
	if not issecretvalue(name) and not issecretvalue(surname) then
		if RegionalUniqueNamesEnabled() and not C_PlayerInfo.ShouldDisplaySurname() and IsPlayerUnit(unit) then
			nameText = NameUtil.GetUnitFirstName(unit)
		elseif surname then
			nameText = name .. Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR .. surname
		end
	end
	if UnitInPartyIsAI(unit) and (C_LFGInfo.IsInLFGFollowerDungeon() or C_PartyInfo.IsPartyWalkIn()) then
		nameText = LFG_FOLLOWER_NAME_PREFIX:format(nameText)
	end
	frame.Name:SetText(nameText)
end

-- UnitFramePortrait_Update and UnitFrame_ShouldReplacePortrait. Both portrait copies get the image.
local function UpdatePortrait(unit)
	if UnitIsHumanPlayer(unit) and GetCVarBool(IsPlayerUnit(unit) and "ReplaceMyPlayerPortrait" or "ReplaceOtherPlayerPortraits") then
		local _, class = UnitClass(unit)
		if class then
			local atlas = GetClassAtlas(class)
			frame.Portrait:SetAtlas(atlas)
			frame.PortraitRed:SetAtlas(atlas)
			return
		end
	end
	SetPortraitTexture(frame.Portrait, unit, false)
	SetPortraitTexture(frame.PortraitRed, unit, false)
end

-- TargetOfTargetMixin:HealthCheck tints a player's portrait red at 20% health or less. Health is
-- secret, so the game evaluates these curves on the hidden percentage: the red copy is opaque in
-- (0, 20%], the normal one everywhere else.
local function CreateStepCurve(...)
	local curve = C_CurveUtil.CreateCurve()
	curve:SetType(Enum.LuaCurveType.Step)
	for i = 1, select("#", ...), 2 do
		local x, y = select(i, ...)
		curve:AddPoint(x, y)
	end
	return curve
end

local LOW_HEALTH_ALPHA_CURVE = CreateStepCurve(0, 0, 0.000001, 1, 0.200001, 0)
local NORMAL_HEALTH_ALPHA_CURVE = CreateStepCurve(0, 1, 0.000001, 0, 0.200001, 1)

local function SetPortraitTint(r, g, b)
	frame.Portrait:SetVertexColor(r, g, b, 1)
	frame.Portrait:SetAlpha(1)
	frame.PortraitRed:SetAlpha(0)
end

local function UpdatePortraitTint(unit)
	if not UnitIsPlayer(unit) then
		-- Blizzard leaves the last player's tint in place here; reset it instead.
		SetPortraitTint(1, 1, 1)
	elseif UnitIsDead(unit) then
		SetPortraitTint(0.35, 0.35, 0.35)
	elseif UnitIsGhost(unit) then
		SetPortraitTint(0.2, 0.2, 0.75)
	elseif not UnitIsConnected(unit) then
		SetPortraitTint(1, 1, 1) -- Blizzard fills a disconnected player's bar, so never red
	else
		local lowAlpha = UnitHealthPercent(unit, true, LOW_HEALTH_ALPHA_CURVE)
		local normalAlpha = UnitHealthPercent(unit, true, NORMAL_HEALTH_ALPHA_CURVE)
		if lowAlpha and normalAlpha then
			frame.Portrait:SetVertexColor(1, 1, 1, 1)
			frame.Portrait:SetAlpha(normalAlpha)
			frame.PortraitRed:SetAlpha(lowAlpha)
		else
			SetPortraitTint(1, 1, 1)
		end
	end
end

-- TargetOfTargetMixin:CheckDead. Blizzard tests for zero health, which is secret; dead or
-- unconscious is the same condition.
local function UpdateDeadText(unit)
	local healthBar = frame.HealthBar
	if UnitIsConnected(unit) and (UnitIsDead(unit) or UnitIsUnconscious(unit)) then
		local unconscious = UnitIsUnconscious(unit)
		healthBar.UnconsciousText:SetShown(unconscious)
		healthBar.DeadText:SetShown(not unconscious)
	else
		healthBar.DeadText:Hide()
		healthBar.UnconsciousText:Hide()
	end
end

-- TextStatusBarSparkMixin:UpdateShown shows the spark above the minimum, and at the maximum only
-- with showAtMax. As an alpha curve on the power percentage, since the values are secret.
local SPARK_ALPHA_CURVE = CreateStepCurve(0, 0, 0.000001, 1, 1, 0)
local SPARK_AT_MAX_ALPHA_CURVE = CreateStepCurve(0, 0, 0.000001, 1, 1, 1)

local function UpdateSpark(sparkInfo)
	local manaBar = frame.ManaBar
	local spark = manaBar.Spark
	if not sparkInfo or not sparkInfo.atlas then
		manaBar.sparkCurve = nil
		spark:Hide()
		return
	end
	spark:ClearAllPoints()
	spark:SetPoint("RIGHT", manaBar:GetStatusBarTexture(), "RIGHT", sparkInfo.xOffset or 0, 0)
	spark:SetAtlas(sparkInfo.atlas, true)
	if sparkInfo.barHeight and sparkInfo.barHeight > 0 then
		spark:SetScale(MANA_BAR_HEIGHT / sparkInfo.barHeight)
	end
	manaBar.sparkCurve = sparkInfo.showAtMax and SPARK_AT_MAX_ALPHA_CURVE or SPARK_ALPHA_CURVE
	spark:Show()
end

-- UnitFrameManaBar_UpdateType for frameType "TargetofTarget".
local function UpdatePowerType(unit)
	local manaBar = frame.ManaBar
	local powerType, powerToken, altR, altG, altB = UnitPowerType(unit)
	if not powerType then
		return -- keep the current look (unit APIs can return nothing in PvP matches)
	end
	manaBar.powerType = powerType
	if powerToken == manaBar.powerToken and manaBar.hasPowerVisuals then
		return
	end
	manaBar.powerToken, manaBar.hasPowerVisuals = powerToken, true

	local info = PowerBarColor[powerToken]
	if info then
		if info.atlasElementName then
			manaBar:SetStatusBarTexture("UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-" .. info.atlasElementName)
		elseif info.atlas then
			manaBar:SetStatusBarTexture(info.atlas)
		end
		manaBar:SetStatusBarColor(1, 1, 1)
	else
		local texture = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana"
		manaBar:SetStatusBarColor(1, 1, 1)
		if altR then
			texture = texture .. "-Status"
			manaBar:SetStatusBarColor(altR, altG, altB)
		end
		manaBar:SetStatusBarTexture(texture)
	end
	UpdateSpark(info and info.spark)
end

-- Status text, which the Target of Target doesn't have: it follows the Status Text setting the way
-- the Pet Frame's bars do (TextStatusBarMixin:UpdateTextStringWithValues). Values may be secret, so
-- the text only uses operations that accept them: AbbreviateLargeNumbers, concatenation, and a
-- curve for Blizzard's rounded-up percentage.
local CEIL_PERCENT_CURVE = C_CurveUtil.CreateCurve()
CEIL_PERCENT_CURVE:SetType(Enum.LuaCurveType.Step)
CEIL_PERCENT_CURVE:AddPoint(0, 0)
for percent = 1, 100 do
	CEIL_PERCENT_CURVE:AddPoint((percent - 1) / 100 + 0.000001, percent)
end

local hovered = false -- with Status Text off, Blizzard shows the text while you point at the bar

-- Blizzard leaves out the text of a bar whose maximum is 0, like the power bar of a unit without
-- power (TextStatusBarMixin:UpdateTextStringWithValues). For a unit that isn't player-controlled
-- that maximum is secret, so the game makes the decision: TruncateWhenZero turns it into "" when
-- it is 0, and WrapString keeps the text only if that isn't empty. WrapString also puts the
-- maximum's digits into the result, so they go in as the data of an empty hyperlink, which
-- StripHyperlinks removes again (left in, the game draws it as text).
local StringUtil = C_StringUtil
local canHideSecretZeroMax = StringUtil and StringUtil.TruncateWhenZero and StringUtil.WrapString and StringUtil.StripHyperlinks

local function HideIfMaxIsZero(text, maxValue)
	if not issecretvalue(maxValue) or not canHideSecretZeroMax then
		return text -- no maximum to check, or a readable one that the caller already checked
	end
	local gate = StringUtil.WrapString(StringUtil.TruncateWhenZero(maxValue), "|Hsimplepettarget:", "|h|h")
	return StringUtil.StripHyperlinks(StringUtil.WrapString(gate, text))
end

local function GetPercent(unit, powerType)
	if powerType then
		return UnitPowerPercent(unit, powerType, false, CEIL_PERCENT_CURVE)
	end
	return UnitHealthPercent(unit, true, CEIL_PERCENT_CURVE)
end

-- powerType is nil for the health bar.
local function UpdateBarText(bar, unit, value, maxValue, hidden, powerType, powerToken)
	bar.LeftText:Hide()
	bar.RightText:Hide()
	local textString = bar.TextString
	if hidden or not value or not maxValue or not (hovered or GetCVar("statusText") == "1") then
		textString:Hide()
		return
	end

	-- Only power is checked (HideIfMaxIsZero): a unit without power has a maximum of 0, while a unit
	-- that exists has health. Blizzard's own check for 0 health is only a safety net.
	local powerMax = powerType and maxValue

	local displayMode = GetCVar("statusTextDisplay")
	if displayMode == STATUS_TEXT_DISPLAY_MODE.BOTH then
		-- Blizzard puts the percentage beside the value only for health and mana.
		if not powerType or powerToken == "MANA" then
			local percent = GetPercent(unit, powerType)
			if percent then
				bar.LeftText:SetText(HideIfMaxIsZero(percent .. "%", powerMax))
				bar.LeftText:Show()
			end
		end
		bar.RightText:SetText(HideIfMaxIsZero(AbbreviateLargeNumbers(value), powerMax))
		bar.RightText:Show()
		textString:Hide()
		return
	end

	local text
	if displayMode == STATUS_TEXT_DISPLAY_MODE.PERCENT then
		local percent = GetPercent(unit, powerType)
		text = percent and percent .. "%"
	end
	text = text or AbbreviateLargeNumbers(value) .. " / " .. AbbreviateLargeNumbers(maxValue)
	textString:SetText(HideIfMaxIsZero(text, powerMax))
	textString:Show()
end

frame:HookScript("OnEnter", function()
	hovered = true
end)
frame:HookScript("OnLeave", function()
	hovered = false
end)

-- UnitFrameHealthBar_Update and UnitFrameManaBar_Update. The bars keep Blizzard's atlas colors.
-- Values are only checked for nil: in PvP matches these APIs may return nothing for "pettarget",
-- and then the bars show empty rather than the previous target's values.
local function UpdateBars(unit)
	local healthBar, manaBar = frame.HealthBar, frame.ManaBar
	local powerType = manaBar.powerType

	local maxHealth = UnitHealthMax(unit)
	local noMaxHealth = maxHealth and not issecretvalue(maxHealth) and maxHealth == 0
	if noMaxHealth then
		maxHealth = 1 -- Blizzard's guard against an empty bar; it also hides the text
	end
	local maxPower = UnitPowerMax(unit, powerType)

	local health, power
	if UnitIsConnected(unit) then
		health, power = UnitHealth(unit), UnitPower(unit, powerType)
	elseif UnitIsDead(unit) then
		health, power = 0, 0
	else
		health, power = maxHealth, maxPower
	end

	healthBar:SetMinMaxValues(0, maxHealth or 1)
	healthBar:SetValue(health or 0)
	manaBar:SetMinMaxValues(0, maxPower or 1)
	manaBar:SetValue(power or 0)

	if manaBar.sparkCurve then
		manaBar.Spark:SetAlpha(UnitPowerPercent(unit, powerType, false, manaBar.sparkCurve) or 0)
	end

	-- No text over DEAD or UNCONSCIOUS (the Target of Target's zero text), or for a power the unit
	-- doesn't have (Blizzard hides it when the maximum is 0).
	local deadTextShown = healthBar.DeadText:IsShown() or healthBar.UnconsciousText:IsShown()
	UpdateBarText(healthBar, unit, health, maxHealth, noMaxHealth or deadTextShown)
	local noPower = not (powerType and UnitHasPowerType(unit, powerType)) or (maxPower and not issecretvalue(maxPower) and maxPower <= 0)
	UpdateBarText(manaBar, unit, power, maxPower, noPower, powerType, manaBar.powerToken)
end

---------------------------------------------------------------------------------------------------
-- Debuffs (AuraUtil.RefreshAuras for the Target of Target)
---------------------------------------------------------------------------------------------------

local dispelColorCurve, dispelProbeCurve

local function BuildDispelColorCurve()
	local colorsByID = {}
	for name, id in pairs(KNOWN_DISPEL_TYPE_IDS) do
		colorsByID[id] = AuraUtil.GetAuraBorderColor(name)
	end
	for name, id in pairs(db and db.dispelTypeIDs or {}) do
		colorsByID[id] = AuraUtil.GetAuraBorderColor(name)
	end
	local ids = {}
	for id in pairs(colorsByID) do
		table.insert(ids, id)
	end
	table.sort(ids)

	local noneColor = AuraUtil.GetAuraBorderColor(nil)
	dispelColorCurve = C_CurveUtil.CreateColorCurve()
	dispelColorCurve:SetType(Enum.LuaCurveType.Step)
	dispelColorCurve:AddPoint(0, noneColor)
	for _, id in ipairs(ids) do
		dispelColorCurve:AddPoint(id, colorsByID[id])
		if not colorsByID[id + 1] then
			dispelColorCurve:AddPoint(id + 1, noneColor) -- unlisted types get the default color
		end
	end
end

-- Out of combat the dispel type name is readable, so ask the game which curve input it uses: a
-- linear red ramp turns the ID into the red channel. The result is saved for use in combat.
local function LearnDispelTypeID(unit, aura)
	local name, auraInstanceID = aura.dispelName, aura.auraInstanceID
	if not db or issecretvalue(name) or issecretvalue(auraInstanceID) or not name or not auraInstanceID or db.dispelTypeIDs[name] then
		return
	end
	if not dispelProbeCurve then
		dispelProbeCurve = C_CurveUtil.CreateColorCurve()
		dispelProbeCurve:SetType(Enum.LuaCurveType.Linear)
		dispelProbeCurve:AddPoint(0, CreateColor(0, 0, 0, 1))
		dispelProbeCurve:AddPoint(255, CreateColor(1, 0, 0, 1))
	end
	local ok, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, dispelProbeCurve)
	if ok and color and not issecretvalue(color) and canaccesstable(color) and not issecretvalue(color.r) then
		db.dispelTypeIDs[name] = math.floor(color.r * 255 + 0.5)
		dispelColorCurve = nil -- rebuild with the learned ID
	end
end

-- AuraUtil.SetAuraBorderColor, with a curve when the dispel type name is secret.
local function SetBorderColor(border, unit, aura)
	local dispelName = aura.dispelName
	if not issecretvalue(dispelName) then
		AuraUtil.SetAuraBorderColor(border, dispelName)
		return
	end
	local auraInstanceID = aura.auraInstanceID
	if not issecretvalue(auraInstanceID) then
		if not dispelColorCurve then
			BuildDispelColorCurve()
		end
		local ok, color = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, auraInstanceID, dispelColorCurve)
		if ok and color and not issecretvalue(color) and canaccesstable(color) then
			border:SetVertexColor(color.r, color.g, color.b, color.a)
			return
		end
	end
	AuraUtil.SetAuraBorderColor(border, nil)
end

-- CooldownFrame_Set(cooldown, expirationTime - duration, duration, true), or a duration object
-- when the times are secret (the only way addons can show a secret cooldown).
local function SetDebuffCooldown(cooldown, unit, aura)
	local duration, expirationTime = aura.duration, aura.expirationTime
	if not issecretvalue(duration) and not issecretvalue(expirationTime) then
		CooldownFrame_Set(cooldown, expirationTime - duration, duration, true)
		return
	end
	local auraInstanceID = aura.auraInstanceID
	local durationObject = not issecretvalue(auraInstanceID) and C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
	if durationObject then
		cooldown:SetDrawEdge(false)
		cooldown:SetCooldownFromDurationObject(durationObject, true)
	else
		cooldown:Clear()
	end
end

local function ShowDebuff(button, unit, aura, auraIndex, tooltipFilter)
	button.unit, button.auraIndex, button.tooltipFilter = unit, auraIndex, tooltipFilter
	button.Icon:SetTexture(aura.icon)
	SetBorderColor(button.Border, unit, aura)
	SetDebuffCooldown(button.Cooldown, unit, aura)
	button:Show()
end

local function UpdateDebuffs(unit)
	local showDispellable = GetCVarBool("showDispelDebuffs") and UnitCanAssist("player", unit)
	local filter = showDispellable and "HARMFUL|RAID" or "HARMFUL"
	local tooltipFilter = showDispellable and "RAID" or nil
	-- On enemies Blizzard only shows your own debuffs (SHOW_CASTABLE_DEBUFFS is normally unset). It
	-- checks each debuff's caster, which is secret in combat, so ask for them with a filter instead.
	if UnitCanAttack("player", unit) and SHOW_CASTABLE_DEBUFFS ~= "0" then
		filter = filter .. "|PLAYER"
		tooltipFilter = tooltipFilter and tooltipFilter .. "|PLAYER" or "PLAYER"
	end

	-- Addons get a Lua error from the aura APIs while auras are secret (combat and similar), so the
	-- debuffs stay hidden then. Interim until the secure aura container takes over.
	--
	-- In Edit Mode the stand-in shows its real debuffs, not Blizzard's sample ones. AuraUtil builds
	-- the samples on first use, and built from addon code they taint any Blizzard code that reads
	-- them later: Edit Mode's own setup reads them (party frames) before it refreshes the Cooldown
	-- Manager and Damage Meter, which then failed with "tainted by SimplePetTarget" errors.
	local numShown = 0
	if not C_Secrets.ShouldAurasBeSecret() then
		local index = 1
		while numShown < NUM_DEBUFFS do
			local aura = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
			if not aura then
				break
			end
			if aura.icon then
				numShown = numShown + 1
				LearnDispelTypeID(unit, aura)
				ShowDebuff(debuffs[numShown], unit, aura, index, tooltipFilter)
			end
			index = index + 1
		end
	end
	for i = numShown + 1, NUM_DEBUFFS do
		debuffs[i]:Hide()
	end
end

local function Debuff_OnEnter(self)
	local x = self:GetCenter()
	if x and not issecretvalue(x) and x > GetScreenWidth() / 2 then
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	else
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	end
	-- Blizzard passes the button's ID as the debuff index, which points at the wrong debuff when
	-- only your own are listed. The index we listed it under always matches the icon.
	GameTooltip:SetUnitDebuff(self.unit, self.auraIndex, self.tooltipFilter)
end

local function Debuff_OnLeave()
	GameTooltip:Hide()
end

for _, button in ipairs(debuffs) do
	button:SetScript("OnEnter", Debuff_OnEnter)
	button:SetScript("OnLeave", Debuff_OnLeave)
end

---------------------------------------------------------------------------------------------------
-- Updating
---------------------------------------------------------------------------------------------------

-- Blizzard's Target of Target refreshes everything every frame. The bars still do; the rest runs
-- every FULL_UPDATE_INTERVAL and right away when the pet changes target.
local FAST_UPDATES = { UpdateBars, UpdatePortraitTint }
local FULL_UPDATES = { UpdateName, UpdatePortrait, UpdatePowerType, UpdateBars, UpdateDeadText, UpdatePortraitTint, UpdateDebuffs }

local function RunUpdates(updates)
	local unit = GetDisplayUnit()
	if unit then
		for _, update in ipairs(updates) do
			RunProtected(update, unit)
		end
	end
end

local timeSinceFullUpdate = 0
local function FullUpdate()
	timeSinceFullUpdate = 0
	RunUpdates(FULL_UPDATES)
end

frame:SetScript("OnShow", function()
	UpdateAlpha()
	FullUpdate()
end)
frame:SetScript("OnUpdate", function(_, elapsed)
	UpdateAlpha()
	timeSinceFullUpdate = timeSinceFullUpdate + elapsed
	if timeSinceFullUpdate >= FULL_UPDATE_INTERVAL then
		FullUpdate()
	else
		RunUpdates(FAST_UPDATES)
	end
end)

---------------------------------------------------------------------------------------------------
-- Edit Mode
---------------------------------------------------------------------------------------------------

local function OnPositionChanged(_, layoutName, point, x, y)
	if not layoutName then
		return
	end
	local settings = GetSettings(layoutName)
	if not settings.attached then
		local scale = frame:GetScale()
		settings.point, settings.x, settings.y = point, x * scale, y * scale
	end
	ApplyLayout() -- an attached frame goes back next to the Pet Frame
end

local function FormatFrameSize(value)
	return FormatPercentage(value / 100, true)
end

-- The frame's own Edit Mode settings, per layout. Turning it on or off and showing it in Edit Mode
-- are account-wide, so they live in Options and beside the HUD Edit Mode window instead.
local SETTINGS = {
	{
		kind = LEM.SettingType.Checkbox,
		name = "Attach to Pet Frame",
		desc = "Sit next to the Pet Frame and follow its position and size, like Target of Target follows the Target frame.",
		default = DEFAULT_SETTINGS.attached,
		get = function(layoutName)
			return GetSettings(layoutName).attached
		end,
		set = function(layoutName, value, fromReset)
			if not layoutName then
				return
			end
			local settings = GetSettings(layoutName)
			if settings.attached == value then
				return
			end
			if not value then
				-- Detach in place, at the size the frame had next to the Pet Frame.
				local left, top, scale = GetAttachedPlacement()
				if left then
					local frameSize = math.floor(scale * 100 / FRAME_SIZE_STEP + 0.5) * FRAME_SIZE_STEP
					frameSize = math.min(math.max(frameSize, FRAME_SIZE_MIN), FRAME_SIZE_MAX)
					local frameScale = frameSize / 100
					settings.frameSize = frameSize
					settings.point, settings.x, settings.y = NormalizeRect(left, top, left + FRAME_WIDTH * frameScale, top - FRAME_HEIGHT * frameScale)
				end
			end
			settings.attached = value
			ApplyLayout()
			if not fromReset then
				-- Detaching can change the stored Frame Size, which the open slider doesn't know
				-- about; rebuild the dialog once LibEditMode has finished handling the click.
				C_Timer.After(0, function()
					LEM:RefreshFrameSettings(frame)
				end)
			end
		end,
	},
	{
		kind = LEM.SettingType.Slider,
		name = HUD_EDIT_MODE_SETTING_UNIT_FRAME_FRAME_SIZE,
		desc = "Attached frames use the Pet Frame's size.",
		default = DEFAULT_SETTINGS.frameSize,
		minValue = FRAME_SIZE_MIN,
		maxValue = FRAME_SIZE_MAX,
		valueStep = FRAME_SIZE_STEP,
		formatter = FormatFrameSize,
		disabled = function(layoutName)
			return GetSettings(layoutName).attached
		end,
		get = function(layoutName)
			return GetSettings(layoutName).frameSize
		end,
		set = function(layoutName, value)
			if layoutName then
				GetSettings(layoutName).frameSize = value
				ApplyLayout()
			end
		end,
	},
}

-- LibEditMode names the preset layouts in English but reports a copied preset by its localized name.
local PRESET_LAYOUT_KEYS = {}
for key, globalName in pairs({ Modern = "LAYOUT_STYLE_MODERN", Classic = "LAYOUT_STYLE_CLASSIC", Gamepad = "LAYOUT_STYLE_GAMEPAD" }) do
	if _G[globalName] then
		PRESET_LAYOUT_KEYS[_G[globalName]] = key
	end
end

local function OnLayoutCreated(layoutName, _, sourceLayoutName)
	-- Never overwrite: LibEditMode can report an existing layout here when the list shifts.
	if db.layouts[layoutName] then
		return
	end
	local sourceName = sourceLayoutName and (PRESET_LAYOUT_KEYS[sourceLayoutName] or sourceLayoutName) or LEM:GetActiveLayoutName()
	local source = sourceName and db.layouts[sourceName]
	db.layouts[layoutName] = CopyTable(source or DEFAULT_SETTINGS)
end

local function OnLayoutRenamed(oldLayoutName, newLayoutName)
	if db.layouts[oldLayoutName] and not db.layouts[newLayoutName] then
		db.layouts[newLayoutName] = db.layouts[oldLayoutName]
	end
	db.layouts[oldLayoutName] = nil
end

local function OnLayoutDeleted(layoutName)
	db.layouts[layoutName] = nil
end

---------------------------------------------------------------------------------------------------
-- Show/hide options: Options > AddOns, and a panel beside the HUD Edit Mode window
---------------------------------------------------------------------------------------------------

-- Blizzard's checkboxes for which frames Edit Mode shows live in the HUD Edit Mode window. Addons
-- can't add to that window without tainting Edit Mode, so this small panel sits beside it instead,
-- with the same checkbox. It only exists while Edit Mode is open.
local EDIT_MODE_PANEL_PADDING = 15
local EDIT_MODE_PANEL_GAP = 2

local editModePanel = CreateFrame("Frame", nil, UIParent)
editModePanel:Hide()
editModePanel:SetFrameStrata("DIALOG")
editModePanel:SetClampedToScreen(true)
editModePanel:EnableMouse(true) -- clicks on the panel shouldn't reach the frames behind it
editModePanel:SetPoint("TOPLEFT", EditModeManagerFrame, "TOPRIGHT", EDIT_MODE_PANEL_GAP, 0)

local editModePanelBorder = CreateFrame("Frame", nil, editModePanel, "DialogBorderTranslucentTemplate")
editModePanelBorder:SetAllPoints()

local editModePanelTitle = editModePanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
editModePanelTitle:SetPoint("TOP", 0, -EDIT_MODE_PANEL_PADDING)
editModePanelTitle:SetText("Simple Pet Target")

local editModeCheckbox = CreateFrame("Frame", nil, editModePanel, "EditModeManagerSettingCheckButtonTemplate")
editModeCheckbox:ClearAllPoints()
editModeCheckbox:SetPoint("TOPLEFT", EDIT_MODE_PANEL_PADDING, -(EDIT_MODE_PANEL_PADDING + 25))
editModeCheckbox:SetLabelText(SYSTEM_NAME)
-- Like Blizzard's checkboxes for frames whose option is off: greyed out, with a tooltip saying why.
editModeCheckbox.disabledTooltipText = "Turn on Show Pet Target Frame in Options > AddOns > Simple Pet Target to place this frame."
function editModeCheckbox:ShouldEnable()
	return IsEnabled()
end
editModeCheckbox:SetCallback(function(checked, isUserInput)
	if isUserInput and db then
		checkedForSession = false
		db.showInEditMode = checked
		ApplyLayout()
	end
end)

editModePanel:SetSize(editModeCheckbox:GetWidth() + EDIT_MODE_PANEL_PADDING * 2, EDIT_MODE_PANEL_PADDING * 2 + 25 + editModeCheckbox:GetHeight())

-- Beside the Edit Mode window on whichever side has room: right, else left, below or above. The
-- window can be dragged anywhere, and a panel clamped to the screen would slide underneath it.
local panelPlacement
local function PlaceEditModePanel()
	local left, right = EditModeManagerFrame:GetLeft(), EditModeManagerFrame:GetRight()
	local top, bottom = EditModeManagerFrame:GetTop(), EditModeManagerFrame:GetBottom()
	if not left or not right or not top or not bottom or issecretvalue(left) or issecretvalue(right) or issecretvalue(top) or issecretvalue(bottom) then
		return
	end
	local scale = EditModeManagerFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
	left, right, top, bottom = left * scale, right * scale, top * scale, bottom * scale -- UIParent units
	local width, height = editModePanel:GetSize()
	local placement = "right"
	if right + EDIT_MODE_PANEL_GAP + width > UIParent:GetRight() then
		if left - EDIT_MODE_PANEL_GAP - width >= UIParent:GetLeft() then
			placement = "left"
		elseif bottom - EDIT_MODE_PANEL_GAP - height >= UIParent:GetBottom() then
			placement = "below"
		elseif top + EDIT_MODE_PANEL_GAP + height <= UIParent:GetTop() then
			placement = "above"
		end
	end
	if placement == panelPlacement then
		return
	end
	panelPlacement = placement
	editModePanel:ClearAllPoints()
	if placement == "left" then
		editModePanel:SetPoint("TOPRIGHT", EditModeManagerFrame, "TOPLEFT", -EDIT_MODE_PANEL_GAP, 0)
	elseif placement == "below" then
		editModePanel:SetPoint("TOP", EditModeManagerFrame, "BOTTOM", 0, -EDIT_MODE_PANEL_GAP)
	elseif placement == "above" then
		editModePanel:SetPoint("BOTTOM", EditModeManagerFrame, "TOP", 0, EDIT_MODE_PANEL_GAP)
	else
		editModePanel:SetPoint("TOPLEFT", EditModeManagerFrame, "TOPRIGHT", EDIT_MODE_PANEL_GAP, 0)
	end
end

local petFrameVisible
editModePanel:SetScript("OnShow", function()
	panelPlacement = nil
	PlaceEditModePanel()
	petFrameVisible = PetFrame:IsVisible()
	editModeCheckbox:SetControlChecked(IsEditModeChecked())
	editModeCheckbox:UpdateDisplay()
end)
-- While Edit Mode shows an attached frame, it stands in for itself when the Pet Frame is hidden, so
-- it is re-placed when the Pet Frame appears or disappears (for example through Blizzard's Pet
-- Frame checkbox). Checked here, while Edit Mode is open, rather than by hooking the Pet Frame.
editModePanel:SetScript("OnUpdate", function()
	PlaceEditModePanel()
	local visible = PetFrame:IsVisible()
	if visible ~= petFrameVisible then
		petFrameVisible = visible
		if previewing then
			ApplyLayout()
		end
	end
end)

local function OnEnabledChanged()
	ApplyLayout()
	if editModePanel:IsShown() then
		editModeCheckbox:UpdateDisplay()
	end
end

local function RegisterOptions()
	local category = Settings.RegisterVerticalLayoutCategory("Simple Pet Target")
	local setting = Settings.RegisterAddOnSetting(category, "SIMPLE_PET_TARGET_ENABLED", "enabled", db, Settings.VarType.Boolean, "Show Pet Target Frame", true)
	setting:SetValueChangedCallback(OnEnabledChanged)
	Settings.CreateCheckbox(category, setting, "Shows your pet's target in a frame like Target of Target, next to the Pet Frame or wherever you place it in Edit Mode. A change made in combat takes effect when combat ends.")
	Settings.RegisterAddOnCategory(category)
end

local function OnEditModeEnter()
	-- Like Blizzard's Pet Frame checkbox (SetupPetFrame): a frame that is already showing can always
	-- be placed, so the box checks itself for this session, without saving that.
	checkedForSession = IsEnabled() and UnitExists(UNIT) and not UnitIsDead("pet")
	editModePanel:Show()
	ApplyLayout()
end

local function OnEditModeExit()
	checkedForSession = false
	editModePanel:Hide()
	ResetEditModeDialog()
	ApplyLayout()
end

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")

local function OnAddonLoaded()
	SimplePetTargetDB = SimplePetTargetDB or {}
	db = SimplePetTargetDB
	db.layouts = db.layouts or {}
	db.dispelTypeIDs = db.dispelTypeIDs or {}
	-- The first beta turned the frame on and off per layout; that is account-wide (db.enabled) now.
	for _, settings in pairs(db.layouts) do
		settings.enabled = nil
	end

	RegisterOptions()

	-- Registered after the saved variables load: LibEditMode can report the active layout at once.
	LEM:AddFrame(frame, OnPositionChanged, defaultPosition, SYSTEM_NAME)
	LEM:AddFrameSettings(frame, SETTINGS)

	-- An attached frame moves with the Pet Frame, so ignore drags on it in Edit Mode.
	local selection = LEM.frameSelections[frame]
	local startDrag = selection:GetScript("OnDragStart")
	selection:SetScript("OnDragStart", function(self, ...)
		if not GetActiveSettings().attached then
			startDrag(self, ...)
		end
	end)
	-- LibEditMode shows every selection again whenever it resets them; keep this one hidden while
	-- Edit Mode doesn't show the frame (UpdateSelection).
	selection:HookScript("OnShow", function(self)
		if not ShowsInEditMode() then
			self:Hide()
		end
	end)

	LEM:RegisterCallback("enter", OnEditModeEnter)
	LEM:RegisterCallback("exit", OnEditModeExit)
	LEM:RegisterCallback("layout", ApplyLayout)
	LEM:RegisterCallback("create", OnLayoutCreated)
	LEM:RegisterCallback("rename", OnLayoutRenamed)
	LEM:RegisterCallback("delete", OnLayoutDeleted)
	ApplyLayout()
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == addonName then
			events:UnregisterEvent("ADDON_LOADED")
			OnAddonLoaded()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		ApplyLayout()
		if frame:IsShown() then
			FullUpdate()
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		if LEM:IsInEditMode() then
			ResetEditModeDialog()
		end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if pendingLayout then
			ApplyLayout()
		end
	else
		-- UNIT_TARGET (pet), UNIT_PET, PORTRAITS_UPDATED: "pettarget" has no unit events of its own.
		SyncVisibility()
		if frame:IsShown() then
			FullUpdate()
		end
	end
end)

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PORTRAITS_UPDATED")
events:RegisterUnitEvent("UNIT_TARGET", "pet")
events:RegisterUnitEvent("UNIT_PET", "player")
