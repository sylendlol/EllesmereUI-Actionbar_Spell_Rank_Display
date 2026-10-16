if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SpellRank \ SpellRank.lua   (standalone add-on)
--
--  Lives in its own folder: no EllesmereUI file is changed. It attaches at run
--  time to the EllesmereUI Action Bars module through the module registry
--  (EllesmereUI._ModuleNS["EllesmereUIActionBars"]); when that module or one of
--  the pieces used here is missing the add-on stays silent instead of erroring.
--
--  Spell Rank text: the rank of the spell on each action button ("R3"), drawn
--  as a small label (default: top left corner). The Max Rank Checker paints
--  the label in another color when the spellbook holds a higher rank of the
--  same spell than the one on the button. Per bar settings
--  (EAB.db.profile.bars[key]):
--    rankEnabled    bool    master switch (off = nothing is built or listened)
--    rankFont       string  "__global" (Action Bars font) or a font name
--    rankFontSize   number  text size
--    rankOutline    string  "default" | "OUTLINE" | "THICKOUTLINE" | "NONE"
--    rankFormat     string  "r" (R3) | "num" (3) | "rank" (Rank 3) | "ratio" (3/5)
--    rankColor      {r,g,b} text color (rank is the max one / not checked)
--    rankAnchor     string  TOPLEFT .. BOTTOMRIGHT (9 points)
--    rankOffsetX/Y  number  offset from the anchor
--    rankBgMode     string  "none" | "custom"
--    rankBgColor    {r,g,b,a} background color (a = opacity)
--    rankBgPad      number  background padding around the text
--    rankCheck      bool    Max Rank Checker on
--    rankWarnColor  {r,g,b} text color of a lower-than-max rank
--    rankWarnBg     bool    lower rank also tints the background (warn color)
--    rankOnlyLow    bool    show only the lower-than-max ranks
--
--  Max ranks come from a scan of the player's spellbook (name -> highest
--  numeric rank), rebuilt after SPELLS_CHANGED / LEARNED_SPELL_IN_TAB.
--  Slots are read with GetAttribute("action"); every API value is checked
--  with issecretvalue before any compare. Refreshes are coalesced.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local ns = EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not (ns and type(ns.EAB) == "table" and type(ns.barButtons) == "table"
        and type(ns.BAR_LOOKUP) == "table"
        and type(ns.EAB.ApplyFontsForBar) == "function") then
    return
end

local _G = _G
local ipairs, pairs, type, tonumber, tostring, pcall = ipairs, pairs, type, tonumber, tostring, pcall
local wipe = wipe or table.wipe
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After
local GetActionInfo = GetActionInfo
local HasAction = HasAction
local GetMacroSpell = GetMacroSpell

local EAB, barButtons, BAR_LOOKUP = ns.EAB, ns.barButtons, ns.BAR_LOOKUP
local FONT_PATH = (type(ns._internals) == "table" and rawget(ns._internals, "FONT_PATH"))
    or (EllesmereUI.MEDIA_PATH and (EllesmereUI.MEDIA_PATH .. "fonts\\Expressway.TTF"))
    or STANDARD_TEXT_FONT

local issecret = _G.issecretvalue or function() return false end

local SR = {}
ns.SpellRank = SR

-------------------------------------------------------------------------------
--  Defaults / helpers
-------------------------------------------------------------------------------
SR.DEFAULTS = {
    rankFont = "__global", rankFontSize = 10, rankOutline = "default",
    rankFormat = "r", rankAnchor = "TOPLEFT", rankOffsetX = 1, rankOffsetY = -1,
    rankBgMode = "none", rankBgPad = 1,
    rankCheck = true, rankWarnBg = false, rankOnlyLow = false,
}
SR.DEFAULT_COLOR = { r = 0.85, g = 0.85, b = 0.85 }
SR.DEFAULT_WARN  = { r = 1.00, g = 0.25, b = 0.20 }
SR.DEFAULT_BG    = { r = 0, g = 0, b = 0, a = 0.7 }
SR.ANCHORS = {
    TOPLEFT = "LEFT", TOP = "CENTER", TOPRIGHT = "RIGHT",
    LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT",
    BOTTOMLEFT = "LEFT", BOTTOM = "CENTER", BOTTOMRIGHT = "RIGHT",
}
-- The keys "Apply to all Bars" copies.
SR.KEYS = { "rankEnabled", "rankFont", "rankFontSize", "rankOutline", "rankFormat",
    "rankColor", "rankAnchor", "rankOffsetX", "rankOffsetY", "rankBgMode",
    "rankBgColor", "rankBgPad", "rankCheck", "rankWarnColor", "rankWarnBg", "rankOnlyLow" }

local function Val(s, key)
    local v = s[key]
    if v == nil then return SR.DEFAULTS[key] end
    return v
end
SR.Val = Val

-- Stance / pet buttons carry no ranked player spells.
local function IsRankBar(barKey)
    local info = BAR_LOOKUP[barKey]
    if not info then return false end
    return not (info.isStance or info.isPetBar)
end
SR.IsRankBar = IsRankBar

local function BarEnabled(barKey)
    local s = EAB.db and EAB.db.profile.bars[barKey]
    return s and s.rankEnabled and IsRankBar(barKey) and barButtons[barKey] ~= nil
end

-------------------------------------------------------------------------------
--  Spell / rank lookup
-------------------------------------------------------------------------------
local GetSubtext = (C_Spell and C_Spell.GetSpellSubtext) or _G.GetSpellSubtext

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, id)
        if ok then return n end
    end
    if _G.GetSpellInfo then
        local ok, n = pcall(_G.GetSpellInfo, id)
        if ok then return n end
    end
    return nil
end

-- Number from a rank subtext ("Rank 3" -> 3); "Racial", "Passive", "" -> nil.
local function RankOf(sub)
    if issecret(sub) or type(sub) ~= "string" or sub == "" then return nil end
    return tonumber(sub:match("(%d+)"))
end

local function SubtextRank(spellID)
    if not GetSubtext or issecret(spellID) or spellID == nil then return nil end
    local ok, sub = pcall(GetSubtext, spellID)
    if not ok then return nil end
    return RankOf(sub)
end

-- spellID of an action slot (spell or macro casting a spell), else nil.
local function SlotSpell(slot)
    if issecret(slot) or slot == nil or not HasAction(slot) then return nil end
    local aType, id, subType = GetActionInfo(slot)
    if issecret(aType) or issecret(id) or aType == nil or id == nil then return nil end
    if aType == "spell" then
        return id
    elseif aType == "macro" then
        if not issecret(subType) and subType == "spell" then return id end
        if not GetMacroSpell then return nil end
        local sid = GetMacroSpell(id)
        if issecret(sid) then return nil end
        return sid
    end
    return nil
end

-- Spellbook scan: spell name -> highest rank known.
local bookMax = {}
local bookDirty = true

local function AddBookSpell(name, sub, spellID)
    if issecret(name) or type(name) ~= "string" or name == "" then return end
    local r = RankOf(sub) or SubtextRank(spellID)
    if not r then return end
    local cur = bookMax[name]
    if not cur or r > cur then bookMax[name] = r end
end

local function ScanModern()
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if not (SB and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo
            and SB.GetSpellBookItemInfo and bank) then
        return false
    end
    local SPELL_T = Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    local n = SB.GetNumSpellBookSkillLines() or 0
    for line = 1, n do
        local li = SB.GetSpellBookSkillLineInfo(line)
        local offSpec = li and li.offSpecID
        if li and not (offSpec and not issecret(offSpec) and offSpec ~= 0) then
            local off, cnt = li.itemIndexOffset or 0, li.numSpellBookItems or 0
            for i = off + 1, off + cnt do
                local info = SB.GetSpellBookItemInfo(i, bank)
                if info and info.spellID and not info.isPassive
                        and (not SPELL_T or info.itemType == SPELL_T) then
                    AddBookSpell(info.name or SpellName(info.spellID), info.subName, info.spellID)
                end
            end
        end
    end
    return true
end

local function ScanLegacy()
    local NumTabs, TabInfo = _G.GetNumSpellTabs, _G.GetSpellTabInfo
    local ItemInfo, ItemName = _G.GetSpellBookItemInfo, _G.GetSpellBookItemName
    if not (NumTabs and TabInfo and ItemInfo and ItemName) then return false end
    local book = _G.BOOKTYPE_SPELL or "spell"
    for tab = 1, NumTabs() do
        local _, _, off, cnt, _, offSpec = TabInfo(tab)
        if off and cnt and (not offSpec or offSpec == 0) then
            for i = off + 1, off + cnt do
                local sType, id = ItemInfo(i, book)
                if sType == "SPELL" and id then
                    local name, sub = ItemName(i, book)
                    AddBookSpell(name, sub, id)
                end
            end
        end
    end
    return true
end

local function EnsureBook()
    if not bookDirty then return end
    bookDirty = false
    wipe(bookMax)
    local ok, done = pcall(ScanModern)
    if not (ok and done) then
        wipe(bookMax)
        pcall(ScanLegacy)
    end
end
function SR.InvalidateBook() bookDirty = true end

-- Highest known rank of a spell name (spellbook scan, then the client's own
-- "spell by name" lookup, which resolves to the highest known rank).
local function MaxRank(name)
    EnsureBook()
    local m = bookMax[name]
    if m then return m end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and info.spellID then
            return SubtextRank(info.spellID)
        end
    elseif _G.GetSpellInfo then
        local ok, _, _, _, _, _, _, sid = pcall(_G.GetSpellInfo, name)
        if ok and sid then return SubtextRank(sid) end
    end
    return nil
end

-- rank, maxRank (maxRank may be nil) of a spellID, or nil.
local function SpellRanks(spellID)
    if spellID == nil then return nil end
    local rank = SubtextRank(spellID)
    if not rank then return nil end
    local name = SpellName(spellID)
    if issecret(name) or type(name) ~= "string" then return rank, nil end
    local maxR = MaxRank(name)
    if maxR and maxR < rank then maxR = rank end
    return rank, maxR
end
SR.SpellRanks = SpellRanks

function SR.FormatRank(rank, maxR, fmt)
    if fmt == "num" then
        return tostring(rank)
    elseif fmt == "rank" then
        return (_G.RANK or "Rank") .. " " .. rank
    elseif fmt == "ratio" then
        return maxR and (rank .. "/" .. maxR) or tostring(rank)
    end
    return "R" .. rank
end

-------------------------------------------------------------------------------
--  Per-button widgets
-------------------------------------------------------------------------------
local widgets = setmetatable({}, { __mode = "k" })  -- btn -> { ov, fs, bg }
local pendingBuild = false

local function GetWidget(btn, create)
    local w = widgets[btn]
    if w or not create then return w end
    if InCombatLockdown() then
        pendingBuild = true
        return nil
    end
    local ov = CreateFrame("Frame", nil, btn)
    ov:SetAllPoints(btn)
    local bg = ov:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0, 0, 0, 0.7)
    local fs = ov:CreateFontString(nil, "OVERLAY")
    fs:SetWordWrap(false)
    w = { ov = ov, fs = fs, bg = bg }
    widgets[btn] = w
    return w
end

local function OverlayLevel(btn)
    local lvl = btn:GetFrameLevel()
    local cd = btn.cooldown
    if cd and cd.GetFrameLevel then lvl = math.max(lvl, cd:GetFrameLevel()) end
    local toc = btn.TextOverlayContainer
    if toc and toc.GetFrameLevel then lvl = math.max(lvl, toc:GetFrameLevel()) end
    return lvl + 1
end

function SR.FontPathFor(s)
    local name = Val(s, "rankFont")
    if name == "__global" or not name then
        return EllesmereUI.GetFontPath("actionBars") or FONT_PATH
    end
    return (EllesmereUI.ResolveFontName and EllesmereUI.ResolveFontName(name)) or FONT_PATH
end

function SR.StyleFont(fs, s, fontPath)
    local size = Val(s, "rankFontSize")
    local outline = Val(s, "rankOutline")
    local flag
    if outline == "NONE" then
        flag = ""
    elseif outline == "OUTLINE" or outline == "THICKOUTLINE" then
        flag = EllesmereUI.SlugFlag and EllesmereUI.SlugFlag(outline .. ", SLUG") or outline
    else
        flag = EllesmereUI.GetIconTextOutlineFlag and EllesmereUI.GetIconTextOutlineFlag("actionBars") or "OUTLINE"
    end
    if EllesmereUI.PrimeFontShadow then EllesmereUI.PrimeFontShadow(fs, flag == "") end
    fs:SetFont(fontPath or SR.FontPathFor(s), size, flag)
end

-- Text + background colors; low = the button holds a lower-than-max rank.
function SR.PaintColors(fs, bg, s, low)
    local warn = s.rankWarnColor or SR.DEFAULT_WARN
    local c = low and warn or (s.rankColor or SR.DEFAULT_COLOR)
    fs:SetTextColor(c.r, c.g, c.b)
    if Val(s, "rankBgMode") == "none" then
        bg:Hide()
        return
    end
    local bc = s.rankBgColor or SR.DEFAULT_BG
    local a = bc.a or 0.7
    if low and Val(s, "rankWarnBg") then
        bg:SetColorTexture(warn.r, warn.g, warn.b, a)
    else
        bg:SetColorTexture(bc.r, bc.g, bc.b, a)
    end
    bg:Show()
end

local function StyleWidget(btn, w, s, fontPath)
    local ov, fs, bg = w.ov, w.fs, w.bg
    if not InCombatLockdown() then ov:SetFrameLevel(OverlayLevel(btn)) end
    SR.StyleFont(fs, s, fontPath)
    local anchor = Val(s, "rankAnchor")
    local justify = SR.ANCHORS[anchor]
    if not justify then anchor, justify = "TOPLEFT", "LEFT" end
    fs:ClearAllPoints()
    fs:SetPoint(anchor, ov, anchor, Val(s, "rankOffsetX"), Val(s, "rankOffsetY"))
    fs:SetJustifyH(justify)
    local pad = Val(s, "rankBgPad")
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", fs, "TOPLEFT", -pad, pad)
    bg:SetPoint("BOTTOMRIGHT", fs, "BOTTOMRIGHT", pad, -pad)
end

local function PaintButton(btn, w, s)
    local rank, maxR = SpellRanks(SlotSpell(btn:GetAttribute("action")))
    local check = Val(s, "rankCheck")
    local low = check and maxR and rank < maxR or false
    if not rank or (check and Val(s, "rankOnlyLow") and not low) then
        w.fs:SetText("")
        w.ov:Hide()
        return
    end
    w.fs:SetText(SR.FormatRank(rank, maxR, Val(s, "rankFormat")))
    SR.PaintColors(w.fs, w.bg, s, low)
    w.ov:Show()
end

-------------------------------------------------------------------------------
--  Bar passes
-------------------------------------------------------------------------------
local hookedButtons = setmetatable({}, { __mode = "k" })
local QueueRefresh  -- forward

local function HookButton(btn)
    if hookedButtons[btn] then return end
    hookedButtons[btn] = true
    btn:HookScript("OnAttributeChanged", function(_, name)
        if name == "action" then QueueRefresh() end
    end)
end

local function HideBar(barKey)
    local buttons = barButtons[barKey]
    if not buttons then return end
    for _, btn in ipairs(buttons) do
        local w = widgets[btn]
        if w then w.fs:SetText(""); w.ov:Hide() end
    end
end

function SR.ApplyBar(barKey)
    if not EAB.db then return end
    if not BarEnabled(barKey) then
        HideBar(barKey)
        SR.UpdateListening()
        return
    end
    local s = EAB.db.profile.bars[barKey]
    local fontPath = SR.FontPathFor(s)
    for _, btn in ipairs(barButtons[barKey]) do
        local w = GetWidget(btn, true)
        if w then
            HookButton(btn)
            StyleWidget(btn, w, s, fontPath)
            PaintButton(btn, w, s)
        end
    end
    SR.UpdateListening()
end

function SR.ApplyAll()
    if not EAB.db then return end
    for barKey in pairs(barButtons) do SR.ApplyBar(barKey) end
end

local function RefreshAll()
    if not EAB.db then return end
    for barKey, buttons in pairs(barButtons) do
        if BarEnabled(barKey) then
            local s = EAB.db.profile.bars[barKey]
            for _, btn in ipairs(buttons) do
                local w = widgets[btn]
                if w then
                    PaintButton(btn, w, s)
                else
                    pendingBuild = true
                end
            end
        end
    end
    if pendingBuild and not InCombatLockdown() then
        pendingBuild = false
        SR.ApplyAll()
    end
end
SR.RefreshAll = RefreshAll

local queued = false
QueueRefresh = function()
    if queued then return end
    queued = true
    C_Timer_After(0.1, function()
        queued = false
        RefreshAll()
    end)
end
SR.QueueRefresh = QueueRefresh

-------------------------------------------------------------------------------
--  Events (registered only while at least one bar shows ranks)
-------------------------------------------------------------------------------
local BOOK_EVENTS = {
    SPELLS_CHANGED = true, LEARNED_SPELL_IN_TAB = true, PLAYER_LEVEL_UP = true,
    PLAYER_TALENT_UPDATE = true, CHARACTER_POINTS_CHANGED = true,
    PLAYER_ENTERING_WORLD = true,
}
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
    "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_SHAPESHIFT_FORMS",
    "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR", "SPELLS_CHANGED",
    "LEARNED_SPELL_IN_TAB", "PLAYER_LEVEL_UP", "UPDATE_MACROS",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED",
}
local ev = CreateFrame("Frame")
local listening = false

ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingBuild then
            pendingBuild = false
            SR.ApplyAll()
        end
        return
    end
    if BOOK_EVENTS[event] then bookDirty = true end
    QueueRefresh()
end)

function SR.UpdateListening()
    local want = false
    if EAB.db then
        for barKey in pairs(barButtons) do
            if BarEnabled(barKey) then want = true; break end
        end
    end
    if want == listening then return end
    listening = want
    if want then
        bookDirty = true
        for _, e in ipairs(EVENTS) do pcall(ev.RegisterEvent, ev, e) end
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
    else
        ev:UnregisterAllEvents()
    end
end

-------------------------------------------------------------------------------
--  /spellrank : list the action slots that hold a lower-than-max rank
-------------------------------------------------------------------------------
SLASH_EUISPELLRANK1 = "/spellrank"
SlashCmdList.EUISPELLRANK = function()
    bookDirty = true
    local seen, n = {}, 0
    local tag = "|cff0cd29fSpell Rank|r: "
    for slot = 1, 180 do
        local id = SlotSpell(slot)
        if id and not seen[id] then
            local rank, maxR = SpellRanks(id)
            if rank and maxR and rank < maxR then
                seen[id] = true
                n = n + 1
                print(tag .. (SpellName(id) or "?") .. "  " .. rank .. " -> " .. maxR
                    .. "  (slot " .. slot .. ")")
            end
        end
    end
    if n == 0 then print(tag .. "every spell on your bars is the highest rank you know.") end
end

-------------------------------------------------------------------------------
--  Hooks into the module's own apply paths
-------------------------------------------------------------------------------
hooksecurefunc(EAB, "ApplyFontsForBar", function(_, barKey)
    if barKey and barButtons[barKey] then SR.ApplyBar(barKey) end
end)

local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_ENTERING_WORLD")
init:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer_After(0.5, function() bookDirty = true; SR.ApplyAll() end)
end)
