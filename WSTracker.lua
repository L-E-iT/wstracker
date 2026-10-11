-- WSTracker: centered, resizable Weakened Soul icon on party/raid frames.
local WS_ID = 6788
local WS_NAME = GetSpellInfo and GetSpellInfo(WS_ID) or (C_Spell and C_Spell.GetSpellName(WS_ID)) or "Weakened Soul"
local WS_ICON = GetSpellTexture and GetSpellTexture(WS_ID) or (C_Spell and C_Spell.GetSpellTexture(WS_ID))

local defaults = { enabled = true, raid = true, party = true, size = 22 }
local db
local overlays = {}
local frames = {}

-- Some aura values are "secret" (unreadable by addons, mostly in combat).
-- Treat them as unknown instead of erroring.
local issecret = issecretvalue or function() return false end
local function Safe(v)
    if issecret(v) then return nil end
    return v
end

local GetDebuff = (C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex) and function(unit, i)
    return C_UnitAuras.GetDebuffDataByIndex(unit, i)
end or function(unit, i)
    local name, icon, _, _, duration, expires, _, _, _, spellId = UnitDebuff(unit, i)
    if name then return { name = name, icon = icon, duration = duration, expirationTime = expires, spellId = spellId } end
end

local GetByInstance = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local lastWS = {}  -- [unit] = auraInstanceID of the last Weakened Soul we identified

-- Returns icon, duration, expires if the unit has Weakened Soul.
local function FindWS(unit)
    for i = 1, 40 do
        local a = GetDebuff(unit, i)
        if not a then break end
        local id, name = Safe(a.spellId), Safe(a.name)
        if id == WS_ID or (name ~= nil and name == WS_NAME) then
            lastWS[unit] = Safe(a.auraInstanceID)
            return Safe(a.icon) or WS_ICON, Safe(a.duration), Safe(a.expirationTime)
        end
    end
    -- Values hidden (e.g. in combat): fall back to the Weakened Soul we saw earlier, if it's still on.
    local inst = lastWS[unit]
    if inst and GetByInstance then
        local a = GetByInstance(unit, inst)
        if a then return WS_ICON, Safe(a.duration), Safe(a.expirationTime) end
    end
    lastWS[unit] = nil
end

local function Active()
    if not db or not db.enabled then return false end
    if IsInRaid() then return db.raid end
    return IsInGroup() and db.party
end

local function GetOverlay(parent)
    local o = overlays[parent]
    if not o then
        o = CreateFrame("Frame", nil, parent)
        o:SetPoint("CENTER")
        o.bg = o:CreateTexture(nil, "BACKGROUND")
        o.bg:SetPoint("TOPLEFT", -1, 1)
        o.bg:SetPoint("BOTTOMRIGHT", 1, -1)
        o.bg:SetColorTexture(0, 0, 0, 1)
        o.icon = o:CreateTexture(nil, "ARTWORK")
        o.icon:SetAllPoints()
        o.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        o.cd = CreateFrame("Cooldown", nil, o, "CooldownFrameTemplate")
        o.cd:SetAllPoints()
        o.cd:SetDrawEdge(false)
        overlays[parent] = o
    end
    o:SetFrameLevel(parent:GetFrameLevel() + 10)
    o:SetSize(db.size, db.size)
    return o
end

local function UnitOf(frame)
    return frame.displayedUnit or frame.unit
end

local function UpdateFrame(frame)
    local unit = UnitOf(frame)
    local icon, duration, expires
    if Active() and unit and frame:IsVisible() and UnitExists(unit) then
        icon, duration, expires = FindWS(unit)
    end
    if not icon then
        if overlays[frame] then overlays[frame]:Hide() end
        return
    end
    local o = GetOverlay(frame)
    o.icon:SetTexture(icon)
    if duration and duration > 0 and expires then
        o.cd:SetCooldown(expires - duration, duration)
    else
        o.cd:Clear()
    end
    o:Show()
end

-- Collect every default party/raid frame that currently exists.
local function AddFrame(f)
    if f and not f:IsForbidden() then frames[#frames + 1] = f end
end

local function RefreshAll()
    wipe(frames)
    for i = 1, 5 do AddFrame(_G["CompactPartyFrameMember" .. i]) end
    for i = 1, 40 do AddFrame(_G["CompactRaidFrame" .. i]) end
    for g = 1, 8 do
        for i = 1, 5 do AddFrame(_G["CompactRaidGroup" .. g .. "Member" .. i]) end
    end
    if PartyFrame then  -- non raid-style party frames
        for i = 1, 4 do AddFrame(PartyFrame["MemberFrame" .. i]) end
    end
    for _, f in ipairs(frames) do UpdateFrame(f) end
end

local function UpdateUnit(unit)
    for _, f in ipairs(frames) do
        local fu = UnitOf(f)
        if fu and (fu == unit or Safe(UnitIsUnit(fu, unit))) then UpdateFrame(f) end
    end
end

local pending
local function QueueRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function() pending = false; RefreshAll() end)
end

-- Config window ---------------------------------------------------------
local config
local function CreateConfig()
    local f = CreateFrame("Frame", "WSTrackerConfig", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(200, 140)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "WSTrackerConfig")

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5)
    title:SetText("WSTracker")

    local function Check(label, key, x, y)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", x, y)
        local t = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        t:SetText(label)
        cb:SetScript("OnClick", function(self) db[key] = self:GetChecked() and true or false; RefreshAll() end)
        cb.key = key
        return cb
    end
    f.checks = {
        Check("Enabled", "enabled", 12, -28),
        Check("Raids", "raid", 12, -52),
        Check("Parties", "party", 100, -52),
    }

    local s = CreateFrame("Slider", "WSTrackerSizeSlider", f, "OptionsSliderTemplate")
    s:SetPoint("TOP", 0, -100)
    s:SetWidth(160)
    s:SetMinMaxValues(12, 48)
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    WSTrackerSizeSliderLow:SetText("12")
    WSTrackerSizeSliderHigh:SetText("48")
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        WSTrackerSizeSliderText:SetText("Icon Size: " .. v)
        if db.size ~= v then
            db.size = v
            for _, o in pairs(overlays) do o:SetSize(v, v) end
        end
    end)
    f.slider = s

    f:SetScript("OnShow", function(self)
        for _, cb in ipairs(self.checks) do cb:SetChecked(db[cb.key]) end
        self.slider:SetValue(db.size)
        WSTrackerSizeSliderText:SetText("Icon Size: " .. db.size)
    end)
    f:Hide()
    return f
end

SLASH_WSTRACKER1 = "/wst"
SLASH_WSTRACKER2 = "/wstracker"
SlashCmdList.WSTRACKER = function()
    config = config or CreateConfig()
    config:SetShown(not config:IsShown())
end

-- Events ---------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("UNIT_AURA")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" then
        if db then UpdateUnit(arg1) end
    elseif event == "ADDON_LOADED" then
        if arg1 == "WSTracker" then
            WSTrackerDB = WSTrackerDB or {}
            for k, v in pairs(defaults) do
                if WSTrackerDB[k] == nil then WSTrackerDB[k] = v end
            end
            db = WSTrackerDB
        end
    else
        if event == "GROUP_ROSTER_UPDATE" then wipe(lastWS) end
        QueueRefresh()
    end
end)
