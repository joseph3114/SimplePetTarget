-- A small stand-in for the parts of the WoW Forever client that Simple Pet Target and LibEditMode
-- use, so the addon can be loaded and driven outside the game. It is not a faithful client: it
-- models what the tests check.
--
-- Modelled: frames (shown flags, visibility and OnShow/OnHide, parents, scripts and hooks), protected
-- frames that refuse changes from addon code in combat, state drivers, EventRegistry, a stand-in for
-- Blizzard's Edit Mode manager (with its Pet Frame checkbox rules), the Settings API, units with
-- secret values, curves, C_StringUtil and Blizzard's secure aura container.
--
-- The runner loads this file into a fresh environment for every test.

LOG = {}
local function log(...)
	local t = {}
	for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
	LOG[#LOG + 1] = table.concat(t, " ")
end
_G.SIMLOG = log

ERRORS = {}
BLOCKED = {}

STATE = { inCombat = false, secureDepth = 0, time = 0 }

local SECURE_FUNCS = setmetatable({}, { __mode = "k" })
local function MarkSecure(fn) SECURE_FUNCS[fn] = true; return fn end
_G.MarkSecure = MarkSecure

local function RunSecure(fn, ...)
	STATE.secureDepth = STATE.secureDepth + 1
	local ok, err = pcall(fn, ...)
	STATE.secureDepth = STATE.secureDepth - 1
	if not ok then ERRORS[#ERRORS + 1] = "secure: " .. tostring(err) end
end
_G.RunSecure = RunSecure

local function RunInsecure(fn, ...)
	local saved = STATE.secureDepth
	STATE.secureDepth = 0
	local ok, err = pcall(fn, ...)
	STATE.secureDepth = saved
	if not ok then ERRORS[#ERRORS + 1] = tostring(err) end
end

function InCombatLockdown() return STATE.inCombat end
function issecure() return STATE.secureDepth > 0 end

---------------------------------------------------------------------------------------------------
-- Generic stubs
---------------------------------------------------------------------------------------------------
local function nop() end
_G.nop = nop
table.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
wipe = table.wipe

local StubMT = {}
StubMT.__index = function(t, k) return nop end
local function Stub(name)
	return setmetatable({ __stubname = name }, StubMT)
end

function Mixin(object, ...)
	for i = 1, select("#", ...) do
		local mixin = select(i, ...)
		for k, v in pairs(mixin) do object[k] = v end
	end
	return object
end
function CreateFromMixins(...) return Mixin({}, ...) end
function CreateAndInitFromMixin(mixin, ...) local o = CreateFromMixins(mixin); o:Init(...); return o end
function CopyTable(t, shallow)
	local c = {}
	for k, v in pairs(t) do
		if type(v) == "table" and not shallow then c[k] = CopyTable(v) else c[k] = v end
	end
	return c
end
function GenerateClosure(f, ...)
	local args = { n = select("#", ...), ... }
	return function(...)
		local all = {}
		for i = 1, args.n do all[i] = args[i] end
		local n = args.n
		for i = 1, select("#", ...) do all[n + i] = (select(i, ...)) end
		return f(unpack(all, 1, n + select("#", ...)))
	end
end
function securecallfunction(f, ...) return f(...) end
function secureexecuterange(t, f, ...) for i, v in ipairs(t) do f(i, v, ...) end end
function hooksecurefunc(tbl, name, hook)
	if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
	local orig = tbl[name]
	tbl[name] = function(...)
		local r = { orig(...) }
		local args = { n = select("#", ...), ... }
		RunInsecure(function() hook(unpack(args, 1, args.n)) end)
		return unpack(r)
	end
end
function geterrorhandler() return function(err) ERRORS[#ERRORS + 1] = "handler: " .. tostring(err) end end
function PlaySound() end
SOUNDKIT = setmetatable({}, { __index = function() return 0 end })
function GetTime() return STATE.time end

local Color = {}
Color.__index = Color
function Color:GetRGB() return self.r, self.g, self.b end
function Color:GetRGBA() return self.r, self.g, self.b, self.a end
function CreateColor(r, g, b, a) return setmetatable({ r = r, g = g, b = b, a = a or 1 }, Color) end
WHITE_FONT_COLOR = CreateColor(1, 1, 1)
DISABLED_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)

HUD_EDIT_MODE_RESET_POSITION = "Reset Position"
RESET_TO_DEFAULT = "Reset To Default"
HEADER_COLON = ":"
HUD_EDIT_MODE_SETTING_UNIT_FRAME_FRAME_SIZE = "Frame Size"
HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT = "Click to edit"
LAYOUT_STYLE_MODERN = "Modern"
LAYOUT_STYLE_CLASSIC = "Classic"
EDIT_MODE_MODERN_SYSTEM_MAP = {}
EDIT_MODE_CLASSIC_SYSTEM_MAP = {}
function FormatPercentage(v) return tostring(math.floor(v * 100 + 0.5)) .. "%" end

Enum = {
	EditModeSettingDisplayType = { Dropdown = 0, Checkbox = 1, Slider = 2 },
	LuaCurveType = { Linear = 0, Step = 1 },
	CustomAuraButtonDispelTypeTextureStyle = { Recolor = 0, PreserveAsset = 1 },
}

---------------------------------------------------------------------------------------------------
-- Secret values
---------------------------------------------------------------------------------------------------
-- A secret wraps a value that addon code may pass to widgets and to the APIs that accept secrets,
-- but may not read. Comparing one or doing arithmetic on one raises an error, as in the client.
-- Concatenation is allowed and gives another secret. Tests read them back with Reveal.
local SecretMT = {}
local function Secret(v) return setmetatable({ __value = v }, SecretMT) end
local function IsSecret(v) return getmetatable(v) == SecretMT end
local function Reveal(v) if IsSecret(v) then return rawget(v, "__value") end return v end
_G.Secret, _G.Reveal = Secret, Reveal
local function SecretError() error("attempt to compare or do arithmetic on a secret value", 2) end
for _, m in ipairs({ "__lt", "__le", "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__len" }) do
	SecretMT[m] = SecretError
end
SecretMT.__concat = function(a, b) return Secret(tostring(Reveal(a)) .. tostring(Reveal(b))) end
SecretMT.__index = function() SecretError() end
SecretMT.__newindex = function() SecretError() end
function issecretvalue(v) return IsSecret(v) end
-- Wraps the result in a secret if any input was one.
local function Propagate(result, ...)
	for i = 1, select("#", ...) do
		if IsSecret((select(i, ...))) then return Secret(result) end
	end
	return result
end
_G.Propagate = Propagate

local Curve = {}
Curve.__index = Curve
function Curve:SetType(t) self.type = t end
function Curve:AddPoint(x, y) table.insert(self.points, { x, y }); table.sort(self.points, function(a, b) return a[1] < b[1] end) end
-- Step curves only, which is all the addon uses: the y of the last point at or before x.
function Curve:Evaluate(x)
	x = Reveal(x)
	local y = self.points[1] and self.points[1][2]
	for _, p in ipairs(self.points) do
		if p[1] <= x then y = p[2] end
	end
	return y
end
C_CurveUtil = {
	CreateCurve = function() return setmetatable({ points = {} }, Curve) end,
	CreateColorCurve = function() return setmetatable({ points = {} }, Curve) end,
}

-- The string helpers that accept secrets.
C_StringUtil = {}
function C_StringUtil.TruncateWhenZero(v)
	local n = Reveal(v)
	return Propagate(n == 0 and "" or tostring(n), v)
end
function C_StringUtil.WrapString(infix, prefix, suffix)
	local s = Reveal(infix)
	local result = (s == nil or s == "") and "" or (Reveal(prefix) or "") .. s .. (Reveal(suffix) or "")
	return Propagate(result, infix, prefix, suffix)
end
function C_StringUtil.StripHyperlinks(text)
	local s = Reveal(text)
	s = s:gsub("|H.-|h(.-)|h", "%1")
	return Propagate(s, text)
end

---------------------------------------------------------------------------------------------------
-- Regions and frames
---------------------------------------------------------------------------------------------------
ALL_FRAMES = {}

local RESTRICTED = {
	Show = true, Hide = true, SetShown = true, SetPoint = true, ClearAllPoints = true, SetAllPoints = true,
	SetParent = true, SetScale = true, SetClampedToScreen = true, SetMovable = true, StartMoving = true,
	SetSize = true, SetWidth = true, SetHeight = true, EnableMouse = true, SetAttribute = true,
}

local Region = {}
local RegionMT = {}
RegionMT.__index = function(t, k)
	local v = Region[k]
	if v ~= nil then
		if RESTRICTED[k] then
			return function(self, ...)
				if rawget(self, "__protected") and STATE.inCombat and STATE.secureDepth == 0 then
					BLOCKED[#BLOCKED + 1] = (rawget(self, "__name") or "?") .. ":" .. k
					return
				end
				return v(self, ...)
			end
		end
		return v
	end
	return nil
end

local function IsProtected(f) return rawget(f, "__protected") end

local function NewRegion(kind, name, parent)
	local r = setmetatable({}, RegionMT)
	rawset(r, "__kind", kind)
	rawset(r, "__name", name)
	rawset(r, "__shown", true)
	rawset(r, "__children", {})
	rawset(r, "__scripts", {})
	rawset(r, "__hooks", {})
	rawset(r, "__alpha", 1)
	rawset(r, "__scale", 1)
	rawset(r, "__points", {})
	rawset(r, "__width", 10)
	rawset(r, "__height", 10)
	rawset(r, "__events", {})
	rawset(r, "__attrs", {})
	if parent then
		rawset(r, "__parent", parent)
		table.insert(rawget(parent, "__children"), r)
	end
	if name then _G[name] = r end
	ALL_FRAMES[#ALL_FRAMES + 1] = r
	return r
end
_G.NewRegion = NewRegion

local function IsVisibleRaw(f)
	if not rawget(f, "__shown") then return false end
	local p = rawget(f, "__parent")
	if not p then return true end
	return IsVisibleRaw(p)
end

local function FireScript(f, name, ...)
	local script = rawget(f, "__scripts")[name]
	if script then
		if SECURE_FUNCS[script] then
			local args = { n = select("#", ...), ... }
			RunSecure(function() script(f, unpack(args, 1, args.n)) end)
		else
			RunInsecure(script, f, ...)
		end
	end
	for _, hook in ipairs(rawget(f, "__hooks")[name] or {}) do
		RunInsecure(hook, f, ...)
	end
end
_G.FireScript = FireScript

-- Fire OnShow/OnHide for f and descendants whose visibility changed. 'before' maps frame -> visible.
local function Snapshot(f, map)
	map[f] = IsVisibleRaw(f)
	for _, c in ipairs(rawget(f, "__children")) do Snapshot(c, map) end
	return map
end
local function FireVisibilityChanges(f, before)
	local now = IsVisibleRaw(f)
	if before[f] ~= now then
		FireScript(f, now and "OnShow" or "OnHide")
	end
	for _, c in ipairs(rawget(f, "__children")) do
		if before[c] ~= nil then FireVisibilityChanges(c, before) end
	end
end

function Region:Show()
	if rawget(self, "__shown") then return end
	local before = Snapshot(self, {})
	rawset(self, "__shown", true)
	FireVisibilityChanges(self, before)
end
function Region:Hide()
	if not rawget(self, "__shown") then return end
	local before = Snapshot(self, {})
	rawset(self, "__shown", false)
	FireVisibilityChanges(self, before)
end
function Region:SetShown(shown) if shown then self:Show() else self:Hide() end end
function Region:IsShown() return rawget(self, "__shown") end
function Region:IsVisible() return IsVisibleRaw(self) end
function Region:GetParent() return rawget(self, "__parent") end
function Region:SetParent(p)
	local old = rawget(self, "__parent")
	if old == p then return end
	local before = Snapshot(self, {})
	if old then
		local ch = rawget(old, "__children")
		for i, c in ipairs(ch) do if c == self then table.remove(ch, i) break end end
	end
	rawset(self, "__parent", p)
	if p then table.insert(rawget(p, "__children"), self) end
	FireVisibilityChanges(self, before)
end
function Region:GetName() return rawget(self, "__name") end
function Region:SetScript(name, fn) rawget(self, "__scripts")[name] = fn end
function Region:GetScript(name) return rawget(self, "__scripts")[name] end
function Region:HookScript(name, fn)
	local h = rawget(self, "__hooks")
	h[name] = h[name] or {}
	table.insert(h[name], fn)
end
function Region:SetAlpha(a) rawset(self, "__alpha", a) end
function Region:GetAlpha() return rawget(self, "__alpha") end
function Region:SetScale(s) rawset(self, "__scale", s) end
function Region:GetScale() return rawget(self, "__scale") end
function Region:GetEffectiveScale()
	local p = rawget(self, "__parent")
	return rawget(self, "__scale") * (p and p:GetEffectiveScale() or 1)
end
function Region:SetPoint(point, a, b, c, d)
	local rel, relPoint, x, y = a, b, c, d
	if type(a) == "number" then rel, relPoint, x, y = rawget(self, "__parent"), point, a, b
	elseif type(a) == "string" then rel, relPoint, x, y = _G[a], b, c, d end
	if rel == nil and a == nil then rel = rawget(self, "__parent") end
	table.insert(rawget(self, "__points"), { point, rel, relPoint or point, x or 0, y or 0 })
end
function Region:ClearAllPoints() rawset(self, "__points", {}) end
function Region:SetAllPoints(rel) rawset(self, "__points", { { "TOPLEFT", rel or rawget(self, "__parent"), "TOPLEFT", 0, 0 } }) end
function Region:GetPoint(i)
	local p = rawget(self, "__points")[i or 1]
	if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Region:GetNumPoints() return #rawget(self, "__points") end
function Region:SetSize(w, h) rawset(self, "__width", w); rawset(self, "__height", h) end
function Region:GetSize() return rawget(self, "__width"), rawget(self, "__height") end
function Region:SetWidth(w) rawset(self, "__width", w) end
function Region:SetHeight(h) rawset(self, "__height", h) end
function Region:GetWidth() return rawget(self, "__width") end
function Region:GetHeight() return rawget(self, "__height") end
function Region:GetLeft() return 500 end
function Region:GetRight() return 500 + rawget(self, "__width") end
function Region:GetTop() return 500 end
function Region:GetBottom() return 500 - rawget(self, "__height") end
function Region:GetCenter() return 550, 480 end
function Region:SetClampedToScreen(v) rawset(self, "__clamped", v) end
function Region:SetMovable(v) rawset(self, "__movable", v) end
function Region:IsMovable() return rawget(self, "__movable") end
function Region:StartMoving() rawset(self, "__moving", true) end
function Region:StopMovingOrSizing() rawset(self, "__moving", false) end
function Region:EnableMouse(v) rawset(self, "__mouse", v) end
function Region:EnableKeyboard(v) rawset(self, "__keyboard", v) end
function Region:SetFrameStrata(s) rawset(self, "__strata", s) end
function Region:SetFrameLevel(l) rawset(self, "__level", l) end
function Region:SetDontSavePosition() end
function Region:RegisterForDrag() end
function Region:RegisterForClicks() end
function Region:SetPropagateMouseMotion() end
function Region:SetPropagateKeyboardInput() end
function Region:SetAttribute(k, v) rawget(self, "__attrs")[k] = v end
function Region:GetAttribute(k) return rawget(self, "__attrs")[k] end
function Region:RegisterEvent(e) rawget(self, "__events")[e] = true end
-- Like the client, only for unit tokens on its fixed list (VALID_UNIT_EVENT_TOKENS).
VALID_UNIT_EVENT_TOKENS = { player = true, pet = true, target = true, focus = true, pettarget = true }
function Region:RegisterUnitEvent(e, ...)
	for i = 1, select("#", ...) do
		local unit = select(i, ...)
		if not VALID_UNIT_EVENT_TOKENS[unit] then error("RegisterUnitEvent: invalid unit " .. tostring(unit), 2) end
	end
	rawget(self, "__events")[e] = true
end
function Region:UnregisterAllEvents() rawset(self, "__events", {}) end
function Region:UnregisterEvent(e) rawget(self, "__events")[e] = nil end
function Region:Raise() end
function Region:Layout() end
function Region:MarkDirty() end
function Region:GetChildren() return unpack(rawget(self, "__children")) end
-- textures / fontstrings
function Region:SetText(t) rawset(self, "__text", t) end
function Region:GetText() return rawget(self, "__text") end
function Region:SetFontObject() end
function Region:SetTextColor() end
function Region:SetJustifyH() end
function Region:SetJustifyV() end
function Region:IsTruncated() return false end
function Region:SetFontObjectsToTry() end
function Region:SetTexture() end
function Region:SetAtlas() end
function Region:SetColorTexture() end
function Region:SetVertexColor() end
function Region:SetTexCoord() end
function Region:SetBlendMode() end
function Region:AddMaskTexture() end
function Region:SetNormalAtlas() end
function Region:SetPushedAtlas() end
function Region:SetHighlightAtlas() end
function Region:SetDrawEdge() end
function Region:Clear() end
function Region:SetCooldownFromDurationObject() end
-- statusbars
function Region:GetStatusBarTexture() return rawget(self, "__bartex") end
function Region:SetStatusBarTexture() end
function Region:SetStatusBarColor() end
function Region:SetMinMaxValues(a, b) rawset(self, "__min", a); rawset(self, "__max", b) end
function Region:GetMinMaxValues() return rawget(self, "__min") or 0, rawget(self, "__max") or 1 end
function Region:SetValue(v) rawset(self, "__value", v) end
function Region:GetValue() return rawget(self, "__value") or 0 end
-- buttons
function Region:SetChecked(v) rawset(self, "__checked", not not v) end
function Region:GetChecked() return rawget(self, "__checked") or false end
function Region:SetEnabled(v) rawset(self, "__enabled", not not v) end
function Region:IsEnabled() local e = rawget(self, "__enabled"); return e == nil or e end
function Region:Enable() self:SetEnabled(true) end
function Region:Disable() self:SetEnabled(false) end
function Region:Click(button)
	if not self:IsEnabled() or not self:IsVisible() then return "not clickable" end
	if rawget(self, "__kind") == "CheckButton" then self:SetChecked(not self:GetChecked()) end
	FireScript(self, "OnClick", button or "LeftButton", false)
end
function Region:SetOnClickHandler(h) rawset(self, "__onclick", h); self:SetScript("OnClick", function(b) h(b) end) end
-- edit boxes
function Region:SetAutoFocus() end
function Region:ClearFocus() end
function Region:HighlightText() end
function Region:SetCursorPosition() end

function Region:CreateTexture(name, layer, template) local t = NewRegion("Texture", name, self); return t end
function Region:CreateFontString(name, layer, template) local t = NewRegion("FontString", name, self); return t end
function Region:CreateMaskTexture(name) return NewRegion("MaskTexture", name, self) end

---------------------------------------------------------------------------------------------------
-- Templates
---------------------------------------------------------------------------------------------------
TEMPLATES = {}

local function ApplyTemplate(f, template)
	for name in string.gmatch(template, "[^,%s]+") do
		local t = TEMPLATES[name]
		if not t then error("unknown template " .. name) end
		t(f)
	end
end

function CreateFrame(kind, name, parent, template)
	local f = NewRegion(kind, name, parent)
	rawset(f, "__template", template)
	if template then ApplyTemplate(f, template) end
	local onload = rawget(f, "__onload")
	if onload then
		for _, fn in ipairs(onload) do fn(f) end
	end
	return f
end

local function AddOnLoad(f, fn)
	local l = rawget(f, "__onload") or {}
	table.insert(l, fn)
	rawset(f, "__onload", l)
end

TEMPLATES.SecureUnitButtonTemplate = function(f) rawset(f, "__protected", true) end
TEMPLATES.PingableUnitFrameTemplate = function(f) end
TEMPLATES.SimplePetTargetDebuffTemplate = function(f)
	rawset(f, "__shown", false)
	f.Icon = f:CreateTexture()
	f.Border = f:CreateTexture()
	f.Cooldown = CreateFrame("Cooldown", nil, f)
	rawset(f.Cooldown, "__shown", false)
end
TEMPLATES.SimplePetTargetFrameTemplate = function(f)
	TEMPLATES.SecureUnitButtonTemplate(f)
	rawset(f, "__shown", false)
	f:SetSize(120, 49)
	f.Portrait = f:CreateTexture()
	f.PortraitRed = f:CreateTexture()
	f.Name = f:CreateFontString()
	local function bar(key, h)
		local b = CreateFrame("StatusBar", nil, f)
		b:SetSize(70, h)
		rawset(b, "__bartex", b:CreateTexture())
		b.TextString = b:CreateFontString(); rawset(b.TextString, "__shown", false)
		b.LeftText = b:CreateFontString(); rawset(b.LeftText, "__shown", false)
		b.RightText = b:CreateFontString(); rawset(b.RightText, "__shown", false)
		f[key] = b
		return b
	end
	local hb = bar("HealthBar", 11)
	hb.DeadText = hb:CreateFontString(); rawset(hb.DeadText, "__shown", false)
	hb.UnconsciousText = hb:CreateFontString(); rawset(hb.UnconsciousText, "__shown", false)
	hb.HealthBarMask = hb:CreateMaskTexture()
	local mb = bar("ManaBar", 7)
	mb.Spark = mb:CreateTexture(); rawset(mb.Spark, "__shown", false)
	mb.ManaBarMask = mb:CreateMaskTexture()
end
function Region:SetID(i) rawset(self, "__id", i) end
function Region:GetID() return rawget(self, "__id") end

TEMPLATES.ResizeLayoutFrame = function(f) end
TEMPLATES.VerticalLayoutFrame = function(f) end
TEMPLATES.DialogBorderTranslucentTemplate = function(f) end
TEMPLATES.UIPanelCloseButton = function(f)
	f:SetScript("OnClick", MarkSecure(function(self) self:GetParent():Hide() end))
end
TEMPLATES.EditModeSystemSettingsDialogButtonTemplate = function(f) end
TEMPLATES.EditModeSystemSettingsDialogExtraButtonTemplate = function(f) end
TEMPLATES.InputBoxTemplate = function(f) end

-- Blizzard selection mixins (EditModeSystemTemplates.lua)
local NineSliceUtil = { ApplyLayout = function() end }
_G.NineSliceUtil = NineSliceUtil
GameTooltip = NewRegion("GameTooltip", "GameTooltip", nil)
rawset(GameTooltip, "__shown", false)
function GameTooltip:SetOwner(o) rawset(self, "__owner", o) end
function GameTooltip:GetOwner() return rawget(self, "__owner") end
function GameTooltip:AddLine() end
function GameTooltip:SetUnitDebuff() end
SettingsTooltip = GameTooltip
function GetAppropriateTooltip() return GameTooltip end
function GameTooltip_AddNormalLine() end
function GameTooltip_AddHighlightLine() end
function GameTooltip_AddBlankLineToTooltip() end
function GameTooltip_AddInstructionLine() end
DefaultTooltipMixin = { OnLeave = function() GameTooltip:Hide() end }

EditModeSystemSelectionBaseMixin = {}
function EditModeSystemSelectionBaseMixin:OnLoad()
	self.parent = self:GetParent()
end
function EditModeSystemSelectionBaseMixin:SetSystem(system) self.system = system end
function EditModeSystemSelectionBaseMixin:ShowHighlighted()
	if self.textureShown ~= "highlight" then
		NineSliceUtil.ApplyLayout(self)
		self.textureShown = "highlight"
	end
	self.isSelected = false
	self:UpdateLabelVisibility()
	self:Show()
end
function EditModeSystemSelectionBaseMixin:ShowSelected()
	if self.textureShown ~= "selected" then
		NineSliceUtil.ApplyLayout(self)
		self.textureShown = "selected"
	end
	self.isSelected = true
	self:UpdateLabelVisibility()
	self:CheckShowInstructionalTooltip()
	self:Show()
end
function EditModeSystemSelectionBaseMixin:IsSelected() return self.isSelected end
function EditModeSystemSelectionBaseMixin:ShouldShowLabelText() return self:IsSelected() or self:IsShowingEditInstructions() end
function EditModeSystemSelectionBaseMixin:OnEnter() self:ShowEditInstructions(true); self:CheckShowInstructionalTooltip() end
function EditModeSystemSelectionBaseMixin:OnLeave() self:ShowEditInstructions(false); self:HideInstructionalTooltip() end
function EditModeSystemSelectionBaseMixin:ShowEditInstructions(shown) self.instructionsShown = shown; self.MouseOverHighlight:SetShown(shown); self:UpdateLabelVisibility() end
function EditModeSystemSelectionBaseMixin:IsShowingEditInstructions() return self.instructionsShown end
function EditModeSystemSelectionBaseMixin:CheckShowInstructionalTooltip()
	if not self:IsSelected() then GameTooltip:SetOwner(self); GameTooltip:Show() else self:HideInstructionalTooltip() end
end
function EditModeSystemSelectionBaseMixin:HideInstructionalTooltip() GameTooltip:Hide() end
function EditModeSystemSelectionBaseMixin:GetLabelText()
	if self:IsSelected() then return self.system:GetSystemName() end
	return HUD_EDIT_MODE_INSTRUCTIONS_CLICK_TO_EDIT
end
EditModeSystemSelectionMixin = CreateFromMixins(EditModeSystemSelectionBaseMixin)
function EditModeSystemSelectionMixin:UpdateLabelVisibility()
	self.Label:SetText(self:GetLabelText())
	self.Label:SetShown(self:ShouldShowLabelText())
end

TEMPLATES.EditModeSystemSelectionTemplate = function(f)
	Mixin(f, EditModeSystemSelectionMixin)
	f.MouseOverHighlight = CreateFrame("Frame", nil, f)
	rawset(f.MouseOverHighlight, "__shown", false)
	f.Label = f:CreateFontString()
	rawset(f.Label, "__shown", false)
	f:SetScript("OnMouseDown", MarkSecure(function(self) end))
	f:SetScript("OnEnter", MarkSecure(function(self) self:OnEnter() end))
	f:SetScript("OnLeave", MarkSecure(function(self) self:OnLeave() end))
	AddOnLoad(f, function(self) self:OnLoad() end)
end

-- Blizzard check button mixins (SharedUIPanelTemplates.lua, EditModeTemplates.lua)
ResizeCheckButtonMixin = {}
function ResizeCheckButtonMixin:OnLoad()
	self.onBoxToggled = self.onBoxToggled or nop
	if self.Label ~= nil then self.Label:SetText(self.labelText) end
end
function ResizeCheckButtonMixin:OnShow() end
function ResizeCheckButtonMixin:OnCheckButtonClick()
	local isUserInput = true
	self.onBoxToggled(self:IsControlChecked(), isUserInput)
end
function ResizeCheckButtonMixin:SetLabelText(labelText)
	self.labelText = labelText
	if self.Label ~= nil then self.Label:SetText(labelText); self:MarkDirty() end
end
function ResizeCheckButtonMixin:SetCallback(onBoxToggled) self.onBoxToggled = onBoxToggled end
function ResizeCheckButtonMixin:SetControlChecked(checked, isUserInput)
	if self:IsControlChecked() == checked then return end
	if self.Button == nil then return end
	self.Button:SetChecked(checked)
	self.onBoxToggled(self:IsControlChecked(), not not isUserInput)
end
function ResizeCheckButtonMixin:IsControlChecked()
	if self.Button == nil then return false end
	return self.Button:GetChecked()
end

EditModeCheckButtonMixin = {}
function EditModeCheckButtonMixin:EditModeCheckButton_OnLoad()
	self.Button:SetScript("OnClick", function() self:OnCheckButtonClick() end)
	self.Button:SetScript("OnEnter", function() self:OnEnter() end)
	self.Button:SetScript("OnLeave", function() self:OnLeave() end)
end
function EditModeCheckButtonMixin:EditModeCheckButton_OnShow() self:UpdateDisplay() end
function EditModeCheckButtonMixin:OnEnter()
	local showDisabledTooltip = not self:ShouldEnable() and self.disabledTooltipText
	if showDisabledTooltip then
		GameTooltip:SetOwner(self.Button)
		rawset(GameTooltip, "__lastText", self.disabledTooltipText)
		GameTooltip:Show()
	end
end
function EditModeCheckButtonMixin:OnLeave() if GameTooltip:GetOwner() == self.Button then GameTooltip:Hide() end end
function EditModeCheckButtonMixin:UpdateDisplay()
	local shouldEnable = self:ShouldEnable()
	self.Button:SetEnabled(shouldEnable)
	rawset(self, "__labelEnabled", shouldEnable)
end
function EditModeCheckButtonMixin:ShouldEnable() return true end
EditModeManagerSettingCheckButtonMixin = {}
function EditModeManagerSettingCheckButtonMixin:EditModeManagerSettingCheckButton_OnLoad() end

TEMPLATES.EditModeManagerSettingCheckButtonTemplate = function(f)
	Mixin(f, ResizeCheckButtonMixin, EditModeCheckButtonMixin, EditModeManagerSettingCheckButtonMixin)
	f:SetSize(225, 32)
	f.Button = CreateFrame("CheckButton", nil, f)
	f.Label = f:CreateFontString()
	AddOnLoad(f, function(self) self:OnLoad(); self:EditModeCheckButton_OnLoad(); self:EditModeManagerSettingCheckButton_OnLoad() end)
	f:SetScript("OnShow", function(self) self:OnShow(); self:EditModeCheckButton_OnShow() end)
end

-- LibEditMode widget templates
TEMPLATES.EditModeSettingCheckboxTemplate = function(f)
	rawset(f, "__shown", false)
	f.Button = CreateFrame("CheckButton", nil, f)
	f.Button:SetScript("OnClick", function(self) self:GetParent():OnCheckButtonClick() end)
	f.Label = f:CreateFontString()
end
MinimalSliderWithSteppersMixin = { Label = { Right = 2 }, Event = {} }
function CreateMinimalSliderFormatter() return function(v) return v end end
TEMPLATES.EditModeSettingSliderTemplate = function(f)
	rawset(f, "__shown", false)
	f.Label = f:CreateFontString()
	f.Slider = CreateFrame("Frame", nil, f)
	f.Slider.MinText = f.Slider:CreateFontString()
	f.Slider.MaxText = f.Slider:CreateFontString()
	f.Slider.RightText = f.Slider:CreateFontString()
	f.Slider.Slider = CreateFrame("Slider", nil, f.Slider)
	function f.Slider:Init(value, minV, maxV) rawset(self, "__value", value); self.Slider:SetMinMaxValues(minV, maxV); self.Slider:SetValue(value) end
	function f.Slider:SetValue(v) rawset(self, "__value", v); self.Slider:SetValue(v); f:OnSliderValueChanged(v) end
	f.OnLoad = function() end
end

-- Object pools
function CreateUnsecuredObjectPool(creationFunc, resetterFunc)
	local pool = { creationFunc = creationFunc, resetterFunc = resetterFunc, active = {}, inactive = {} }
	function pool:Acquire()
		local obj = table.remove(self.inactive)
		local new = false
		if not obj then obj = self.creationFunc(self); new = true end
		self.active[obj] = true
		return obj, new
	end
	function pool:ReleaseAll()
		for obj in pairs(self.active) do
			if self.resetterFunc then self.resetterFunc(self, obj) end
			table.insert(self.inactive, obj)
		end
		self.active = {}
	end
	return pool
end

---------------------------------------------------------------------------------------------------
-- UIParent, events, EventRegistry
---------------------------------------------------------------------------------------------------
UIParent = NewRegion("Frame", "UIParent", nil)
UIParent:SetSize(1920, 1080)
function GetScreenWidth() return 1920 end

function DispatchEvent(event, ...)
	local snapshot = {}
	for _, f in ipairs(ALL_FRAMES) do snapshot[#snapshot + 1] = f end
	for _, f in ipairs(snapshot) do
		if rawget(f, "__events")[event] then FireScript(f, "OnEvent", event, ...) end
	end
	EventRegistry:TriggerEvent(event, ...)
end

EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, func, owner)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], { func = func, owner = owner or {} })
end
function EventRegistry:RegisterFrameEventAndCallback(event, func, owner) self:RegisterCallback(event, func, owner) end
function EventRegistry:TriggerEvent(event, ...)
	for _, cb in ipairs(self.callbacks[event] or {}) do
		local args = { n = select("#", ...), ... }
		RunInsecure(function() cb.func(cb.owner, unpack(args, 1, args.n)) end)
	end
end

---------------------------------------------------------------------------------------------------
-- State drivers
---------------------------------------------------------------------------------------------------

local stateDrivers = {}
local function EvalVisibility(cond)
	if cond == "hide" then return false end
	if cond == "show" then return true end
	-- "[@pettarget,noexists][@pet,dead] hide; show"
	if not UnitExists("pettarget") or UnitIsDead("pet") then return false end
	return true
end
function RegisterStateDriver(frame, state, values)
	if IsProtected(frame) and STATE.inCombat and STATE.secureDepth == 0 then
		BLOCKED[#BLOCKED + 1] = "RegisterStateDriver"
		return
	end
	stateDrivers[frame] = values
	RunSecure(function() frame:SetShown(EvalVisibility(values)) end)
end
function UnregisterStateDriver(frame, state)
	if IsProtected(frame) and STATE.inCombat and STATE.secureDepth == 0 then
		BLOCKED[#BLOCKED + 1] = "UnregisterStateDriver"
		return
	end
	stateDrivers[frame] = nil
end
function UpdateStateDrivers()
	for frame, values in pairs(stateDrivers) do
		RunSecure(function() frame:SetShown(EvalVisibility(values)) end)
	end
end
function GetStateDriver(frame) return stateDrivers[frame] end

---------------------------------------------------------------------------------------------------
-- Blizzard Edit Mode stand-in
---------------------------------------------------------------------------------------------------
PlayerFrame = NewRegion("Button", "PlayerFrame", UIParent)
rawset(PlayerFrame, "__protected", true)
PetFrame = NewRegion("Button", "PetFrame", PlayerFrame)
rawset(PetFrame, "__protected", true)
PetFrame:SetSize(120, 49)
rawset(PetFrame, "__shown", false)
PetFrame.isInEditMode = false
PetFrame.Selection = NewRegion("Frame", nil, PetFrame)
rawset(PetFrame.Selection, "__shown", false)
function PetFrame:UpdateShownState()
	RunSecure(function() self:SetShown(self.isInEditMode or UNITS.pet.exists) end)
end

EditModeSystemSettingsDialog = NewRegion("Frame", "EditModeSystemSettingsDialog", UIParent)
rawset(EditModeSystemSettingsDialog, "__shown", false)

-- One other Blizzard system (e.g. an action bar) so selecting a Blizzard system can be simulated.
OtherSystem = NewRegion("Frame", "OtherSystem", UIParent)
OtherSystem.isHighlighted = false

EditModeManagerFrame = NewRegion("Frame", "EditModeManagerFrame", UIParent)
rawset(EditModeManagerFrame, "__shown", false)
local EMF = EditModeManagerFrame
EMF.petFrameChecked = false -- account setting (saved)
EMF.petFrameControlChecked = false -- checkbox state
EMF.selected = nil

local function RefreshPetFrame()
	if EMF.petFrameControlChecked then
		PetFrame.isInEditMode = true
		PetFrame.Selection:Show()
	else
		PetFrame.isInEditMode = false
		if EMF.selected == PetFrame then EMF:ClearSelectedSystem() end
		PetFrame.Selection:Hide()
	end
	PetFrame:UpdateShownState()
end
function EMF:EnterEditMode()
	self.editModeActive = true
	OtherSystem.isHighlighted = true
	-- AccountSettings:OnEditModeEnter -> SetupPetFrame, RefreshPetFrame
	if PetFrame:IsShown() then EMF.petFrameControlChecked = true end
	RefreshPetFrame()
	EventRegistry:TriggerEvent("EditMode.Enter")
end
function EMF:ExitEditMode()
	self.editModeActive = false
	self:ClearSelectedSystem() -- RevertAllChanges
	-- HideSystemSelections
	OtherSystem.isHighlighted = false
	PetFrame.Selection:Hide()
	PetFrame.isInEditMode = false
	PetFrame:UpdateShownState()
	EditModeSystemSettingsDialog:Hide()
	EventRegistry:TriggerEvent("EditMode.Exit")
end
EMF:SetScript("OnShow", MarkSecure(function(self)
	if not self.lockState then
		self:EnterEditMode()
	elseif self.lockState == "hideSelections" then
		OtherSystem.isHighlighted = true
		if PetFrame:IsShown() then EMF.petFrameControlChecked = true end
		RefreshPetFrame()
	end
	self.lockState = nil
end))
EMF:SetScript("OnHide", MarkSecure(function(self)
	if not self.lockState then
		self:ExitEditMode()
	elseif self.lockState == "hideSelections" then
		OtherSystem.isHighlighted = false
		PetFrame.Selection:Hide()
		PetFrame.isInEditMode = false
		PetFrame:UpdateShownState()
		EditModeSystemSettingsDialog:Hide()
	end
end))
function EMF:SelectSystem(frame)
	if self.lockState then return end
	self.selected = frame
	EditModeSystemSettingsDialog:Show()
end
function EMF:ClearSelectedSystem()
	self.selected = nil
	EditModeSystemSettingsDialog:Hide()
end
function EMF:ShowNewLayoutDialog() self:ClearSelectedSystem() end
function EMF:CheckHideAndLockEditMode(lockState)
	if self.editModeActive then
		self:ClearSelectedSystem()
		self.lockState = lockState or "hideSelections"
		self:Hide()
	end
end
function EMF:ShowIfActive() if self.editModeActive then self:Show() return true end return false end
function EMF:SetPetFrameCheckbox(checked)
	-- user click on Blizzard's "Pet Frame" checkbox
	RunSecure(function()
		EMF.petFrameControlChecked = checked
		EMF.petFrameChecked = checked
		RefreshPetFrame()
	end)
end

-- Layouts
LAYOUTS = { activeLayout = 1, layouts = { { layoutName = "Mine", layoutType = 0 } } }
C_EditMode = {}
function C_EditMode.GetLayouts()
	local copy = { activeLayout = LAYOUTS.activeLayout, layouts = {} }
	for i, l in ipairs(LAYOUTS.layouts) do copy.layouts[i] = { layoutName = l.layoutName, layoutType = l.layoutType } end
	return copy
end
function EMF:SelectLayout(index)
	RunSecure(function()
		if index ~= LAYOUTS.activeLayout then
			self:ClearSelectedSystem()
			LAYOUTS.activeLayout = index
			-- InitializeAccountSettings: SetPetFrameShown(saved), programmatic, no refresh
			EMF.petFrameControlChecked = EMF.petFrameChecked
		end
	end)
	EventRegistry:TriggerEvent("EDIT_MODE_LAYOUTS_UPDATED", C_EditMode.GetLayouts())
end

---------------------------------------------------------------------------------------------------
-- Settings stand-in
---------------------------------------------------------------------------------------------------
SETTINGS_REGISTERED = {}
Settings = { VarType = { Boolean = "boolean" } }
function Settings.RegisterVerticalLayoutCategory(name) return { name = name } end
function Settings.RegisterAddOnSetting(category, variable, key, tbl, varType, name, default)
	if tbl[key] == nil then tbl[key] = default end
	local setting = { variable = variable, key = key, tbl = tbl, callbacks = {} }
	function setting:SetValueChangedCallback(cb) table.insert(self.callbacks, cb) end
	function setting:SetValue(v)
		self.tbl[self.key] = v
		for _, cb in ipairs(self.callbacks) do RunInsecure(cb, self, v) end
	end
	function setting:GetValue() return self.tbl[self.key] end
	SETTINGS_REGISTERED[variable] = setting
	return setting
end
function Settings.CreateCheckbox() end
function Settings.RegisterAddOnCategory() end

---------------------------------------------------------------------------------------------------
-- CVars and strings
---------------------------------------------------------------------------------------------------
CVARS = { statusText = "0", statusTextDisplay = "NUMERIC", showDispelDebuffs = "1" }
function GetCVar(name) return CVARS[name] end
function GetCVarBool(name) return CVARS[name] == "1" end
STATUS_TEXT_DISPLAY_MODE = { NUMERIC = "NUMERIC", PERCENT = "PERCENT", BOTH = "BOTH", NONE = "NONE" }
function AbbreviateLargeNumbers(v) return Propagate(tostring(Reveal(v)), v) end
LFG_FOLLOWER_NAME_PREFIX = "%s"
Constants = { CharacterNameSeparatorConsts = { CHARACTERNAME_SURNAME_SEPARATOR = " " } }
function RegionalUniqueNamesEnabled() return false end
C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
NameUtil = { GetUnitFirstName = function(unit) return UNITS[unit] and UNITS[unit].name end }
C_LFGInfo = { IsInLFGFollowerDungeon = function() return false end }
C_PartyInfo = { IsPartyWalkIn = function() return false end }
PowerBarColor = {
	MANA = { atlas = "UI-HUD-UnitFrame-TargetofTarget-PortraitOn-Bar-Mana" },
	RAGE = { atlasElementName = "Rage" },
	ENERGY = { atlasElementName = "Energy", spark = { atlas = "spark", barHeight = 10, xOffset = 1 } },
}

---------------------------------------------------------------------------------------------------
-- Units
---------------------------------------------------------------------------------------------------
-- UNITS[token] describes each unit; tests change these fields and fire the events. A unit that
-- isn't player-controlled has a secret maximum health and power, and in combat its name and power
-- are secret too. Health is always secret, as in the client.
local function NewUnit(fields)
	local u = {
		exists = true, name = "Unit", dead = false, ghost = false, unconscious = false, connected = true,
		isPlayer = false, playerControlled = false, humanPlayer = false, class = "WARRIOR",
		health = 100, maxHealth = 100, powerType = 0, powerToken = "MANA", power = 50, maxPower = 100,
		canAttack = false, canAssist = false,
	}
	for k, v in pairs(fields or {}) do u[k] = v end
	return u
end
_G.NewUnit = NewUnit

UNITS = {
	player = NewUnit({ name = "Me", isPlayer = true, playerControlled = true, humanPlayer = true, class = "HUNTER" }),
	pet = NewUnit({ exists = false, name = "Wolf", playerControlled = true, powerToken = "FOCUS", powerType = 2 }),
	pettarget = NewUnit({ exists = false, name = "Boar", canAttack = true }),
}

local function U(unit)
	local u = UNITS[unit]
	if unit == "pettarget" and not UNITS.pet.exists then return nil end
	if u and u.exists then return u end
end
local function SecretIf(cond, v) if cond then return Secret(v) end return v end
local function MaxSecret(u) return not u.playerControlled end
local function CombatSecret(u) return STATE.inCombat and not u.playerControlled end

function UnitExists(unit) return U(unit) ~= nil end
function UnitIsDead(unit) local u = U(unit) return u and u.dead or false end
function UnitIsGhost(unit) local u = U(unit) return u and u.ghost or false end
function UnitIsUnconscious(unit) local u = U(unit) return u and u.unconscious or false end
function UnitIsConnected(unit) local u = U(unit) return u and u.connected or false end
function UnitIsVisible(unit) return UnitExists(unit) end
function UnitIsPlayer(unit) local u = U(unit) return u and u.isPlayer or false end
function UnitIsHumanPlayer(unit) local u = U(unit) return u and u.humanPlayer or false end
function UnitInPartyIsAI() return false end
function UnitIsUnit(a, b) return U(a) ~= nil and U(a) == U(b) end
function UnitClass(unit) local u = U(unit) if u then return u.class, u.class end end
function UnitCanAttack(_, unit) local u = U(unit) return u and u.canAttack or false end
function UnitCanAssist(_, unit) local u = U(unit) return u and u.canAssist or false end
function UnitName(unit)
	local u = U(unit)
	if not u then return nil end
	return SecretIf(CombatSecret(u), u.name), u.surname
end
function UnitHealth(unit) local u = U(unit) if u then return Secret(u.health) end end
function UnitHealthMax(unit) local u = U(unit) if u then return SecretIf(MaxSecret(u), u.maxHealth) end end
function UnitPower(unit) local u = U(unit) if u then return SecretIf(CombatSecret(u), u.power) end end
function UnitPowerMax(unit) local u = U(unit) if u then return SecretIf(MaxSecret(u), u.maxPower) end end
function UnitPowerType(unit) local u = U(unit) if u then return u.powerType, u.powerToken end end
function UnitHasPowerType(unit, powerType) local u = U(unit) return u ~= nil and u.powerType == powerType end
-- The percentage goes through the curve inside the "client", so the result is secret whenever the
-- values are.
function UnitHealthPercent(unit, _, curve)
	local u = U(unit)
	if not u then return nil end
	local pct = u.maxHealth > 0 and u.health / u.maxHealth or 0
	return Secret(curve and curve:Evaluate(pct) or pct)
end
function UnitPowerPercent(unit, _, _, curve)
	local u = U(unit)
	if not u then return nil end
	local pct = u.maxPower > 0 and u.power / u.maxPower or 0
	local v = curve and curve:Evaluate(pct) or pct
	return SecretIf(CombatSecret(u) or MaxSecret(u), v)
end
function GetClassAtlas(class) return "classicon-" .. tostring(class):lower() end
function SetPortraitTexture(texture, unit) texture:SetTexture("portrait:" .. tostring(unit)) end

---------------------------------------------------------------------------------------------------
-- Auras: Blizzard's secure aura container (CustomAuraContainerTemplate)
---------------------------------------------------------------------------------------------------
AuraContainerSortMethod = { Default = 0, AuraInstanceIDOnly = 1 }
AuraContainerSortDirection = { Normal = 0, Reverse = 1 }
C_Secrets = { ShouldAurasBeSecret = function() return STATE.inCombat end }
SHOW_CASTABLE_DEBUFFS = nil

VIOLATIONS = {}
-- Buttons are locked once the container has set them up: addon code may then only change their
-- tooltip anchor, and only while auras aren't secret.
local function LockedButtonCall(button, name)
	if rawget(button, "__locked") and (name ~= "SetTooltipAnchorPoint" or C_Secrets.ShouldAurasBeSecret()) then
		VIOLATIONS[#VIOLATIONS + 1] = "aura button: " .. name
		return true
	end
end

TEMPLATES.CustomAuraButtonTemplate = function(f)
	rawset(f, "__shown", false)
	rawset(f, "__dispelTextures", {})
	function f:SetIcon(t) if not LockedButtonCall(self, "SetIcon") then rawset(self, "__icon", t) end end
	function f:GetIcon() return rawget(self, "__icon") end
	function f:AddDispelTypeTexture(t, opts)
		if LockedButtonCall(self, "AddDispelTypeTexture") then return end
		assert(opts and opts.style, "AddDispelTypeTexture needs a style")
		table.insert(rawget(self, "__dispelTextures"), { texture = t, options = opts })
	end
	function f:GetDispelTypeTextureCount() return #rawget(self, "__dispelTextures") end
	function f:GetDispelTypeTexture(i) return rawget(self, "__dispelTextures")[i] end
	function f:SetDurationCooldown(c) if not LockedButtonCall(self, "SetDurationCooldown") then rawset(self, "__cooldown", c) end end
	function f:GetDurationCooldown() return rawget(self, "__cooldown") end
	function f:SetTooltipAnchorPoint(anchor)
		if not LockedButtonCall(self, "SetTooltipAnchorPoint") then rawset(self, "__tooltipAnchor", anchor) end
	end
	function f:GetTooltipAnchorPoint() return rawget(self, "__tooltipAnchor") end
end

TEMPLATES.CustomAuraContainerTemplate = function(c)
	rawset(c, "__groups", {})
	rawset(c, "__updates", 0)
	function c:SetUnit(unit) rawset(self, "__unit", unit) end
	function c:GetUnit() return rawget(self, "__unit") end
	function c:SetEditModePreviewEnabled(v) rawset(self, "__preview", v) end
	function c:IsEditModePreviewEnabled() return rawget(self, "__preview") end
	function c:SetFlowLayoutMaximumLineSize(v) rawset(self, "__lineSize", v) end
	function c:AddAuraGroup(key, filter, opts)
		local group = { filter = filter, sortMethod = opts.sortMethod, frames = {}, opts = opts }
		for _ = 1, opts.maxFrameCount do
			local button = CreateFrame("Button", nil, self, "CustomAuraButtonTemplate, " .. table.concat(opts.templateNames, ", "))
			-- Behind a secure call barrier: errors are reported, not passed on.
			RunSecure(opts.initializeFrame, button)
			rawset(button, "__locked", true)
			table.insert(group.frames, button)
		end
		rawget(self, "__groups")[key] = group
	end
	function c:GetAuraGroupFrameCount(key) local g = rawget(self, "__groups")[key] return g and #g.frames or 0 end
	function c:GetAuraGroup(key) return rawget(self, "__groups")[key] end
	function c:GetUpdateCount() return rawget(self, "__updates") end
	function c:SetAuraGroupFilterString(key, filter) rawget(self, "__groups")[key].filter = filter end
	function c:SetAuraGroupSortMethod(key, method, direction)
		local g = rawget(self, "__groups")[key]
		g.sortMethod, g.sortDirection = method, direction
	end
	function c:UpdateAllAuras() rawset(self, "__updates", rawget(self, "__updates") + 1) end
end

-- Addon code calling an aura API while auras are secret is an error in the client.
C_UnitAuras = setmetatable({}, { __index = function(_, name)
	return function()
		if C_Secrets.ShouldAurasBeSecret() then error("C_UnitAuras." .. name .. " called while auras are secret", 2) end
	end
end })
-- AuraUtil builds Edit Mode's sample auras on first use; built from addon code they taint Edit Mode.
AuraUtil = setmetatable({}, { __index = function(_, name)
	return function() VIOLATIONS[#VIOLATIONS + 1] = "AuraUtil." .. name .. " called by addon code" end
end })

function SecureUnitButton_OnLoad(f, unit) rawset(f, "__secureUnit", unit) end
C_Timer = { queue = {} }
function C_Timer.After(_, fn) table.insert(C_Timer.queue, fn) end

---------------------------------------------------------------------------------------------------
-- Driving the game
---------------------------------------------------------------------------------------------------
function Tick(n, elapsed)
	elapsed = elapsed or 0.05
	for _ = 1, (n or 1) do
		STATE.time = STATE.time + elapsed
		local q = C_Timer.queue
		C_Timer.queue = {}
		for _, fn in ipairs(q) do RunInsecure(fn) end
		UpdateStateDrivers()
		local snapshot = {}
		for _, f in ipairs(ALL_FRAMES) do snapshot[#snapshot + 1] = f end
		for _, f in ipairs(snapshot) do
			if rawget(f, "__scripts").OnUpdate and f:IsVisible() then FireScript(f, "OnUpdate", elapsed) end
		end
	end
end

function SetCombat(v)
	if v then
		DispatchEvent("PLAYER_REGEN_DISABLED")
		STATE.inCombat = true
	else
		STATE.inCombat = false
		DispatchEvent("PLAYER_REGEN_ENABLED")
	end
end

function SetPet(exists, dead)
	UNITS.pet.exists = exists
	UNITS.pet.dead = dead or false
	PetFrame:UpdateShownState()
	UpdateStateDrivers()
	DispatchEvent("UNIT_PET", "player")
end

-- The pet targets a unit (a table from NewUnit) or nothing (nil).
function SetPetTarget(unit)
	if unit then
		UNITS.pettarget = unit
	else
		UNITS.pettarget.exists = false
	end
	UpdateStateDrivers()
	DispatchEvent("UNIT_TARGET", "pet")
end

function OpenEditMode() RunSecure(function() EditModeManagerFrame:Show() end) end
function CloseEditMode() RunSecure(function() EditModeManagerFrame:Hide() end) end

function FindFrameByTemplate(template)
	for _, f in ipairs(ALL_FRAMES) do
		if rawget(f, "__template") == template then return f end
	end
end

function Login()
	DispatchEvent("ADDON_LOADED", "SimplePetTarget")
	EventRegistry:TriggerEvent("EDIT_MODE_LAYOUTS_UPDATED", C_EditMode.GetLayouts())
	DispatchEvent("PLAYER_ENTERING_WORLD")
end
