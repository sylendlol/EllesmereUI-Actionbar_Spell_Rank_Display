if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  EllesmereUI_SpellRank \ SpellRank_Options.lua   (standalone add-on)
--  "Spell Rank" rows in the EXTRAS section at the bottom of every Action Bars
--  > Bar Display tab. Every setting is per bar; the sync icon on the master
--  row copies the whole set to other bars. Runtime: SpellRank.lua.
--
--  EXTRAS is shared with other extras add-ons (EllesmereUI_SpellCost) through
--  ns._EUIExtras: one wrap of ns.ABO_BuildBarAppearance, one EXTRAS header,
--  each add-on's rows appended in order. Each add-on works without the other.
-------------------------------------------------------------------------------
local EllesmereUI = _G.EllesmereUI
local ns = EllesmereUI and EllesmereUI._ModuleNS and EllesmereUI._ModuleNS["EllesmereUIActionBars"]
if not (ns and ns.SpellRank) then return end

-------------------------------------------------------------------------------
--  Shared EXTRAS host (same block in every EllesmereUI extras add-on; the
--  first one loaded creates it, the others reuse it).
-------------------------------------------------------------------------------
local X = ns._EUIExtras
if not X then
    X = { builders = {} }
    ns._EUIExtras = X
end
if not X.Install then
    local function Pack(...) return { n = select("#", ...), ... } end
    function X.Register(id, order, fn)
        X.builders[id] = { order = order, fn = fn }
    end
    -- The EXTRAS header, once per page build (first section that shows).
    function X.Header(parent, y, W)
        if X.headerDone then return y end
        X.headerDone = true
        local _, h = W:SectionHeader(parent, "EXTRAS", y)
        return y - h
    end
    function X.Install()
        if X.hooked then return true end
        local orig = ns.ABO_BuildBarAppearance
        if type(orig) ~= "function" then return false end
        X.hooked = true
        ns.ABO_BuildBarAppearance = function(parent, y, ctx, ...)
            local r = Pack(orig(parent, y, ctx, ...))
            -- r[1] is the page's running y; the rest passes through. A
            -- failing section must never break the page.
            if type(r[1]) == "number" then
                X.headerDone = false
                local list = {}
                for _, b in pairs(X.builders) do list[#list + 1] = b end
                table.sort(list, function(a, b) return a.order < b.order end)
                for _, b in ipairs(list) do
                    local ok, newY = pcall(b.fn, parent, r[1], ctx)
                    if ok and type(newY) == "number" then
                        r[1] = newY
                    elseif not ok then
                        geterrorhandler()(newY)
                    end
                end
            end
            return unpack(r, 1, r.n)
        end
        return true
    end
end

-------------------------------------------------------------------------------
--  Spell Rank rows
-------------------------------------------------------------------------------
local ANCHOR_LABELS = {
    TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right",
    LEFT = "Left", CENTER = "Center", RIGHT = "Right",
    BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom Right",
}
local ANCHOR_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

local FORMAT_LABELS = { r = "R3", num = "3", rank = "Rank 3", ratio = "3/5 (rank / max)" }
local FORMAT_ORDER  = { "r", "num", "rank", "ratio" }

local BG_MODE_LABELS = { none = "None", custom = "Custom Color" }
local BG_MODE_ORDER  = { "none", "custom" }

local OUTLINE_LABELS = { default = "Action Bars Default", OUTLINE = "Outline",
    THICKOUTLINE = "Thick Outline", NONE = "None (Shadow)" }
local OUTLINE_ORDER  = { "default", "OUTLINE", "THICKOUTLINE", "NONE" }

local function CopyValue(v)
    if type(v) == "table" then
        return { r = v.r, g = v.g, b = v.b, a = v.a }
    end
    return v
end

local function BuildSpellRank(parent, y, ctx)
    local env = ns._ABO_OptEnv
    local SR = ns.SpellRank
    if not (SR and env and env.EAB and env.SB and env.SelectedKey and ctx and ctx.W) then return y end
    local EAB, GROUP_BAR_ORDER, PP = env.EAB, env.GROUP_BAR_ORDER, env.PP
    local SB, SelectedKey, SHORT_LABELS = env.SB, env.SelectedKey, env.SHORT_LABELS
    local W = ctx.W
    local _, h

    if not SR.IsRankBar(SelectedKey()) then return y end

    local D = SR.DEFAULTS
    local function Get(key)
        local v = SB()[key]
        if v == nil then return D[key] end
        return v
    end
    local function Apply(k) SR.ApplyBar(k) end
    local function Set(key, v)
        SB()[key] = v
        Apply(SelectedKey())
        EllesmereUI:RefreshPage()
    end
    local function SetColor(key, r, g, b, a)
        Set(key, { r = r, g = g, b = b, a = a })
    end

    local RANK_BARS = {}
    for _, key in ipairs(GROUP_BAR_ORDER) do
        if SR.IsRankBar(key) then RANK_BARS[#RANK_BARS + 1] = key end
    end

    local function CopyTo(key)
        local src, dst = SB(), EAB.db.profile.bars[key]
        if not dst or dst == src then return end
        for _, k in ipairs(SR.KEYS) do dst[k] = CopyValue(src[k]) end
        Apply(key)
    end
    local function Norm(v, k)
        if v == nil then v = D[k] end
        if v == nil then v = false end
        return v
    end
    local function Same(key)
        local src, dst = SB(), EAB.db.profile.bars[key]
        if not dst then return true end
        for _, k in ipairs(SR.KEYS) do
            local a, b = src[k], dst[k]
            if type(a) == "table" or type(b) == "table" then
                a, b = a or {}, b or {}
                if a.r ~= b.r or a.g ~= b.g or a.b ~= b.b or a.a ~= b.a then return false end
            elseif Norm(a, k) ~= Norm(b, k) then
                return false
            end
        end
        return true
    end

    y = X.Header(parent, y, W)

    -------------------------------------------------------------------
    --  Master row: Show Spell Rank | Rank Font
    -------------------------------------------------------------------
    local fontValues, fontOrder = EllesmereUI.BuildFontDropdownData()
    local masterRow
    masterRow, h = W:DualRow(parent, y,
        { type="toggle", text="Show Spell Rank",
          tooltip="Shows the rank of the spell on each button of this bar.",
          getValue=function() return SB().rankEnabled and true or false end,
          setValue=EllesmereUI.SectionToggleSetValue(function(v)
              SB().rankEnabled = v and true or false
              Apply(SelectedKey())
          end) },
        { type="dropdown", text="Rank Font",
          values=fontValues, order=fontOrder,
          disabled=function() return not SB().rankEnabled end,
          disabledTooltip="Show Spell Rank",
          getValue=function() return Get("rankFont") end,
          setValue=function(v) Set("rankFont", v) end });  y = y - h

    do
        local rgn = masterRow._leftRegion
        EllesmereUI.BuildSyncIcon({
            region  = rgn,
            tooltip = "Apply Spell Rank Settings to all Bars",
            onClick = function()
                for _, key in ipairs(RANK_BARS) do CopyTo(key) end
                EllesmereUI:RefreshPage()
            end,
            isSynced = function()
                for _, key in ipairs(RANK_BARS) do
                    if not Same(key) then return false end
                end
                return true
            end,
            flashTargets = function() return { rgn } end,
            multiApply = {
                elementKeys   = RANK_BARS,
                elementLabels = SHORT_LABELS,
                getCurrentKey = function() return SelectedKey() end,
                onApply       = function(checkedKeys)
                    for _, key in ipairs(checkedKeys) do CopyTo(key) end
                    EllesmereUI:RefreshPage()
                end,
            },
        })
    end

    if not SB().rankEnabled then
        _, h = W:Spacer(parent, y, 20);  y = y - h
        return y
    end

    -------------------------------------------------------------------
    --  Text Size (+ position cog) | Text Color
    -------------------------------------------------------------------
    local textRow
    textRow, h = W:DualRow(parent, y,
        { type="slider", text="Rank Text Size", min=6, max=30, step=1, trackWidth=120,
          getValue=function() return Get("rankFontSize") end,
          setValue=function(v) Set("rankFontSize", v) end },
        { type="colorpicker", text="Rank Text Color", hasAlpha=false,
          tooltip="Color of a rank that is the highest one in your spellbook.",
          getValue=function()
              local c = SB().rankColor or SR.DEFAULT_COLOR
              return c.r, c.g, c.b, 1
          end,
          setValue=function(r, g, b) SetColor("rankColor", r, g, b) end });  y = y - h

    EllesmereUI.BuildInlineCog(textRow._leftRegion, { icon = EllesmereUI.DIRECTIONS_ICON,
        title = "Spell Rank Position",
        rows = {
            { type="dropdown", label="Position",
              values=ANCHOR_LABELS, order=ANCHOR_ORDER,
              get=function() return Get("rankAnchor") end,
              set=function(v) Set("rankAnchor", v) end },
            { type="slider", label="X Offset", min=-50, max=50, step=1,
              get=function() return Get("rankOffsetX") end,
              set=function(v) Set("rankOffsetX", v) end },
            { type="slider", label="Y Offset", min=-50, max=50, step=1,
              get=function() return Get("rankOffsetY") end,
              set=function(v) Set("rankOffsetY", v) end },
        },
    })

    -------------------------------------------------------------------
    --  Outline | Format
    -------------------------------------------------------------------
    _, h = W:DualRow(parent, y,
        { type="dropdown", text="Rank Text Outline",
          values=OUTLINE_LABELS, order=OUTLINE_ORDER,
          getValue=function() return Get("rankOutline") end,
          setValue=function(v) Set("rankOutline", v) end },
        { type="dropdown", text="Rank Format",
          values=FORMAT_LABELS, order=FORMAT_ORDER,
          getValue=function() return Get("rankFormat") end,
          setValue=function(v) Set("rankFormat", v) end });  y = y - h

    -------------------------------------------------------------------
    --  Background (+ swatch with opacity) | Background Padding
    -------------------------------------------------------------------
    local bgRow
    bgRow, h = W:DualRow(parent, y,
        { type="dropdown", text="Rank Background",
          values=BG_MODE_LABELS, order=BG_MODE_ORDER,
          getValue=function() return Get("rankBgMode") end,
          setValue=function(v) Set("rankBgMode", v) end },
        { type="slider", text="Background Padding", min=0, max=8, step=1,
          disabled=function() return Get("rankBgMode") == "none" end,
          disabledTooltip="Rank Background",
          getValue=function() return Get("rankBgPad") end,
          setValue=function(v) Set("rankBgPad", v) end });  y = y - h

    do
        local rgn = bgRow._leftRegion
        local ctrl = rgn._control
        local swatch, updateSwatch = EllesmereUI.BuildColorSwatch(
            rgn, bgRow:GetFrameLevel() + 3,
            function()
                local c = SB().rankBgColor or SR.DEFAULT_BG
                return c.r, c.g, c.b, c.a or 0.7
            end,
            function(r, g, b, a) SetColor("rankBgColor", r, g, b, a or 0.7) end,
            true, 20)
        PP.Point(swatch, "RIGHT", ctrl, "LEFT", -12, 0)
        rgn._lastInline = swatch
        local function SwState()
            updateSwatch()
            swatch:SetAlpha(Get("rankBgMode") == "custom" and 1 or 0.25)
        end
        EllesmereUI.RegisterWidgetRefresh(SwState)
        SwState()
    end

    -------------------------------------------------------------------
    --  Max Rank Checker | Lower Rank Color
    -------------------------------------------------------------------
    local function CheckOff() return not Get("rankCheck") end
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Max Rank Checker",
          tooltip="Paints the rank in the Lower Rank Color when your spellbook has a higher rank of that spell than the one on the button. Type /spellrank to list them in chat.",
          getValue=function() return Get("rankCheck") and true or false end,
          setValue=function(v) Set("rankCheck", v and true or false) end },
        { type="colorpicker", text="Lower Rank Color", hasAlpha=false,
          disabled=CheckOff, disabledTooltip="Max Rank Checker",
          getValue=function()
              local c = SB().rankWarnColor or SR.DEFAULT_WARN
              return c.r, c.g, c.b, 1
          end,
          setValue=function(r, g, b) SetColor("rankWarnColor", r, g, b) end });  y = y - h

    -------------------------------------------------------------------
    --  Only Lower Ranks | Tint Background
    -------------------------------------------------------------------
    _, h = W:DualRow(parent, y,
        { type="toggle", text="Show Only Lower Ranks",
          tooltip="Hides the rank on buttons that already hold your highest rank.",
          disabled=CheckOff, disabledTooltip="Max Rank Checker",
          getValue=function() return Get("rankOnlyLow") and true or false end,
          setValue=function(v) Set("rankOnlyLow", v and true or false) end },
        { type="toggle", text="Lower Rank Background",
          tooltip="A lower rank also paints the background in the Lower Rank Color (needs Rank Background on; its opacity is kept).",
          disabled=function() return CheckOff() or Get("rankBgMode") == "none" end,
          disabledTooltip="Max Rank Checker / Rank Background",
          getValue=function() return Get("rankWarnBg") and true or false end,
          setValue=function(v) Set("rankWarnBg", v and true or false) end });  y = y - h

    _, h = W:Spacer(parent, y, 20);  y = y - h
    return y
end

X.Register("SpellRank", 20, BuildSpellRank)

local IsLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
if not (IsLoaded and IsLoaded("EllesmereUIOptions") and X.Install()) then
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        if name == "EllesmereUIOptions" then
            X.Install()
            self:UnregisterAllEvents()
        end
    end)
end
