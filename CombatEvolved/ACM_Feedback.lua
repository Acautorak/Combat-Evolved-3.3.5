-- Combat Evolved: Combat Feedback module (hit/crit/kill markers, range tint, cooldown ring, cast arc)
local TEX = "Interface\\AddOns\\CombatEvolved\\Textures\\"
local D = ACM.moduleDefaults
D.fbHit = true
D.fbCrit = true
D.fbKill = true
D.fbRange = true
D.fbCD = true
D.fbCast = true
D.fbTalk = true
D.fbScale = 1

local cross = ACM.cross

-- marker ---------------------------------------------------------------
local marker = cross:CreateTexture(nil, "OVERLAY")
marker:SetTexture(TEX .. "hit.tga")
marker:SetPoint("CENTER", cross, "CENTER", 0, 0)
marker:Hide()
local mT, mDur, mBase = 0, 0.25, 36

local function ShowMarker(kind)
    local sc = ACMDB.fbScale or 1
    marker:SetTexture(TEX .. (kind == "kill" and "kill.tga" or "hit.tga"))
    if kind == "kill" then
        marker:SetVertexColor(1, 0.15, 0.15); mBase = 56 * sc; mDur = 0.5
    elseif kind == "crit" then
        marker:SetVertexColor(1, 0.82, 0); mBase = 44 * sc; mDur = 0.3
    else
        marker:SetVertexColor(1, 1, 1); mBase = 34 * sc; mDur = 0.22
    end
    mT = mDur
    marker:SetAlpha(1)
    marker:SetWidth(mBase); marker:SetHeight(mBase)
    marker:Show()
end
ACM.ShowMarker = ShowMarker

-- arcs -----------------------------------------------------------------
local function MakeArc(n, radius, size)
    local arc = { n = n, pips = {}, lit = -1 }
    for i = 1, n do
        local t = cross:CreateTexture(nil, "OVERLAY")
        t:SetTexture(TEX .. "pip.tga")
        t:SetWidth(size); t:SetHeight(size)
        local ang = math.pi / 2 - 2 * math.pi * (i - 1) / n
        t:SetPoint("CENTER", cross, "CENTER", math.cos(ang) * radius, math.sin(ang) * radius)
        t:Hide()
        arc.pips[i] = t
    end
    function arc.Set(frac, r, g, b, a)
        local lit = 0
        if frac and frac > 0 then lit = math.min(n, math.ceil(frac * n)) end
        for i = 1, n do
            local t = arc.pips[i]
            if i <= lit then
                t:SetVertexColor(r, g, b); t:SetAlpha(a or 0.9); t:Show()
            else
                t:Hide()
            end
        end
        arc.lit = lit
    end
    return arc
end
local cdArc = MakeArc(32, 25, 5)
local castArc = MakeArc(40, 31, 5)

-- range ------------------------------------------------------------------
local outOfRange = false
local function ActionId(slot)
    local b = _G["ActionButton" .. slot]
    if b and ActionButton_GetPagedID then
        local ok, id = pcall(ActionButton_GetPagedID, b)
        if ok and id then return id end
    end
    return slot
end

local talkFar = false
ACM.TintFn = function(state, r, g, b)
    if ACMDB and ACMDB.fbRange and state == "hostile" and outOfRange then
        return 0.75, 0.35, 0.95
    end
    if ACMDB and ACMDB.fbTalk and talkFar and (state == "friend" or state == "loot") then
        return 0.5, 0.5, 0.5
    end
end

-- combat log ---------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
f:SetScript("OnEvent", function(_, event, ...)
    if not ACMDB or not ACM.Active() then return end
    local ts, sub, sg, sn, sf, dg, dn, df, a9, a10, a11, a12, a13, a14, a15, a16, a17, a18 = ...
    if sg ~= UnitGUID("player") then return end
    if sub == "PARTY_KILL" then
        if ACMDB.fbKill then ShowMarker("kill") end
        if ACM.Sound then ACM.Sound("kill") end
        return
    end
    local crit
    if sub == "SWING_DAMAGE" then
        crit = a15
    elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" then
        crit = a18
    else
        return
    end
    if ACMDB.fbHit then
        if crit and ACMDB.fbCrit then ShowMarker("crit") else ShowMarker("hit") end
    end
    if ACM.Sound then
        if crit and ACMDB.snd and ACMDB.snd.crit and ACMDB.snd.crit ~= "off" then ACM.Sound("crit") else ACM.Sound("hit") end
    end
end)

-- tick -------------------------------------------------------------------------
local acc = 0
ACM.On("tick", function(dt)
    if not ACMDB then return end
    if mT > 0 then
        mT = mT - dt
        if mT <= 0 then
            mT = 0; marker:Hide()
        else
            local p = 1 - mT / mDur
            local sz = mBase * (0.8 + 0.5 * p)
            marker:SetWidth(sz); marker:SetHeight(sz)
            marker:SetAlpha(1 - p)
        end
    end
    acc = acc + dt
    if acc < 0.05 then return end
    acc = 0
    local shown = cross:IsShown()
    -- range
    outOfRange = false
    if ACMDB.fbRange and shown and UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        local r = IsActionInRange(ActionId(ACMDB.left or 1))
        if r == 0 then outOfRange = true end
    end
    -- interaction range (quest givers / loot): grey when too far (about 10 yards, the closest range the game exposes)
    talkFar = false
    ACM.talkFar = false
    if ACMDB.fbTalk and shown and ACM.name and ACM.name ~= "" and (ACM.state == "friend" or ACM.state == "loot") and CheckInteractDistance then
        local u
        if UnitExists("target") and UnitName("target") == ACM.name then
            u = "target"
        elseif UnitExists("mouseover") and UnitName("mouseover") == ACM.name then
            u = "mouseover"
        end
        if u and not UnitIsPlayer(u) and not CheckInteractDistance(u, 3) then
            talkFar = true
            ACM.talkFar = true
        end
    end
    -- cooldown ring (button 1)
    if ACMDB.fbCD and shown then
        local start, dur, en = GetActionCooldown(ActionId(ACMDB.left or 1))
        if start and dur and start > 0 and dur > 0 and en ~= 0 then
            local frac = 1 - (GetTime() - start) / dur
            if dur > 2 then cdArc.Set(frac, 1, 0.55, 0.2) else cdArc.Set(frac, 0.9, 0.9, 0.9, 0.6) end
        else
            if cdArc.lit ~= 0 then cdArc.Set(0, 1, 1, 1) end
        end
    elseif cdArc.lit ~= 0 then
        cdArc.Set(0, 1, 1, 1)
    end
    -- cast arc
    local frac
    if ACMDB.fbCast and shown then
        local name, _, _, _, st, en = UnitCastingInfo("player")
        if name and st and en and en > st then
            frac = (GetTime() * 1000 - st) / (en - st)
        else
            local cn, _, _, _, cs, ce = UnitChannelInfo("player")
            if cn and cs and ce and ce > cs then frac = 1 - (GetTime() * 1000 - cs) / (ce - cs) end
        end
    end
    if frac then
        castArc.Set(math.max(0, math.min(1, frac)), 0.4, 0.8, 1)
    elseif castArc.lit ~= 0 then
        castArc.Set(0, 1, 1, 1)
    end
end)

ACM.On("mode", function()
    mT = 0; marker:Hide(); outOfRange = false
    cdArc.Set(0, 1, 1, 1); castArc.Set(0, 1, 1, 1)
end)

ACM.On("login", function()
    local P = ACM.NewPage("Feedback", "Combat Feedback", "Combat feedback")
    ACM.pages = ACM.pages or {}
    ACM.pages.feedback = P

    P.Header("Hit markers")
    P.Check("hit", "Hit marker", "A small X flashes on the reticle when you damage something.",
        function() return ACMDB.fbHit end, function(v) ACMDB.fbHit = v end)
    P.Check("crit", "Bigger gold marker on critical hits", "Critical hits get a larger gold X.",
        function() return ACMDB.fbCrit end, function(v) ACMDB.fbCrit = v end)
    P.Check("kill", "Red kill marker", "A larger red marker when you land the killing blow.",
        function() return ACMDB.fbKill end, function(v) ACMDB.fbKill = v end)
    P.Slider("fbscale", "Marker size", "Scales all three markers. The test buttons need the preview, which shows while this page is open.",
        0.5, 2, 0.1, function() return ACMDB.fbScale end, function(v) ACMDB.fbScale = v end, "%.1f")
    P.Custom(34, function(c, y)
        local function B(x, text, kind)
            local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
            b:SetPoint("TOPLEFT", c, "TOPLEFT", x, y)
            b:SetWidth(110); b:SetHeight(22); b:SetText(text)
            b:SetScript("OnClick", function() ShowMarker(kind) end)
        end
        B(14, "Test hit", "hit"); B(130, "Test crit", "crit"); B(246, "Test kill", "kill")
    end)

    P.Header("Range")
    P.Check("range", "Purple reticle when the target is out of range", "Uses your left-click action button's range. Needs a hostile target selected.",
        function() return ACMDB.fbRange end, function(v) ACMDB.fbRange = v end)
    P.Check("talk", "Grey reticle when too far to interact", "Quest givers and lootables turn grey beyond about 10 yards (the closest check the game offers, so it can differ slightly from real talk range). Works on units you have targeted or are mousing over.",
        function() return ACMDB.fbTalk end, function(v) ACMDB.fbTalk = v end)

    P.Header("Rings and arcs")
    P.Check("cd", "Cooldown ring", "A ring that empties as your left-click button's cooldown finishes. White is the global cooldown, orange a real cooldown.",
        function() return ACMDB.fbCD end, function(v) ACMDB.fbCD = v end)
    P.Check("cast", "Cast / channel arc", "A blue arc around the reticle showing the progress of your current cast or channel.",
        function() return ACMDB.fbCast end, function(v) ACMDB.fbCast = v end)
    P.Note("Markers react to your own damage in the combat log.")
    P.Finish(function() ACM.SetPreview(true) end, function() ACM.SetPreview(false) end)
end)
