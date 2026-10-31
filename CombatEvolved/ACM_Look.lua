-- Combat Evolved: Reticle Look module (style, colors, opacity, lock-on, mini health bar, interact hint)
local TEX = "Interface\\AddOns\\CombatEvolved\\Textures\\"
local STYLES = { "classic", "dot", "cross", "plus", "ring", "ringdot", "target", "crosshair", "sniper", "dashring", "arcs", "brackets", "square", "diamond", "chevrons", "tdot" }
local STYLE_NAMES = { classic = "Classic lines", dot = "Dot", cross = "Cross (gap)", plus = "Plus", ring = "Ring", ringdot = "Ring + dot", target = "Double ring", crosshair = "Crosshair", sniper = "Scope", dashring = "Dashed ring", arcs = "Arcs", brackets = "Corner brackets", square = "Rounded square", diamond = "Diamond", chevrons = "Chevrons", tdot = "Four dots" }
local STATES = { "none", "hostile", "neutral", "friend", "loot", "dead" }
local STATE_NAMES = { none = "Nothing aimed", hostile = "Enemy", neutral = "Neutral", friend = "Friendly", loot = "Lootable", dead = "Tapped / dead" }
local LOCK_DUR = 0.18

local D = ACM.moduleDefaults
D.lookStyle = "ringdot"
D.cols = {}
D.alphaIdle = 0.6
D.alphaAim = 1
D.showName = true
D.hpBar = true
D.hintOn = true
D.lockOn = true

local cross = ACM.cross
local nameText = ACM.nameText

local shadow = cross:CreateTexture(nil, "BACKGROUND")
local main = cross:CreateTexture(nil, "OVERLAY")
for _, t in ipairs({ shadow, main }) do
    t:SetWidth(40); t:SetHeight(40)
    t:SetPoint("CENTER", cross, "CENTER", 0, 0)
    t:Hide()
end
shadow:SetVertexColor(0, 0, 0)

local hpBg = cross:CreateTexture(nil, "BACKGROUND")
hpBg:SetTexture(TEX .. "barbg.tga")
hpBg:SetVertexColor(0, 0, 0)
hpBg:SetAlpha(0.75)
hpBg:SetWidth(40); hpBg:SetHeight(7)
hpBg:SetPoint("TOP", cross, "BOTTOM", 0, -4)
local hpFill = cross:CreateTexture(nil, "ARTWORK")
hpFill:SetTexture(TEX .. "barfill.tga")
hpFill:SetHeight(5)
hpFill:SetPoint("TOPLEFT", hpBg, "TOPLEFT", 1.5, -1)
hpBg:Hide(); hpFill:Hide()

local flash = cross:CreateTexture(nil, "BACKGROUND")
flash:SetTexture(TEX .. "glow.tga")
flash:SetWidth(76); flash:SetHeight(76)
flash:SetPoint("CENTER", cross, "CENTER", 0, 0)
flash:Hide()

local hint = cross:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

local function Anchor()
    nameText:ClearAllPoints()
    hint:ClearAllPoints()
    if ACMDB.hpBar then
        nameText:SetPoint("TOP", hpBg, "BOTTOM", 0, -2)
    else
        nameText:SetPoint("TOP", cross, "BOTTOM", 0, -2)
    end
    hint:SetPoint("TOP", nameText, "BOTTOM", 0, -1)
end

local function ApplyStyle()
    local st = ACMDB.lookStyle or "classic"
    local classic = (st == "classic")
    ACM.hideClassic = not classic
    for i = 1, #ACM.parts do if classic then ACM.parts[i]:Show() else ACM.parts[i]:Hide() end end
    for i = 1, #ACM.shadows do if classic then ACM.shadows[i]:Show() else ACM.shadows[i]:Hide() end end
    if classic then
        main:Hide(); shadow:Hide()
    else
        main:SetTexture(TEX .. st .. ".tga")
        shadow:SetTexture(TEX .. st .. ".tga")
        main:Show(); shadow:Show()
    end
end

local function LoadColors()
    for state, c in pairs(ACMDB.cols or {}) do
        if ACM.STATECOL[state] and type(c) == "table" then
            ACM.STATECOL[state] = { c[1], c[2], c[3] }
        end
    end
end

local prevState, lockT = "none", 0
local function SetSize(k)
    local sz = 40 * k
    main:SetWidth(sz); main:SetHeight(sz)
    shadow:SetWidth(sz + 3); shadow:SetHeight(sz + 3)
end

local function HintFor(state)
    if not ACMDB.hintOn or not ACMDB.interact or not ACMDB.interactKey or ACMDB.interactKey == "" then return "" end
    if ACM.talkFar and (state == "loot" or state == "friend") then return "Too far" end
    if state == "loot" then return "[" .. ACMDB.interactKey .. "] Loot" end
    if state == "friend" then return "[" .. ACMDB.interactKey .. "] Talk" end
    return ""
end

ACM.On("reticle", function(state, r, g, b, name, hp)
    if not ACMDB then return end
    if not ACM.hideClassic then
        -- classic lines are recolored by the core
    else
        main:SetVertexColor(r, g, b)
        shadow:SetAlpha(0.65)
    end
    cross:SetAlpha(state == "none" and (ACMDB.alphaIdle or 0.7) or (ACMDB.alphaAim or 1))
    if not ACMDB.showName then nameText:SetText("") end
    hint:SetText(HintFor(state))
    hint:SetTextColor(r, g, b)
    if ACMDB.hpBar and hp and state ~= "none" then
        hpBg:Show(); hpFill:Show()
        hpFill:SetVertexColor(r, g, b)
        local f = math.min(1, math.max(0.02, hp))
        hpFill:SetTexCoord(0, f, 0, 1)
        hpFill:SetWidth(37 * f)
    else
        hpBg:Hide(); hpFill:Hide()
    end
    flash:SetVertexColor(r, g, b)
    if ACMDB.lockOn and prevState == "none" and state ~= "none" then
        lockT = LOCK_DUR
        flash:Show()
        if ACM.OnLock then ACM.OnLock(state) end
    end
    prevState = state
end)

ACM.On("tick", function(dt)
    if lockT > 0 then
        lockT = lockT - dt
        if lockT <= 0 then lockT = 0; flash:Hide() else flash:SetAlpha(0.7 * lockT / LOCK_DUR) end
        if not ACM.hideClassic then return end
        SetSize(1 + 0.6 * (lockT / LOCK_DUR))
    elseif ACM.hideClassic and main:GetWidth() ~= 40 then
        SetSize(1)
    end
end)

ACM.On("mode", function() prevState = "none"; lockT = 0; flash:Hide(); if ACMDB then SetSize(1) end end)

local function MkButton(parent, x, y, w, text, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    b:SetWidth(w); b:SetHeight(22)
    b:SetText(text)
    b:SetScript("OnClick", fn)
    return b
end

ACM.On("reset", function()
    ACM.STATECOL.hostile = { 1, 0.15, 0.15 }; ACM.STATECOL.neutral = { 1, 0.9, 0.1 }
    ACM.STATECOL.friend = { 0.2, 1, 0.2 }; ACM.STATECOL.dead = { 0.6, 0.6, 0.6 }
    ACM.STATECOL.loot = { 0.3, 0.6, 1 }; ACM.STATECOL.none = { 1, 1, 1 }
    ApplyStyle()
    Anchor()
end)

ACM.On("login", function()
    LoadColors()
    Anchor()
    ApplyStyle()
    local P = ACM.NewPage("Look", "Reticle Look", "Reticle look")
    ACM.pages = ACM.pages or {}
    ACM.pages.look = P

    P.Header("Style")
    local thumbs, styleLabel = {}, nil
    local function RefreshThumbs()
        for i, st in ipairs(STYLES) do
            if thumbs[i] then
                if ACMDB.lookStyle == st then thumbs[i].sel:Show() else thumbs[i].sel:Hide() end
            end
        end
        if styleLabel then styleLabel:SetText("Selected: " .. (STYLE_NAMES[ACMDB.lookStyle] or "")) end
    end
    P.Custom(138, function(c, y)
        for i, st in ipairs(STYLES) do
            local col, row = (i - 1) % 8, math.floor((i - 1) / 8)
            local b = CreateFrame("Button", "ACM_Thumb_" .. st, c)
            b:SetWidth(48); b:SetHeight(48)
            b:SetPoint("TOPLEFT", c, "TOPLEFT", 12 + col * 54, y - row * 54)
            local bg = b:CreateTexture(nil, "BACKGROUND")
            bg:SetTexture(0, 0, 0, 0.45)
            bg:SetAllPoints(b)
            local img = b:CreateTexture(nil, "ARTWORK")
            img:SetTexture(TEX .. st .. ".tga")
            img:SetWidth(44); img:SetHeight(44)
            img:SetPoint("CENTER", b, "CENTER", 0, 0)
            local sel = b:CreateTexture(nil, "OVERLAY")
            sel:SetTexture(1, 0.82, 0, 0.35)
            sel:SetAllPoints(b)
            sel:Hide()
            b.sel = sel
            b:SetScript("OnClick", function()
                ACMDB.lookStyle = st
                ApplyStyle()
                RefreshThumbs()
            end)
            b:SetScript("OnEnter", function(self)
                if GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(STYLE_NAMES[st]); GameTooltip:Show() end
            end)
            b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
            thumbs[i] = b
        end
        styleLabel = c:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        styleLabel:SetPoint("TOPLEFT", c, "TOPLEFT", 14, y - 112)
    end)
    table.insert(P.controls, { refresh = RefreshThumbs })

    local pv = 1
    P.Cycle("preview",
        function() return "Preview shows: " .. STATE_NAMES[STATES[pv]] end,
        "A live reticle is drawn while this page is open. Cycle through what it looks like for each kind of target.",
        function()
            pv = pv % #STATES + 1
            ACM.previewState = STATES[pv]
        end, 320)

    P.Header("What is shown")
    P.Check("name", "Target name under the reticle", "Shows the name of whatever the reticle is aimed at.",
        function() return ACMDB.showName end, function(v) ACMDB.showName = v end)
    P.Check("hp", "Mini health bar", "A small health bar of the aimed target under the reticle (needs nameplate aiming).",
        function() return ACMDB.hpBar end, function(v) ACMDB.hpBar = v; Anchor() end)
    P.Check("hint", "Interact hint", "Shows '[F] Loot' or '[F] Talk' (with your interact key) when aiming at lootables or friendly NPCs.",
        function() return ACMDB.hintOn end, function(v) ACMDB.hintOn = v end)
    P.Check("lock", "Lock-on animation", "The reticle briefly tightens and flashes when it snaps onto a target. Resizing only applies to the texture styles, not Classic lines.",
        function() return ACMDB.lockOn end, function(v) ACMDB.lockOn = v end)

    P.Header("Opacity")
    P.Slider("aidle", "When nothing is aimed", "Keep this low for a subtle reticle until you aim at something.",
        0.1, 1, 0.05, function() return ACMDB.alphaIdle end, function(v) ACMDB.alphaIdle = v end, "%.2f")
    P.Slider("aaim", "When a target is aimed", "Opacity once the reticle is on an enemy, NPC or lootable.",
        0.1, 1, 0.05, function() return ACMDB.alphaAim end, function(v) ACMDB.alphaAim = v end, "%.2f")

    P.Header("Colors")
    local swatches = {}
    local function SetCol(state, r, g, b)
        ACMDB.cols = ACMDB.cols or {}
        ACMDB.cols[state] = { r, g, b }
        ACM.STATECOL[state] = { r, g, b }
        for i = 1, #swatches do swatches[i].refresh() end
    end
    P.Custom(92, function(c, y)
        for i, state in ipairs(STATES) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            local b = MkButton(c, 12 + col * 184, y - row * 28, 176, "", function()
                local cc = ACM.STATECOL[state]
                ColorPickerFrame:Hide()
                ColorPickerFrame.hasOpacity = false
                ColorPickerFrame.previousValues = { cc[1], cc[2], cc[3] }
                ColorPickerFrame.func = function()
                    local r, g, bl = ColorPickerFrame:GetColorRGB()
                    SetCol(state, r, g, bl)
                end
                ColorPickerFrame.cancelFunc = function(prev)
                    if prev then SetCol(state, prev[1], prev[2], prev[3]) end
                end
                ColorPickerFrame:SetColorRGB(cc[1], cc[2], cc[3])
                ColorPickerFrame:Show()
            end)
            local sq = b:CreateTexture(nil, "OVERLAY")
            sq:SetWidth(14); sq:SetHeight(14)
            sq:SetPoint("RIGHT", b, "RIGHT", -8, 0)
            b.refresh = function()
                b:SetText(STATE_NAMES[state])
                local cc = ACM.STATECOL[state]
                sq:SetTexture(cc[1], cc[2], cc[3], 1)
            end
            swatches[#swatches + 1] = b
            table.insert(P.controls, b)
        end
        MkButton(c, 12, y - 62, 176, "Reset colors", function()
            ACMDB.cols = {}
            ACM.STATECOL.hostile = { 1, 0.15, 0.15 }; ACM.STATECOL.neutral = { 1, 0.9, 0.1 }
            ACM.STATECOL.friend = { 0.2, 1, 0.2 }; ACM.STATECOL.dead = { 0.6, 0.6, 0.6 }
            ACM.STATECOL.loot = { 0.3, 0.6, 1 }; ACM.STATECOL.none = { 1, 1, 1 }
            for i = 1, #swatches do swatches[i].refresh() end
        end)
    end)
    P.Note("Click a color to change it. Enemy = red, neutral = yellow, friendly = green, lootable corpse = blue, tapped/dead = grey.")

    P.Finish(function() ACM.SetPreview(true); ACM.previewState = STATES[pv] end,
             function() ACM.SetPreview(false); ACM.previewState = nil end)
end)
