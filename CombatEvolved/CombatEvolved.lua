-- Combat Evolved v3.4 for WotLK 3.3.5a (formerly ActionCombat)
-- MIDDLE MOUSE toggles action combat mode:
--   * cursor hidden, camera in mouselook (character turns with the camera)
--   * Left click  -> action button <left>  (default 1), optional auto-attack
--   * Right click -> action button <right> (default 2), optional auto-attack
--   * Reticle sits where the (frozen) mouse pointer is. Put the mouse at screen center
--     before pressing middle mouse for a centered reticle.
--   * NAMEPLATE AIMING: the addon reads the game's nameplates and finds the one
--     under the reticle -> real-time color: red enemy, yellow neutral, green friendly.
--     Clicking (out of combat) targets that unit first.
--   * HOLD ALT: mouselook pauses, the cursor reappears exactly at the reticle and normal
--     mouse clicks come back, so you can click loot, chests, benches, NPCs directly.
--   * F = SMART INTERACT: aim the reticle at a friendly NPC (quest giver, guard, vendor):
--     first press targets it, next press interacts. Already targeted / looting a corpse =
--     one press. (Optional experimental "same press" mode in Interaction & Nameplates.)
--   * LOOT-F: with nothing aimed (no green/red/player plate under the reticle) F frees the
--     cursor at the reticle position; press F again = Interact With Mouseover (loot a corpse,
--     open a chest...), then mouselook resumes by itself.
--   * G = target the friendly PLAYER under the reticle (or nearest friendly player).
--   * WORLD CLICK: with no enemy/NPC plate under the reticle (and not in combat), the first
--     left click frees the cursor at the reticle position and the SECOND left click is the
--     game's own real click (the game ignores plain clicks while mouselooking, so it takes
--     two). Mouselook resumes right after.
--   * Blue reticle = your target is a dead enemy (press F to loot it)
--
-- NOTE: the 3.3.5a client does not update "unit under the mouse" while mouselooking,
-- hence nameplates for aiming and ALT for real hovering.
--
-- Settings panel: /acm   (or Interface > AddOns > Combat Evolved)
-- Macro to toggle without the mouse:  /click ACM_Toggle

local ACM_VERSION = 10
local ACM_DEFAULTS = {
    left = 1, right = 2, crosshair = true, ui = true,
    plates = true,          -- nameplate aiming (reticle colors + click targeting)
    friendAlpha = 0,        -- opacity of friendly nameplates in action mode (0 = hidden, 1 = normal)
    fallback = false,       -- click with no target -> nearest enemy in front of you
    trace = false,          -- /acm trace: print every click the addon fires
    direct = false,         -- true = plain ACTIONBUTTON bindings (no targeting/auto-attack)
    clickon = "down",       -- fire on mouse "down" or "up"
    atkLeft = true, atkRight = false,
    scale = 1,
    interact = true, interactKey = "F", interactMode = "target",
    friendKey = "G",
    reticleFollow = false,  -- true = draw reticle at the (frozen) pointer position
    reticleX = 95, reticleY = 20,  -- fixed-mode offset from screen center (pixels)
    worldClick = true,      -- nothing aimed (and out of combat): left click = game's own click, not action button
    worldClickFriends = false,  -- also use the game's click when aiming at friendly NPCs/players
    lootF = false,          -- F with nothing aimed: free cursor at reticle, next F interacts with mouseover
    smartF = true,          -- F targets the friendly NPC under the reticle, then interacts
    chat = false,           -- print status messages to the chat frame
    screenText = true,      -- on-screen ON/OFF and cursor hints
    namesOnly = false,      -- hidden nameplates keep their name text, only bars/borders vanish
    clickSelect = false,    -- left click on a NEW aimed enemy only selects it; the next click fires your button
    nameColor = "game",     -- names-only color: game (untouched) / reaction (bar color) / white
    nameScale = 1,          -- names-only text size multiplier
    ownNames = false,       -- show the game's own names above units (untouched), plates fully hidden
    barSource = "blizzard",  -- which action buttons the click buttons press (blizzard handles stance/form bars)
    freeKey = "alt",         -- hold to free the cursor at the reticle: alt / ctrl / shift / none
    autoTarget = true,      -- clicking targets the enemy under the reticle first (off = only fires your button)
    gPlayersOnly = true,    -- G targets players only
    enemyAlpha = 0,         -- enemy nameplate opacity in action mode (0 = hidden)
    trustHover = false,     -- use the game mouseover unit while mouselooking (test with /acm hovertest)
    camNormal = 10,         -- camera distance to return to when leaving action mode
    camSet = false, camDist = 6,
    hudFade = false, hudAlpha = 0.35,
}

local function Say(s, force)
    if force or ACM_inSlash or (ACM_diagUntil and GetTime() < ACM_diagUntil) or (ACMDB and ACMDB.chat) then
        print("|cff66ccffCombat Evolved:|r " .. s)
    end
end

-- Public API for the add-on's modules (ACM_Look / ACM_Feedback / ACM_Immersion)
ACM = {
    STATECOL = {
        hostile = { 1, 0.15, 0.15 }, neutral = { 1, 0.9, 0.1 }, friend = { 0.2, 1, 0.2 },
        dead = { 0.6, 0.6, 0.6 }, loot = { 0.3, 0.6, 1 }, none = { 1, 1, 1 },
    },
    moduleDefaults = {},
    Say = Say,
}
local acmHooks = {}
function ACM.On(event, fn)
    acmHooks[event] = acmHooks[event] or {}
    table.insert(acmHooks[event], fn)
end
function ACM.Fire(event, ...)
    local l = acmHooks[event]
    if not l then return end
    for i = 1, #l do
        local ok, err = pcall(l[i], ...)
        if not ok then
            ACM.errs = (ACM.errs or 0) + 1
            if ACM.errs < 4 then Say("module error (" .. event .. "): " .. tostring(err)) end
        end
    end
end

-------------------------------------------------------------------------------
-- Secure frames
-------------------------------------------------------------------------------
local toggle = CreateFrame("Button", "ACM_Toggle", UIParent, "SecureHandlerClickTemplate,SecureHandlerStateTemplate")
toggle:RegisterForClicks("AnyUp")
toggle:SetAttribute("acm", 0)
toggle:SetAttribute("alt", 0)
toggle:SetAttribute("direct", 0)
toggle:SetAttribute("leftslot", 1)
toggle:SetAttribute("rightslot", 2)
toggle:SetAttribute("interactkey", "")
toggle:SetAttribute("interactaction", "INTERACTTARGET")
toggle:SetAttribute("friendkey", "")

local SNIP_BIND_CLICKS = [[
    if self:GetAttribute("direct") == 1 then
        self:SetBinding(true, "BUTTON1", "ACTIONBUTTON" .. self:GetAttribute("leftslot"))
        self:SetBinding(true, "BUTTON2", "ACTIONBUTTON" .. self:GetAttribute("rightslot"))
    else
        self:SetBindingClick(true, "BUTTON1", "ACM_Left")
        self:SetBindingClick(true, "BUTTON2", "ACM_Right")
    end
]]
local SNIP_BIND_EXTRA = [[
    local ik = self:GetAttribute("interactkey")
    if ik and ik ~= "" then
        self:SetBinding(true, ik, self:GetAttribute("interactaction"))
    end
    local fk = self:GetAttribute("friendkey")
    if fk and fk ~= "" then
        self:SetBindingClick(true, fk, "ACM_Friend")
    end
]]
local SNIP_CLEAR_ALL = [[
    self:ClearBinding("BUTTON1")
    self:ClearBinding("BUTTON2")
    local ik = self:GetAttribute("interactkey")
    if ik and ik ~= "" then self:ClearBinding(ik) end
    local fk = self:GetAttribute("friendkey")
    if fk and fk ~= "" then self:ClearBinding(fk) end
]]

local SNIP_SETMODE = [[
    self:SetAttribute("acm", on and 1 or 0)
    if on then
        if self:GetAttribute("alt") ~= 1 then
]] .. SNIP_BIND_CLICKS .. [[
        end
]] .. SNIP_BIND_EXTRA .. [[
    else
]] .. SNIP_CLEAR_ALL .. [[
    end
]]

toggle:SetAttribute("_onclick", [[
    local on = self:GetAttribute("acm") ~= 1
    self:SetAttribute("autowas", 0)
]] .. SNIP_SETMODE)

-- Auto enter when combat starts / leave when it ends (only if we entered automatically)
toggle:SetAttribute("autocombat", 0)
toggle:SetAttribute("autoexit", 0)
toggle:SetAttribute("autowas", 0)
toggle:SetAttribute("_onstate-acmcombat", [[
    if newstate == "1" then
        if self:GetAttribute("autocombat") == 1 and self:GetAttribute("acm") ~= 1 then
            self:SetAttribute("autowas", 1)
            local on = true
]] .. SNIP_SETMODE .. [[
        end
    else
        if self:GetAttribute("autoexit") == 1 and self:GetAttribute("autowas") == 1 and self:GetAttribute("acm") == 1 then
            local on = false
]] .. SNIP_SETMODE .. [[
        end
        self:SetAttribute("autowas", 0)
    end
]])
RegisterStateDriver(toggle, "acmcombat", "[combat] 1; 0")

-- While ALT is held, give the normal mouse clicks back
toggle:SetAttribute("_onstate-acmalt", [[
    self:SetAttribute("alt", (newstate == "1") and 1 or 0)
    if self:GetAttribute("acm") == 1 then
        if newstate == "1" then
            self:ClearBinding("BUTTON1")
            self:ClearBinding("BUTTON2")
        else
]] .. SNIP_BIND_CLICKS .. [[
        end
    end
]])
RegisterStateDriver(toggle, "acmalt", "[mod:alt] 1; 0")

local function FreeKeyDown()
    local k = ACMDB and ACMDB.freeKey or "alt"
    if k == "alt" then return IsAltKeyDown() end
    if k == "ctrl" then return IsControlKeyDown() end
    if k == "shift" then return IsShiftKeyDown() end
    return false
end
ACM.FreeKeyDown = FreeKeyDown

local function Active()
    return toggle:GetAttribute("acm") == 1
end

local leftBtn = CreateFrame("Button", "ACM_Left", UIParent, "SecureActionButtonTemplate")
leftBtn:RegisterForClicks("LeftButtonDown")
leftBtn:SetAttribute("type", "macro")

local rightBtn = CreateFrame("Button", "ACM_Right", UIParent, "SecureActionButtonTemplate")
rightBtn:RegisterForClicks("LeftButtonDown")
rightBtn:SetAttribute("type", "macro")

local friendBtn = CreateFrame("Button", "ACM_Friend", UIParent, "SecureActionButtonTemplate")
friendBtn:RegisterForClicks("LeftButtonDown")
friendBtn:SetAttribute("type", "macro")
friendBtn:SetAttribute("macrotext", "/targetfriendplayer")

local interactBtn = CreateFrame("Button", "ACM_Interact", UIParent, "SecureActionButtonTemplate")
interactBtn:RegisterForClicks("LeftButtonDown")
interactBtn:SetAttribute("type", "macro")
interactBtn:SetAttribute("macrotext", "")

local worldBtn = CreateFrame("Button", "ACM_World", UIParent, "SecureActionButtonTemplate")
worldBtn:RegisterForClicks("LeftButtonDown")

-------------------------------------------------------------------------------
-- Reticle
-------------------------------------------------------------------------------
local cross = CreateFrame("Frame", "ACM_Crosshair", UIParent)
cross:SetWidth(40)
cross:SetHeight(40)
cross:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
cross:SetFrameStrata("TOOLTIP")
cross:Hide()

local parts = {}
local shadows = {}
local function Part(w, h, x, y)
    local shadow = cross:CreateTexture(nil, "BACKGROUND")
    shadows[#shadows + 1] = shadow
    shadow:SetTexture(0, 0, 0, 0.8)
    shadow:SetWidth(w + 2)
    shadow:SetHeight(h + 2)
    shadow:SetPoint("CENTER", cross, "CENTER", x, y)
    local t = cross:CreateTexture(nil, "OVERLAY")
    t:SetTexture(1, 1, 1, 1)
    t:SetWidth(w)
    t:SetHeight(h)
    t:SetPoint("CENTER", cross, "CENTER", x, y)
    parts[#parts + 1] = t
end
Part(2, 2, 0, 0)
Part(2, 8, 0, 11)
Part(2, 8, 0, -11)
Part(8, 2, 11, 0)
Part(8, 2, -11, 0)

local nameText = cross:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
nameText:SetPoint("TOP", cross, "BOTTOM", 0, -2)

local function SetReticle(state, name, hp)
    local c = ACM.STATECOL[state] or ACM.STATECOL.none
    local r, g, b = c[1], c[2], c[3]
    if ACM.TintFn then
        local tr, tg, tb = ACM.TintFn(state, r, g, b)
        if tr then r, g, b = tr, tg, tb end
    end
    if not ACM.hideClassic then
        for i = 1, #parts do parts[i]:SetVertexColor(r, g, b) end
    end
    nameText:SetText(name or "")
    nameText:SetTextColor(r, g, b)
    ACM.state, ACM.name, ACM.hp = state, name, hp
    ACM.Fire("reticle", state, r, g, b, name, hp)
end
ACM.cross, ACM.nameText, ACM.parts, ACM.shadows = cross, nameText, parts, shadows
ACM.SetReticle = SetReticle

-------------------------------------------------------------------------------
-- Nameplate aiming
-------------------------------------------------------------------------------
local plates, knownChildren = {}, 0
local baseMacro = {}
local fMode = "action"
local StartLootHover
local StartWorldClick

local function IsPlate(f)
    if f:GetName() then return false end
    local o = select(2, f:GetRegions())
    return o and o.GetObjectType and o:GetObjectType() == "Texture"
        and o.GetTexture and o:GetTexture() == "Interface\\Tooltips\\Nameplate-Border"
end

local function ScanChildren()
    local n = WorldFrame:GetNumChildren()
    if n == knownChildren then return end
    for i = knownChildren + 1, n do
        local f = select(i, WorldFrame:GetChildren())
        if f and IsPlate(f) then plates[#plates + 1] = f end
    end
    knownChildren = n
end

local function PlateInfo(f)
    local name
    local regions = { f:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        if r.GetObjectType and r:GetObjectType() == "FontString" then
            name = r:GetText()
            break
        end
    end
    local bar = f:GetChildren()
    local r, g, b = 1, 1, 1
    local hp
    if bar and bar.GetStatusBarColor then r, g, b = bar:GetStatusBarColor() end
    if bar and bar.GetValue and bar.GetMinMaxValues then
        local lo, hi = bar:GetMinMaxValues()
        local v = bar:GetValue()
        if hi and lo and hi > lo and v then hp = (v - lo) / (hi - lo) end
    end
    return name, r, g, b, hp
end

local function Classify(r, g, b)
    if r > 0.85 and g < 0.3 and b < 0.3 then return "hostile" end
    if r > 0.85 and g > 0.75 and b < 0.3 then return "neutral" end
    if r < 0.3 and g > 0.85 and b < 0.3 then return "friend" end
    if r < 0.3 and g < 0.5 and b > 0.85 then return "player" end
    if math.abs(r - g) < 0.12 and math.abs(g - b) < 0.12 then return "tapped" end
    return "other"
end

-- The nameplate sits above the unit's head; accept plates horizontally near the
-- reticle and vertically a bit above it. Heuristic, scaled by plate width.
local function PlateUnderReticle()
    if ACMDB.ownNames then return nil end   -- plates are switched off in that mode
    ScanChildren()
    local cx, cy = cross:GetCenter()
    if not cx then return nil end
    local ces = cross:GetEffectiveScale()
    cx, cy = cx * ces, cy * ces
    local best, bestd
    for i = 1, #plates do
        local f = plates[i]
        if f:IsShown() then
            local px, py = f:GetCenter()
            if px then
                local es = f:GetEffectiveScale()
                px, py = px * es, py * es
                local w = f:GetWidth() * es
                local dx, dy = math.abs(px - cx), py - cy
                if dx < w * 0.6 and dy > -w * 0.3 and dy < w * 3 then
                    local d = dx + math.abs(dy) * 0.1
                    if not bestd or d < bestd then best, bestd = f, d end
                end
            end
        end
    end
    return best
end

-- Hide/fade nameplates (they stay "shown" so aiming and targeting still work)
-- Names-only: hide everything on a plate except its name text
local function NamesOnly(f, on)
    if on then
        local now = GetTime()
        if not f.acmNames or now >= (f.acmNext or 0) then
            -- (re)build the list of things to hide; refreshed once a second
            f.acmNext = now + 1
            f.acmOrig = f.acmOrig or {}
            local list = {}
            local seenName = false
            local regions = { f:GetRegions() }
            for i = 1, #regions do
                local r = regions[i]
                local keep = false
                if r.GetObjectType and r:GetObjectType() == "FontString" and not seenName then
                    seenName = true
                    keep = true
                    f.acmName = r
                end
                if not keep and r.SetAlpha then
                    if f.acmOrig[r] == nil then f.acmOrig[r] = r:GetAlpha() end
                    list[#list + 1] = r
                end
            end
            local kids = { f:GetChildren() }
            f.acmBar = kids[1]
            for i = 1, #kids do
                local c = kids[i]
                if c.SetAlpha then
                    if f.acmOrig[c] == nil then f.acmOrig[c] = c:GetAlpha() end
                    list[#list + 1] = c
                end
            end
            f.acmList = list
            f.acmNames = true
        end
        -- every frame: the game re-shows the threat glow / target highlight while you fight
        local l = f.acmList
        for i = 1, #l do l[i]:SetAlpha(0) end
        -- the game colors the name from the (now invisible) bar; do it ourselves so names keep their normal colors
        local bar, nm = f.acmBar, f.acmName
        local mode = ACMDB.nameColor or "game"
        if nm and mode == "reaction" and bar and bar.GetStatusBarColor then
            local r, g, b = bar:GetStatusBarColor()
            if r then nm:SetTextColor(r, g, b) end
        elseif nm and mode == "white" then
            nm:SetTextColor(1, 1, 1)
        end
        -- size: keep the game's own font unless a multiplier is set
        if nm and nm.GetFont and nm.SetFont then
            local want = ACMDB.nameScale or 1
            if not f.acmFont then
                local path, size, flags = nm:GetFont()
                f.acmFont = { path, size, flags }
            end
            if f.acmScaleApplied ~= want then
                local ft = f.acmFont
                if ft[1] and ft[2] then nm:SetFont(ft[1], ft[2] * want, ft[3]) end
                f.acmScaleApplied = want
            end
        end
    elseif f.acmNames then
        for r, a in pairs(f.acmOrig or {}) do r:SetAlpha(a) end
        f.acmOrig, f.acmList = nil, nil
        f.acmNames = nil
        if f.acmFont and f.acmName and f.acmScaleApplied and f.acmScaleApplied ~= 1 and f.acmFont[1] and f.acmFont[2] then
            f.acmName:SetFont(f.acmFont[1], f.acmFont[2], f.acmFont[3])
        end
        f.acmScaleApplied = nil
    end
end

local function FadePlates(on)
    ScanChildren()
    local fa, ea = ACMDB.friendAlpha, ACMDB.enemyAlpha
    local namesOnlyOn = ACMDB.namesOnly and not ACMDB.ownNames
    if ACMDB.ownNames then fa, ea = 0, 0 end
    local any = (fa and fa < 1) or (ea and ea < 1)
    if on and not any then on = false end
    for i = 1, #plates do
        local f = plates[i]
        if f:IsShown() then
            if on then
                local bar = f:GetChildren()
                if bar and bar.GetStatusBarColor then
                    local r, g, b = bar:GetStatusBarColor()
                    local c = Classify(r, g, b)
                    local want
                    if c == "friend" or c == "player" then
                        want = fa
                    elseif c == "hostile" or c == "neutral" then
                        want = ea
                    end
                    if want and want < 1 and namesOnlyOn then
                        if f.acmFaded then f:SetAlpha(1); f.acmFaded = nil end
                        NamesOnly(f, true)
                    elseif want and want < 1 then
                        if f.acmNames then NamesOnly(f, false) end
                        f:SetAlpha(want); f.acmFaded = true
                    else
                        if f.acmNames then NamesOnly(f, false) end
                        if f.acmFaded then f:SetAlpha(1); f.acmFaded = nil end
                    end
                end
            else
                if f.acmNames then NamesOnly(f, false) end
                if f.acmFaded then f:SetAlpha(1); f.acmFaded = nil end
            end
        end
    end
end

-- Colors: red = enemy, yellow = neutral, green = friendly, blue = your target is a
-- lootable corpse, grey = tapped/dead friendly, white = nothing under the reticle.
local function ReticleFromUnit(unit)
    local name = UnitName(unit)
    local mx = UnitHealthMax(unit)
    local hpf = (mx and mx > 0) and (UnitHealth(unit) / mx) or nil
    if UnitIsDead(unit) then
        if UnitIsFriend("player", unit) then
            SetReticle("dead", name, hpf)
        else
            SetReticle("loot", name, hpf)
        end
    elseif UnitCanAttack("player", unit) then
        SetReticle("hostile", name, hpf)
    elseif UnitIsFriend("player", unit) then
        SetReticle("friend", name, hpf)
    else
        SetReticle("neutral", name, hpf)
    end
end

local function UpdateReticle()
    if (ACMDB.trustHover or ACMDB.ownNames) and UnitExists("mouseover") then
        ReticleFromUnit("mouseover")
        return
    end
    if ACMDB.plates then
        local f = PlateUnderReticle()
        if f then
            local name, r, g, b, hpf = PlateInfo(f)
            local c = Classify(r, g, b)
            if c == "hostile" then
                SetReticle("hostile", name, hpf); return
            elseif c == "neutral" then
                SetReticle("neutral", name, hpf); return
            elseif c == "friend" or c == "player" then
                SetReticle("friend", name, hpf); return
            elseif c == "tapped" then
                SetReticle("dead", name, hpf); return
            end
        end
    end
    if UnitExists("target") and UnitIsDead("target") and not UnitIsFriend("player", "target") then
        SetReticle("loot", (UnitName("target") or ""))
        return
    end
    SetReticle("none", "")
end

-- Click targeting without calling protected functions: out of combat, a PreClick
-- hook prepends "/target <name>" to the button's secure macro, PostClick resets it.
local function PreClickTarget(self)
    if InCombatLockdown() then
        if ACMDB.trace then Say(self:GetName() .. ": in combat, can't retarget by click", true) end
        return
    end
    local base = baseMacro[self:GetName()]
    if not base then return end
    local isLeft = (self:GetName() == "ACM_Left")
    local sel = ACMDB.clickSelect and isLeft
    local prefix = ""
    local selectOnly = false
    if sel or ACMDB.autoTarget ~= false then
        local name
        if ACMDB.plates then
            local f = PlateUnderReticle()
            if f then
                local n, r, g, b = PlateInfo(f)
                local c = Classify(r, g, b)
                if n and n ~= "" and (c == "hostile" or c == "neutral") then name = n end
            end
        end
        if name then
            if not (UnitExists("target") and UnitName("target") == name and not UnitIsDead("target")) then
                if sel then
                    selectOnly = true
                    prefix = "/targetexact " .. name .. "\n/target " .. name
                else
                    prefix = "/target " .. name .. "\n"
                end
                if ACMDB.trace then Say("target by click: " .. name, true) end
            end
        elseif (sel or ACMDB.ownNames) and UnitExists("mouseover") and UnitCanAttack("player", "mouseover") and not UnitIsDead("mouseover")
            and not (UnitExists("target") and UnitIsUnit("target", "mouseover")) then
            -- no plate found (or plates are off), but the game reports an enemy under the pointer
            if sel then
                selectOnly = true
                prefix = "/target [target=mouseover,harm,nodead]"
            else
                prefix = "/target [target=mouseover,harm,nodead]\n"
            end
        elseif sel and ACMDB.trace then
            Say("click-select: no enemy plate under the reticle (plates " .. #plates .. ", nameplate aiming " .. tostring(ACMDB.plates) .. ")", true)
        end
    end
    if selectOnly then
        self:SetAttribute("macrotext", prefix)
    else
        self:SetAttribute("macrotext", prefix .. base)
    end
end

local function PreClickFriend(self)
    if InCombatLockdown() then return end
    local playersOnly = ACMDB.gPlayersOnly ~= false
    local macro = playersOnly and "/targetfriendplayer" or "/targetfriend"
    if ACMDB.plates then
        local f = PlateUnderReticle()
        if f then
            local name, r, g, b = PlateInfo(f)
            local c = Classify(r, g, b)
            if name and name ~= "" and (c == "player" or (not playersOnly and c == "friend")) then
                macro = "/target " .. name
            end
        end
    end
    self:SetAttribute("macrotext", macro)
end

-- Smart F: if a friendly NPC plate is under the reticle and it is not already your
-- target, target it first.
local function PreClickInteract(self)
    if InCombatLockdown() then return end
    local macro = ""
    if ACMDB.plates then
        local f = PlateUnderReticle()
        if f then
            local name, r, g, b = PlateInfo(f)
            if name and name ~= "" and Classify(r, g, b) == "friend" then
                if not (UnitExists("target") and UnitName("target") == name and not UnitIsDead("target")) then
                    macro = "/target " .. name
                end
            end
        end
    end
    self:SetAttribute("macrotext", macro)
end

local function PostClickCommon(self)
    if ACMDB.trace then
        local t = tostring(self:GetAttribute("macrotext")):gsub("\n", " | ")
        Say(self:GetName() .. " fired: " .. t, true)
    end
    if self == interactBtn and fMode == "hover" and StartLootHover then
        StartLootHover()
    end
    if self == worldBtn and StartWorldClick then
        StartWorldClick()
    end
    if InCombatLockdown() then return end
    if self == friendBtn then
        self:SetAttribute("macrotext", (ACMDB.gPlayersOnly ~= false) and "/targetfriendplayer" or "/targetfriend")
    elseif self == interactBtn then
        self:SetAttribute("macrotext", "")
    elseif baseMacro[self:GetName()] then
        self:SetAttribute("macrotext", baseMacro[self:GetName()])
    end
end

leftBtn:HookScript("PreClick", PreClickTarget)
rightBtn:HookScript("PreClick", PreClickTarget)
friendBtn:HookScript("PreClick", PreClickFriend)
interactBtn:HookScript("PreClick", PreClickInteract)
leftBtn:HookScript("PostClick", PostClickCommon)
rightBtn:HookScript("PostClick", PostClickCommon)
friendBtn:HookScript("PostClick", PostClickCommon)
interactBtn:HookScript("PostClick", PostClickCommon)
worldBtn:HookScript("PostClick", PostClickCommon)

local function PlaceReticle()
    cross:ClearAllPoints()
    if ACMDB.reticleFollow then
        local x, y = GetCursorPosition()
        local cs = cross:GetEffectiveScale()
        if x then
            cross:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / cs, y / cs)
            return
        end
    end
    cross:SetPoint("CENTER", UIParent, "CENTER", ACMDB.reticleX or 0, ACMDB.reticleY or 0)
end

-------------------------------------------------------------------------------
-- Immersion helpers (camera distance, HUD fade)
-------------------------------------------------------------------------------
local function SetCamDist(d)
    CameraZoomIn(50)
    if d and d > 0 then CameraZoomOut(d) end
end

local hudFrames = { "MinimapCluster", "WatchFrame", "BuffFrame", "ChatFrame1", "ChatFrame1Tab", "GeneralDockManager" }
local hudOrig = {}
local function FadeHUD(on)
    for i = 1, #hudFrames do
        local n = hudFrames[i]
        local f = _G[n]
        if f then
            if on then
                if hudOrig[n] == nil then hudOrig[n] = f:GetAlpha() end
                f:SetAlpha(ACMDB.hudAlpha)
            elseif hudOrig[n] ~= nil then
                f:SetAlpha(hudOrig[n])
                hudOrig[n] = nil
            end
        end
    end
end

-- The game's own names above units (3D text, not nameplates)
local PulseOn
local NAME_CVARS = { "UnitNameNPC", "UnitNameNonCombatCreatureName", "UnitNameFriendlyPlayerName",
    "UnitNameEnemyPlayerName", "UnitNameFriendlyPetName", "UnitNameEnemyPetName",
    "UnitNameFriendlyGuardianName", "UnitNameEnemyGuardianName" }
local function ApplyOwnNames(on)
    if on then
        ACMDB.savedNames = ACMDB.savedNames or {}
        for _, k in ipairs(NAME_CVARS) do
            local cur = GetCVar(k)
            if cur ~= nil then
                if ACMDB.savedNames[k] == nil then ACMDB.savedNames[k] = cur end
            end
        end
        PulseOn(NAME_CVARS)
    elseif ACMDB.savedNames then
        for k, v in pairs(ACMDB.savedNames) do pcall(SetCVar, k, v) end
        ACMDB.savedNames = nil
    end
end
ACM.ApplyOwnNames = ApplyOwnNames

-- The client does not always redraw names/plates when a CVar is set to the value it already has
-- (that is why you had to press V). Pulse 0 -> 1 so the change is real, then keep the values healed.
local pulseT, pulseList = nil, nil
PulseOn = function(list)
    local l = {}
    for _, k in ipairs(list) do
        if GetCVar(k) ~= nil then
            l[#l + 1] = k
            pcall(SetCVar, k, 0)
        end
    end
    if #l > 0 then
        pulseList = pulseList or {}
        for _, k in ipairs(l) do pulseList[#pulseList + 1] = k end
        pulseT = 0.12
    end
end
local healAcc = 0
local PLATE_CVARS = { "nameplateShowEnemies", "nameplateShowFriends" }
ACM.On("tick", function(dt)
    if pulseT then
        pulseT = pulseT - dt
        if pulseT <= 0 then
            for _, k in ipairs(pulseList) do pcall(SetCVar, k, 1) end
            pulseT, pulseList = nil, nil
        end
        return
    end
    healAcc = healAcc + dt
    if healAcc < 0.5 then return end
    healAcc = 0
    if not Active() then return end
    if ACMDB.ownNames then
        for _, k in ipairs(NAME_CVARS) do
            local v = GetCVar(k)
            if v ~= nil and tonumber(v) ~= 1 then pcall(SetCVar, k, 1) end
        end
    end
    if ACMDB.ownNames then
        for _, k in ipairs(PLATE_CVARS) do
            local v = GetCVar(k)
            if v ~= nil and tonumber(v) ~= 0 then pcall(SetCVar, k, 0) end
        end
    elseif ACMDB.plates then
        for _, k in ipairs(PLATE_CVARS) do
            local v = GetCVar(k)
            if v ~= nil and tonumber(v) ~= 1 then pcall(SetCVar, k, 1) end
        end
    end
end)

local savedZoom, savedPlates
local function OnModeChanged(active)
    if active then
        if (ACMDB.plates or ACMDB.ownNames) and not savedPlates then
            savedPlates = { GetCVar("nameplateShowEnemies"), GetCVar("nameplateShowFriends") }
            if ACMDB.ownNames then
                -- the game hides its own names above units whenever nameplates are on
                pcall(SetCVar, "nameplateShowEnemies", 0)
                pcall(SetCVar, "nameplateShowFriends", 0)
            else
                PulseOn(PLATE_CVARS)
            end
        end
        if ACMDB.camSet then
            savedZoom = GetCameraZoom and GetCameraZoom() or nil
            SetCamDist(ACMDB.camDist)
        end
        if ACMDB.hudFade then FadeHUD(true) end
        if ACMDB.ownNames then ApplyOwnNames(true) end
        ACM.Fire("mode", true)
    else
        ApplyOwnNames(false)
        ACM.Fire("mode", false)
        if savedPlates then
            if savedPlates[1] then pcall(SetCVar, "nameplateShowEnemies", savedPlates[1]) end
            if savedPlates[2] then pcall(SetCVar, "nameplateShowFriends", savedPlates[2]) end
            savedPlates = nil
        end
        if ACMDB.camSet then SetCamDist(savedZoom or ACMDB.camNormal or 10) end
        savedZoom = nil
        FadeHUD(false)
    end
end

-------------------------------------------------------------------------------
-- Look driver (mouselook or right-click-style turn)
-------------------------------------------------------------------------------
local blockers = {
    "CharacterFrame", "SpellBookFrame", "PlayerTalentFrame", "TalentFrame",
    "QuestLogFrame", "GossipFrame", "QuestFrame", "MerchantFrame", "TradeFrame",
    "MailFrame", "AuctionFrame", "WorldMapFrame", "LootFrame", "BankFrame",
    "FriendsFrame", "GameMenuFrame", "InterfaceOptionsFrame", "VideoOptionsFrame",
    "KeyBindingFrame", "MacroFrame", "TaxiFrame", "TradeSkillFrame", "CraftFrame",
    "InspectFrame", "DressUpFrame", "AchievementFrame", "LFDParentFrame",
    "PVPParentFrame", "StaticPopup1", "StaticPopup2",
    "ClassTrainerFrame", "PetStableFrame", "GuildBankFrame", "ItemSocketingFrame",
    "CalendarFrame", "BattlefieldFrame",
}
for i = 1, 13 do blockers[#blockers + 1] = "ContainerFrame" .. i end

local hoverPauseUntil = 0

local function Blocker()
    if GetCursorInfo() then return "item on cursor" end
    if FreeKeyDown() then return "free key held" end
    if GetTime() < hoverPauseUntil then return "loot hover" end
    if not UIParent:IsShown() then return "UI hidden" end
    if ChatFrame1EditBox and ChatFrame1EditBox:HasFocus() then return "typing in chat" end
    if ACMDB and ACMDB.ui == false then return nil end
    for i = 1, #blockers do
        local f = _G[blockers[i]]
        if f and f.IsVisible and f:IsVisible() then return blockers[i] end
    end
    return nil
end

local looking = false

local function StopLook()
    if IsMouselooking() then MouselookStop() end
    looking = false
end

local function StartLook()
    if not IsMouselooking() then MouselookStart() end
    looking = true
end

local lastWhy
local elapsed = 0
local previewing = false
ACM.SetPreview = function(b) previewing = b and true or false end
-- /acm keytest: shows what happens when you press the interact / friendly-target keys
local keytestUntil, keyDown = 0, {}
local TEST_EVENTS = {
    "UI_ERROR_MESSAGE", "LOOT_OPENED", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL",
    "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW", "TRAINER_SHOW", "TAXIMAP_OPENED",
    "BANKFRAME_OPENED", "PLAYER_TARGET_CHANGED",
}
local kt = CreateFrame("Frame")
kt:SetScript("OnEvent", function(_, event, arg1)
    if keytestUntil == 0 then return end
    if event == "UI_ERROR_MESSAGE" then
        Say("test: game says \"" .. tostring(arg1) .. "\"")
    elseif event == "PLAYER_TARGET_CHANGED" then
        Say("test: target is now " .. tostring(UnitExists("target") and UnitName("target") or "none"))
    else
        Say("test: " .. event .. "  (an interaction window opened)")
    end
end)

local function KeyTestTick()
    if keytestUntil == 0 then return end
    if GetTime() > keytestUntil then
        keytestUntil = 0
        kt:UnregisterAllEvents()
        Say("key test finished", true)
        return
    end
    local keys = { { ACMDB.interactKey, "interact" }, { ACMDB.friendKey, "friendly target" } }
    for i = 1, #keys do
        local k = keys[i][1]
        if k and k ~= "" then
            local ok, down = pcall(IsKeyDown, k)
            if not ok then
                Say("test: this client cannot read key '" .. k .. "' (" .. tostring(down) .. "), ending test")
                keytestUntil = GetTime() - 1
                return
            end
            if down and not keyDown[k] then
                keyDown[k] = true
                local t = "none"
                if UnitExists("target") then
                    t = tostring(UnitName("target")) ..
                        (UnitIsDead("target") and " (dead)" or "") ..
                        (UnitIsFriend("player", "target") and " (friendly)" or "")
                end
                Say("test: " .. k .. " pressed [" .. keys[i][2] .. "]  mode on: " .. tostring(Active()) ..
                    "  key is bound to: " .. tostring(GetBindingAction(k)) .. "  target: " .. t)
            elseif not down then
                keyDown[k] = nil
            end
        end
    end
end

-- Smart F: swap what F is bound to depending on what is under the reticle.
--   "action": F = game's Interact With Target (loot / talk to current target)
--   "click" : F = our button that targets the friendly NPC under the reticle first
--   "hover" : F = our button that frees the cursor at the reticle (loot hover)
--   "armed" : F = game's Interact With Mouseover (cursor is free, next F = the "click")
-- Rebinding is only possible out of combat.
local fbElapsed = 0
local lootKeyWasDown = false

local function SetFBind(mode)
    local key = ACMDB.interactKey
    if not key or key == "" then return end
    if mode == "click" or mode == "hover" then
        SetOverrideBindingClick(toggle, true, key, "ACM_Interact")
    elseif mode == "armed" then
        SetOverrideBinding(toggle, true, key, "INTERACTMOUSEOVER")
    else
        SetOverrideBinding(toggle, true, key, toggle:GetAttribute("interactaction"))
    end
end

local function WantedFMode()
    local name, c
    if ACMDB.plates then
        local f = PlateUnderReticle()
        if f then
            local r, g, b
            name, r, g, b = PlateInfo(f)
            c = Classify(r, g, b)
        end
    end
    local hasTarget = UnitExists("target")
    local aimedAlreadyTargeted = name and hasTarget and UnitName("target") == name and not UnitIsDead("target")
    if ACMDB.smartF and c == "friend" and name and name ~= "" and not aimedAlreadyTargeted then
        return "click"
    end
    if ACMDB.lootF and BINDING_NAME_INTERACTMOUSEOVER and not (c == "friend" or c == "hostile" or c == "player") then
        if not hasTarget or (not UnitIsDead("target") and not UnitIsFriend("player", "target")) then
            return "hover"
        end
    end
    return "action"
end

local function UpdateFBinding()
    if InCombatLockdown() or not ACMDB.interact then return end
    if GetTime() < hoverPauseUntil then return end   -- loot hover in progress
    local want = WantedFMode()
    if want ~= fMode then
        fMode = want
        SetFBind(want)
    end
end

-- World click: BUTTON1 has three states
--   "action": our spell button          "world": our button that frees the cursor
--   "native": unbound, so the next click is the game's own click (cursor is free)
-- Derived from the real binding each tick, so ALT / mode toggles cannot desync it.
local worldPause, leftWasDown = false, false

local function SetLeftBind(mode)
    if mode == "native" then
        SetOverrideBinding(toggle, true, "BUTTON1", nil)
    elseif mode == "world" then
        SetOverrideBindingClick(toggle, true, "BUTTON1", "ACM_World")
    elseif ACMDB.direct then
        SetOverrideBinding(toggle, true, "BUTTON1", "ACTIONBUTTON" .. tostring(ACMDB.left))
    else
        SetOverrideBindingClick(toggle, true, "BUTTON1", "ACM_Left")
    end
end

local function CurLeft()
    local cur = GetBindingAction("BUTTON1")
    if cur and cur ~= "" then
        if cur:find("ACM_World", 1, true) then return "world" end
        if cur:find("ACM_Left", 1, true) or cur:find("ACTIONBUTTON", 1, true) then return "action" end
    end
    return "native"
end

local function WantedLeft()
    if not ACMDB.worldClick then return "action" end
    if UnitAffectingCombat("player") then return "action" end
    if UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") then
        return "action"
    end
    if ACMDB.ownNames and UnitExists("mouseover") and UnitCanAttack("player", "mouseover") and not UnitIsDead("mouseover") then
        return "action"
    end
    if ACMDB.plates then
        local f = PlateUnderReticle()
        if f then
            local _, r, g, b = PlateInfo(f)
            local c = Classify(r, g, b)
            if c == "hostile" or c == "neutral" then return "action" end
            if (c == "friend" or c == "player") and not ACMDB.worldClickFriends then return "action" end
        end
    end
    return "world"
end

local function UpdateLeftBinding()
    if InCombatLockdown() then return end
    if FreeKeyDown() or GetTime() < hoverPauseUntil then return end
    local want = WantedLeft()
    if CurLeft() ~= want then SetLeftBind(want) end
end

-- First click of a world click: free the cursor at the reticle and let the next
-- left click through as the game's own click.
StartWorldClick = function()
    hoverPauseUntil = GetTime() + 4
    worldPause = true
    leftWasDown = true
    if not InCombatLockdown() then SetLeftBind("native") end
    if ACMDB.screenText ~= false then UIErrorsFrame:AddMessage("Cursor free - click again", 1, 1, 0.4) end
end

-- Called when F is pressed in "hover" mode: free the cursor (it reappears where the
-- reticle is) and make the next F press "Interact With Mouseover".
StartLootHover = function()
    hoverPauseUntil = GetTime() + 4
    lootKeyWasDown = true
    if not InCombatLockdown() then
        fMode = "armed"
        SetFBind("armed")
    end
    if ACMDB.screenText ~= false then UIErrorsFrame:AddMessage("Cursor free - press " .. tostring(ACMDB.interactKey) .. " again to interact", 1, 1, 0.4) end

end

-- every frame: while armed, notice the second F press and end the pause shortly after
local function LootPauseTick()
    if hoverPauseUntil == 0 then return end
    local now = GetTime()
    if now >= hoverPauseUntil then
        hoverPauseUntil = 0
        worldPause = false
        return
    end
    if worldPause then
        local ok, down = pcall(IsMouseButtonDown, "LeftButton")
        if ok and down and not leftWasDown then
            leftWasDown = true
            worldPause = false
            hoverPauseUntil = now + 0.5   -- let the real click happen, then resume
        elseif ok and not down then
            leftWasDown = false
        end
    end
    if fMode == "armed" then
        local ok, down = pcall(IsKeyDown, ACMDB.interactKey)
        if ok and down and not lootKeyWasDown then
            lootKeyWasDown = true
            hoverPauseUntil = now + 0.7
        elseif ok and not down then
            lootKeyWasDown = false
        end
    end
end

local hoverTestUntil, lastHoverGUID = 0, nil
local function HoverTick()
    if GetTime() > hoverTestUntil then return end
    local g = UnitGUID("mouseover")
    if g ~= lastHoverGUID then
        lastHoverGUID = g
        Say("hover test: mouseover = " .. tostring(g and UnitName("mouseover") or nil) ..
            "   (mouselooking: " .. tostring(IsMouselooking()) .. ")")
    end
end
local CheckMode
local fadedActive = true

local driver = CreateFrame("Frame")
driver:SetScript("OnUpdate", function(_, e)
    CheckMode()
    ACM.Fire("tick", e)
    HoverTick()
    KeyTestTick()
    LootPauseTick()
    if Active() then
        FadePlates(true)
        fadedActive = true
        fbElapsed = fbElapsed + e
        if fbElapsed > 0.1 then
            fbElapsed = 0
            UpdateFBinding()
            UpdateLeftBinding()
        end
        local why = Blocker()
        if why ~= lastWhy then
            lastWhy = why
            if why and why ~= "free key held" and why ~= "loot hover" then
                Say("cursor freed by: " .. why .. "   (settings: /acm)")
            end
        end
        if why then
            StopLook()
            cross:Hide()
        else
            StartLook()
            if ACMDB and ACMDB.crosshair then
                cross:Show()
                PlaceReticle()
                elapsed = elapsed + e
                if elapsed > 0.05 then
                    elapsed = 0
                    UpdateReticle()
                end
            else
                cross:Hide()
            end
        end
    else
        if fadedActive then FadePlates(false); fadedActive = false end
        lastWhy = nil
        if looking then StopLook() end
        if previewing and ACMDB and ACMDB.crosshair then
            cross:Show()
            PlaceReticle()
            local ps = ACM.previewState or "none"
            SetReticle(ps, ps ~= "none" and "Training Dummy" or "", ps ~= "none" and (ACM.previewHP or 0.65) or nil)
        else
            cross:Hide()
        end
    end
end)

local lastActiveSeen = false
CheckMode = function()
    local on = Active()
    if on == lastActiveSeen then return end
    lastActiveSeen = on
    if on then
        if ACMDB.screenText ~= false then UIErrorsFrame:AddMessage("Combat Evolved: ON", 0.3, 1, 0.3) end
    else
        if ACMDB.screenText ~= false then UIErrorsFrame:AddMessage("Combat Evolved: OFF (tab targeting)", 1, 0.6, 0.2) end
    end
    fMode = "action"
    hoverPauseUntil = 0
    worldPause = false
    OnModeChanged(on)
end
toggle:HookScript("PostClick", function() CheckMode() end)
ACM.CheckMode = CheckMode
ACM.Active = Active

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------
local pending = false

local function MacroFor(slot, atk)
    local m = ""
    if ACMDB.trustHover and ACMDB.autoTarget ~= false then
        m = "/target [target=mouseover,harm,nodead]\n"
    end
    if ACMDB.fallback and ACMDB.autoTarget ~= false then
        -- no target (or a dead one): grab the nearest enemy in front of you
        m = m .. "/targetenemy [noexists][dead]\n"
    end
    if atk then
        m = m .. "/startattack [harm,nodead]\n"
    end
    local src = ACMDB.barSource or "blizzard"
    if src == "bt4" then
        return m .. "/click BT4Button" .. slot
    elseif src == "dominos" then
        return m .. "/click DominosActionButton" .. slot
    elseif src == "elvui" then
        return m .. "/click ElvUI_Bar1Button" .. slot
    end
    -- default UI: while shapeshifted / in a stance the bonus bar sits on top of bar one
    return m .. "/click [bonusbar] BonusActionButton" .. slot .. "; ActionButton" .. slot
end

local function ApplyConfig()
    cross:SetScale(ACMDB.scale or 1)
    if InCombatLockdown() then
        pending = true
        return
    end
    pending = false
    local reg = (ACMDB.clickon == "up") and "LeftButtonUp" or "LeftButtonDown"
    leftBtn:RegisterForClicks(reg)
    rightBtn:RegisterForClicks(reg)
    baseMacro.ACM_Left = MacroFor(ACMDB.left, ACMDB.atkLeft)
    baseMacro.ACM_Right = MacroFor(ACMDB.right, ACMDB.atkRight)
    leftBtn:SetAttribute("macrotext", baseMacro.ACM_Left)
    rightBtn:SetAttribute("macrotext", baseMacro.ACM_Right)
    toggle:SetAttribute("leftslot", ACMDB.left)
    toggle:SetAttribute("rightslot", ACMDB.right)
    toggle:SetAttribute("direct", ACMDB.direct and 1 or 0)
    local iaction = ((ACMDB.interactMode == "mouseover" or ACMDB.trustHover) and BINDING_NAME_INTERACTMOUSEOVER ~= nil)
        and "INTERACTMOUSEOVER" or "INTERACTTARGET"
    toggle:SetAttribute("interactaction", iaction)
    toggle:SetAttribute("interactkey", ACMDB.interact and ACMDB.interactKey or "")
    toggle:SetAttribute("friendkey", ACMDB.friendKey or "")
    toggle:SetAttribute("autocombat", ACMDB.autoCombat and 1 or 0)
    toggle:SetAttribute("autoexit", ACMDB.autoExit and 1 or 0)
    ClearOverrideBindings(toggle)
    SetOverrideBindingClick(toggle, true, "BUTTON3", "ACM_Toggle")
    toggle:SetAttribute("acm", 0)
    toggle:SetAttribute("alt", 0)
    local fk = ACMDB.freeKey or "alt"
    if fk == "alt" or fk == "ctrl" or fk == "shift" then
        RegisterStateDriver(toggle, "acmalt", "[mod:" .. fk .. "] 1; 0")
    else
        UnregisterStateDriver(toggle, "acmalt")
    end
end

ACM.ApplyConfig = ApplyConfig
ACM.InCombat = function() return InCombatLockdown() end
ACM.ToggleMode = function() if not InCombatLockdown() then toggle:Click() end end

-------------------------------------------------------------------------------
-- Settings panel
-------------------------------------------------------------------------------
local panel = CreateFrame("Frame", "ACM_Options", UIParent)
panel.name = "Combat Evolved"
local controls = {}
local curPanel, curControls = panel, controls

local function MakeCheck(key, label, x, y, get, set)
    local cb = CreateFrame("CheckButton", "ACM_Check_" .. key, curPanel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", curPanel, "TOPLEFT", x, y)
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    cb.refresh = function() cb:SetChecked(get()) end
    curControls[#curControls + 1] = cb
    return cb
end

-- make a button wide enough for its text (never clipped), up to maxw
local function FitButton(b, minw, maxw)
    local fs = b.GetFontString and b:GetFontString()
    if fs and fs.GetStringWidth then
        local tw = fs:GetStringWidth()
        if tw and tw > 0 then
            b:SetWidth(math.min(maxw or 545, math.max(minw or 80, tw + 34)))
        end
    end
end
ACM.FitButton = FitButton

local function MakeButton(key, x, y, w, onclick)
    local b = CreateFrame("Button", "ACM_Btn_" .. key, curPanel, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", curPanel, "TOPLEFT", x, y)
    b:SetWidth(w)
    b:SetHeight(22)
    b:SetScript("OnClick", onclick)
    return b
end

local function MakeSlider(key, label, minv, maxv, step, x, y, get, set, fmt)
    local s = CreateFrame("Slider", "ACM_Slider_" .. key, curPanel, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", curPanel, "TOPLEFT", x, y)
    s:SetWidth(230)
    s:SetMinMaxValues(minv, maxv)
    s:SetValueStep(step)
    _G[s:GetName() .. "Low"]:SetText(string.format(fmt, minv))
    _G[s:GetName() .. "High"]:SetText(string.format(fmt, maxv))
    local text = _G[s:GetName() .. "Text"]
    local busy = false
    s.refresh = function()
        busy = true
        s:SetValue(get())
        text:SetText(label .. ": " .. string.format(fmt, get()))
        busy = false
    end
    s:SetScript("OnValueChanged", function(_, v)
        if busy then return end
        v = math.floor(v / step + 0.5) * step
        set(v)
        text:SetText(label .. ": " .. string.format(fmt, v))
    end)
    curControls[#curControls + 1] = s
    return s
end

local function CycleButton(key, x, y, w, textfn, cyclefn)
    local b
    b = MakeButton(key, x, y, w, function() cyclefn(); b.refresh() end)
    b.refresh = function() b:SetText(textfn()); FitButton(b, w, 545) end
    curControls[#curControls + 1] = b
    return b
end

local function MakeKeyButton(key, x, y, label, dbkey)
    local kb
    kb = MakeButton(key, x, y, 250, function()
        kb.capturing = true
        kb:SetText("Press a key (Esc cancel, Del clear)")
        FitButton(kb, 250, 545)
        kb:EnableKeyboard(true)
    end)
    kb:SetScript("OnKeyDown", function(self, k)
        if not self.capturing then return end
        if k == "LSHIFT" or k == "RSHIFT" or k == "LCTRL" or k == "RCTRL"
           or k == "LALT" or k == "RALT" then return end
        self.capturing = false
        self:EnableKeyboard(false)
        if k == "DELETE" or k == "BACKSPACE" then
            ACMDB[dbkey] = ""
            ApplyConfig()
        elseif k ~= "ESCAPE" then
            ACMDB[dbkey] = k
            ApplyConfig()
        end
        self.refresh()
    end)
    kb.refresh = function()
        local v = ACMDB[dbkey]
        kb:SetText(label .. ": " .. ((v and v ~= "") and v or "none"))
        FitButton(kb, 250, 545)
    end
    curControls[#curControls + 1] = kb
    return kb
end

local function Header(parent, x, y, text, w)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)
    local ln = parent:CreateTexture(nil, "ARTWORK")
    ln:SetTexture(1, 1, 1, 0.18)
    ln:SetHeight(1)
    ln:SetWidth(w or 270)
    ln:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    return fs
end
ACM.Header = Header
ACM.pageFrames = {}

function ACM.OpenPage(key)
    local f = ACM.pageFrames[key]
    if f then
        InterfaceOptionsFrame_OpenToCategory(f)
        InterfaceOptionsFrame_OpenToCategory(f)
    end
end

local function PageTitle(p, title, subtitle)
    local t = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", 16, -16)
    t:SetText(title)
    local ln = p:CreateTexture(nil, "ARTWORK")
    ln:SetTexture(1, 0.82, 0, 0.35)
    ln:SetHeight(1)
    ln:SetPoint("TOPLEFT", p, "TOPLEFT", 16, -40)
    ln:SetPoint("TOPRIGHT", p, "TOPRIGHT", -16, -40)
    if subtitle then
        local st = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        st:SetPoint("TOPLEFT", p, "TOPLEFT", 18, -46)
        st:SetText(subtitle)
    end
    return t
end

-- Flow-layout settings pages: every control gets an auto-placed description underneath.
local function EstLines(text, width)
    local perLine = math.max(20, math.floor(width / 5.4))
    local lines = 0
    for para in (text .. "\n"):gmatch("(.-)\n") do
        lines = lines + math.max(1, math.ceil(#para / perLine))
    end
    return lines
end

function ACM.NewPage(id, name, title, frame, subtitle)
    local p = frame or CreateFrame("Frame", "ACM_Options_" .. id, UIParent)
    if not frame then
        p.name = name
        p.parent = "Combat Evolved"
    end
    PageTitle(p, title, subtitle)
    ACM.pageFrames[id:lower()] = p
    local sf = CreateFrame("ScrollFrame", "ACM_Scroll_" .. id, p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", p, "TOPLEFT", 0, subtitle and -66 or -50)
    sf:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -28, 6)
    local content = CreateFrame("Frame", "ACM_Content_" .. id, sf)
    content:SetWidth(570)
    content:SetHeight(600)
    sf:SetScrollChild(content)
    local ctl = {}
    local L = { frame = p, content = content, controls = ctl, y = -4 }
    local W = 545

    local function with(fn, ...)
        local a, b = curPanel, curControls
        curPanel, curControls = content, ctl
        local ok, r = pcall(fn, ...)
        curPanel, curControls = a, b
        if not ok then error(r, 0) end
        return r
    end
    local function Desc(text, x)
        if not text or text == "" then return end
        x = x or 28
        local fs = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", x, L.y)
        fs:SetWidth(W - x)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        local h = fs.GetStringHeight and fs:GetStringHeight()
        if not h or h < 8 then h = EstLines(text, W - x) * 12 end
        L.y = L.y - h - 10
    end

    function L.Header(text)
        if L.y < -10 then L.y = L.y - 12 end
        Header(content, 8, L.y, text, W)
        L.y = L.y - 30
    end
    function L.Check(key, label, desc, get, set)
        local cb = with(MakeCheck, key, label, 4, L.y, get, set)
        L.y = L.y - 26
        Desc(desc, 32)
        return cb
    end
    function L.Cycle(key, textfn, desc, fn, w)
        local b = with(CycleButton, key, 14, L.y, w or 440, textfn, fn)
        L.y = L.y - 28
        Desc(desc, 18)
        return b
    end
    function L.Button(key, text, desc, fn, w)
        local b = with(MakeButton, key, 14, L.y, w or 220, fn)
        b:SetText(text)
        FitButton(b, w or 120, 545)
        L.y = L.y - 28
        Desc(desc, 18)
        return b
    end
    function L.Slider(key, label, desc, minv, maxv, step, get, set, fmt)
        L.y = L.y - 20
        local s = with(MakeSlider, key, label, minv, maxv, step, 26, L.y, get, set, fmt)
        s:SetWidth(320)
        L.y = L.y - 26
        Desc(desc, 26)
        return s
    end
    function L.Key(key, label, dbkey, desc)
        local b = with(MakeKeyButton, key, 14, L.y, label, dbkey)
        L.y = L.y - 28
        Desc(desc, 18)
        return b
    end
    function L.Note(text) Desc(text, 8) end
    function L.Gap(n) L.y = L.y - n end
    function L.Custom(h, fn)
        fn(content, L.y)
        L.y = L.y - h
    end
    function L.Finish(onShow, onHide)
        content:SetHeight(-L.y + 24)
        local function refresh()
            for i = 1, #ctl do ctl[i].refresh() end
        end
        p.refresh = refresh
        p:SetScript("OnShow", function()
            refresh()
            if onShow then onShow() end
        end)
        p:SetScript("OnHide", function() if onHide then onHide() end end)
        InterfaceOptions_AddCategory(p)
    end
    function L.Open()
        InterfaceOptionsFrame_OpenToCategory(p)
        InterfaceOptionsFrame_OpenToCategory(p)
    end
    return L
end

-------------------------------------------------------------------------------
-- API probe: reports which extra functions / CVars / bindings this client has
-------------------------------------------------------------------------------
local PROBE_FUNCS = {
    "SetCursorPosition", "MoveCursor", "SetMousePosition", "InteractUnit", "InteractMouseover",
    "InteractTarget", "TargetMouseover", "GetNamePlateForUnit", "GetNamePlates", "C_NamePlate",
    "C_Timer", "C_CVar", "C_Mouse", "C_Camera", "GetMouseFocus", "GetCursorPosition",
    "IsMouselooking", "MouselookStart", "SetMouseLook", "SetView", "GetCameraZoom",
    "SetCameraTarget", "UnitGUID", "UnitIsUnit", "TargetNearestEnemy", "TargetNearestFriend",
    "TargetNearestFriendPlayer", "AssistUnit", "GetUnitName", "UnitEffectiveLevel",
    "GetMouseOverUnit", "WorldFrame", "SetSoftTarget", "GetSoftTarget", "UnitSoftTarget",
}
local PROBE_CVARS = {
    "SoftTargetEnemy", "SoftTargetFriend", "SoftTargetInteract", "softTargetInteract",
    "SoftTargetNameplateEnemy", "test_cameraOverShoulder", "cameraOverShoulder", "CameraOverShoulder",
    "test_cameraDynamicPitch", "cameraSmoothStyle", "FoV", "mouseSpeed", "nameplateShowEnemies",
    "nameplateShowFriends", "nameplateMotion", "cameraDistanceMaxFactor", "cameraDistanceMax",
    "autoInteract", "rawMouseEnable", "enableMouseSpeed", "cameraYawSmoothSpeed", "cameraPitchSmoothSpeed",
    "actionCamera", "ActionCamera", "actionMode", "ActionMode", "actionCam", "ActionCombat", "combatMode",
    "mouselookMode", "cameraFollowStyle", "cameraView",
}
local PROBE_BINDINGS = {
    "INTERACTMOUSEOVER", "INTERACTTARGET", "TARGETMOUSEOVER", "TARGETNEARESTENEMY",
    "TARGETNEARESTFRIEND", "TARGETNEARESTFRIENDPLAYER", "TOGGLEAUTORUN", "ACTIONBUTTON1",
}
local PROBE_PATTERNS = { "cursor", "mouse", "interact", "plate", "soft", "reticle", "aim", "crosshair", "hover", "camera", "actioncam", "actionmode", "ascension", "combatmode" }

local function ProbeReport()
    local out = {}
    local function add(t) out[#out + 1] = t end
    local ver, build, bdate, toc = GetBuildInfo()
    add("Combat Evolved API probe")
    add("Client: " .. tostring(ver) .. " build " .. tostring(build) .. " (" .. tostring(bdate) .. ") interface " .. tostring(toc))
    add("Realm: " .. tostring(GetRealmName()))
    add("")
    add("-- Candidate globals --")
    for i = 1, #PROBE_FUNCS do
        local n = PROBE_FUNCS[i]
        add(n .. ": " .. type(_G[n]))
    end
    add("")
    add("-- Candidate CVars (n/a = not a CVar on this client) --")
    for i = 1, #PROBE_CVARS do
        local c = PROBE_CVARS[i]
        local ok, v = pcall(GetCVar, c)
        add(c .. " = " .. ((ok and v ~= nil) and tostring(v) or "n/a"))
    end
    add("")
    add("-- Binding names (nil = no such binding) --")
    for i = 1, #PROBE_BINDINGS do
        local n = PROBE_BINDINGS[i]
        add(n .. ": " .. tostring(_G["BINDING_NAME_" .. n]))
    end
    add("")
    add("-- Global functions whose names contain: " .. table.concat(PROBE_PATTERNS, ", ") .. " --")
    local hits = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and type(v) == "function" then
            local lk = k:lower()
            for i = 1, #PROBE_PATTERNS do
                if lk:find(PROBE_PATTERNS[i], 1, true) then hits[#hits + 1] = k; break end
            end
        end
    end
    table.sort(hits)
    add(table.concat(hits, ", "))
    add("")
    add("-- C_* tables --")
    local ct = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, 2) == "C_" and type(v) == "table" then ct[#ct + 1] = k end
    end
    table.sort(ct)
    add(#ct > 0 and table.concat(ct, ", ") or "(none)")
    add("")
    add("-- Members of interesting C_* tables (nameplate, mouse, cursor, camera, target, interact, cvar, unit, combat, action, soft) --")
    local keys = { "nameplate", "mouse", "cursor", "camera", "target", "interact", "cvar", "unit", "combat", "action", "soft" }
    for i = 1, #ct do
        local lname = ct[i]:lower()
        local interesting = false
        for j = 1, #keys do
            if lname:find(keys[j], 1, true) then interesting = true; break end
        end
        if interesting then
            local m = {}
            for k, v in pairs(_G[ct[i]]) do
                if type(k) == "string" then m[#m + 1] = k end
            end
            table.sort(m)
            local shown = {}
            for j = 1, math.min(#m, 80) do shown[j] = m[j] end
            add(ct[i] .. " (" .. #m .. "): " .. table.concat(shown, ", ") .. (#m > 80 and ", ..." or ""))
        end
    end
    add("")
    add("-- Addon-visible hints --")
    add("UnitExists('mouseover') now: " .. tostring(UnitExists("mouseover")))
    add("IsMouselooking now: " .. tostring(IsMouselooking()))
    return table.concat(out, "\n")
end

local probe
local function ShowProbe()
    if not probe then
        probe = CreateFrame("Frame", "ACM_ProbeFrame", UIParent)
        probe:SetWidth(580)
        probe:SetHeight(460)
        probe:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        probe:SetFrameStrata("DIALOG")
        probe:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        probe:EnableMouse(true)
        probe:SetMovable(true)
        probe:RegisterForDrag("LeftButton")
        probe:SetScript("OnDragStart", probe.StartMoving)
        probe:SetScript("OnDragStop", probe.StopMovingOrSizing)
        local t = probe:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        t:SetPoint("TOPLEFT", 20, -16)
        t:SetText("Combat Evolved API probe - click the text, Ctrl+A, Ctrl+C, then paste it to Claude")
        local close = CreateFrame("Button", nil, probe, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -4, -4)
        local scroll = CreateFrame("ScrollFrame", "ACM_ProbeScroll", probe, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 18, -42)
        scroll:SetPoint("BOTTOMRIGHT", -36, 16)
        local edit = CreateFrame("EditBox", "ACM_ProbeEdit", scroll)
        edit:SetMultiLine(true)
        edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(510)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        scroll:SetScrollChild(edit)
        probe.edit = edit
    end
    local text = ProbeReport()
    local _, lines = text:gsub("\n", "\n")
    probe.edit:SetText(text)
    probe.edit:SetHeight(math.max(380, (lines + 2) * 14))
    probe:Show()
end

-------------------------------------------------------------------------------
-- Sub-panel: reticle position + diagnostics
-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Settings pages (flow layout; every setting has a description)
-------------------------------------------------------------------------------
local function BuildMain()
    local L = ACM.NewPage("main", "Combat Evolved", "Combat Evolved", panel,
        "Middle mouse toggles the mode.  Hold the free-cursor key (ALT by default) = cursor at the reticle + normal clicks.  Changes to keys and buttons apply out of combat.")
    ACM.pages = ACM.pages or {}
    ACM.pages.main = L

    L.Header("Settings pages")
    L.Custom(36, function(c, y)
        local pages = {
            { "interaction", "Targeting & Plates" }, { "look", "Reticle Look" }, { "feedback", "Combat Feedback" },
            { "immersion", "Immersion" }, { "reticle", "Position & Tests" },
        }
        local x = 8
        for i, pg in ipairs(pages) do
            local a = curPanel
            curPanel = c
            local btn = MakeButton("page_" .. pg[1], x, y, 100, function() ACM.OpenPage(pg[1]) end)
            curPanel = a
            btn:SetText(pg[2])
            FitButton(btn, 90, 200)
            x = x + btn:GetWidth() + 6
        end
    end)

    L.Header("Mouse buttons")
    L.Check("atkL", "Auto-attack on left click", "Starts auto-attack when you left-click a target. Not used with Plain bindings.",
        function() return ACMDB.atkLeft end,
        function(v) ACMDB.atkLeft = v; ApplyConfig() end)
    L.Check("atkR", "Auto-attack on right click", "Same for the right button. Usually off so right click can be a utility spell.",
        function() return ACMDB.atkRight end,
        function(v) ACMDB.atkRight = v; ApplyConfig() end)
    L.Cycle("clickon",
        function() return "Clicks fire on mouse: " .. ACMDB.clickon end,
        "'down' casts the moment you press the button (snappiest). 'up' casts when you release it.",
        function() ACMDB.clickon = (ACMDB.clickon == "down") and "up" or "down"; ApplyConfig() end, 260)
    L.Cycle("target",
        function() return "Click with no target: grab nearest enemy: " .. (ACMDB.fallback and "on" or "off") end,
        "When you click and nothing is targeted, the game picks the nearest enemy in front of you first.",
        function() ACMDB.fallback = not ACMDB.fallback; ApplyConfig() end, 360)
    L.Slider("left", "Left click = action bar button", "Which button of your main action bar left click presses (1-12).",
        1, 12, 1, function() return ACMDB.left end,
        function(v) ACMDB.left = v; ApplyConfig() end, "%d")
    L.Slider("right", "Right click = action bar button", "Which button right click presses (1-12).",
        1, 12, 1, function() return ACMDB.right end,
        function(v) ACMDB.right = v; ApplyConfig() end, "%d")

    L.Cycle("barsource",
        function()
            local n = { blizzard = "default Blizzard bars (stance/form aware)", bt4 = "Bartender4 (BT4Button)",
                        dominos = "Dominos", elvui = "ElvUI bar 1" }
            return "Click buttons press: " .. n[ACMDB.barSource or "blizzard"]
        end,
        "Which action buttons left and right click press. The default follows shapeshift forms and stances (cat, bear, battle stance, stealth...) so clicks no longer drop your form. If you use a bar addon, pick it here so clicks use its buttons.",
        function()
            local o = { blizzard = "bt4", bt4 = "dominos", dominos = "elvui", elvui = "blizzard" }
            ACMDB.barSource = o[ACMDB.barSource or "blizzard"]
            ApplyConfig()
        end, 440)

    L.Header("Keys")
    L.Check("interact", "Interact key enabled", "While in the mode, this key interacts (talk, loot, use). See the Targeting & Plates page for the smart modes.",
        function() return ACMDB.interact end,
        function(v) ACMDB.interact = v; ApplyConfig() end)
    L.Cycle("freekey",
        function()
            local n = { alt = "ALT", ctrl = "CTRL", shift = "SHIFT", none = "disabled" }
            return "Hold to free the cursor: " .. n[ACMDB.freeKey or "alt"]
        end,
        "While you hold this key the cursor appears at the reticle and normal clicks work. Pick another key, or disabled, if you bind things like ALT+1 on your bars. With it disabled, use the interact double-press or the world click to reach the cursor.",
        function()
            local o = { alt = "ctrl", ctrl = "shift", shift = "none", none = "alt" }
            ACMDB.freeKey = o[ACMDB.freeKey or "alt"]
            ApplyConfig()
        end, 360)
    L.Key("ikey", "Interact key", "interactKey", "Click, then press the key you want. Delete clears it.")
    L.Key("fkey", "Target friendly player key", "friendKey", "Targets the next friendly player (or friendly unit, see the Targeting & Plates page).")

    L.Header("Reticle")
    L.Check("reticle", "Show reticle", "The aiming marker in the middle of the screen. Style and colors are on the Reticle Look page.",
        function() return ACMDB.crosshair end,
        function(v) ACMDB.crosshair = v end)
    L.Slider("scale", "Reticle size", "Overall size of the reticle and everything attached to it.",
        0.5, 2.5, 0.1, function() return ACMDB.scale end,
        function(v) ACMDB.scale = v; cross:SetScale(v) end, "%.1f")

    L.Header("Camera")
    L.Check("camset", "Set camera distance in action mode", "Moves the camera to the distance below when you enter the mode and back when you leave.",
        function() return ACMDB.camSet end,
        function(v)
            ACMDB.camSet = v
            if Active() and v then SetCamDist(ACMDB.camDist) end
        end)
    L.Slider("camdist", "Action camera distance", "0 is first person. Higher is further behind your character.",
        0, 20, 1, function() return ACMDB.camDist end,
        function(v)
            ACMDB.camDist = v
            if Active() and ACMDB.camSet then SetCamDist(v) end
        end, "%d")
    L.Custom(32, function(c, y)
        local a = curPanel
        curPanel = c
        local zi = MakeButton("zin", 14, y, 120, function() CameraZoomIn(3) end)
        zi:SetText("Zoom in")
        local zo = MakeButton("zout", 144, y, 120, function() CameraZoomOut(3) end)
        zo:SetText("Zoom out")
        curPanel = a
    end)
    L.Slider("zoomf", "Max zoom-out factor", "How far the camera is allowed to zoom out in total (game setting).",
        1, 4, 0.1, function() return tonumber(GetCVar("cameraDistanceMaxFactor")) or 1 end,
        function(v) SetCVar("cameraDistanceMaxFactor", v) end, "%.1f")
    if GetCVar("FoV") ~= nil then
        L.Slider("fov", "Field of view", "How wide the view is (game setting).",
            1, 2, 0.05, function() return tonumber(GetCVar("FoV")) or 1.57 end,
            function(v) SetCVar("FoV", v) end, "%.2f")
    end
    if GetCVar("mouseSpeed") ~= nil then
        L.Slider("mouse", "Mouse sensitivity", "Your normal mouse speed. The Immersion page can use a different one just for action mode.",
            0.5, 2, 0.1, function() return tonumber(GetCVar("mouseSpeed")) or 1 end,
            function(v) SetCVar("mouseSpeed", v) end, "%.1f")
    end
    L.Note("Over-the-shoulder camera offset is not supported by the 3.3.5a client. A short camera distance or first person works instead.")

    L.Header("Interface")
    L.Check("ui", "Free cursor while windows are open", "Bags, quest and vendor windows give you the mouse back automatically, and mouselook resumes when they close.",
        function() return ACMDB.ui end,
        function(v) ACMDB.ui = v end)
    L.Check("hud", "Fade chat, minimap and quest tracker in action mode", "Dims those parts of the screen while the mode is on. Action bars and unit frames are on the Immersion page.",
        function() return ACMDB.hudFade end,
        function(v)
            ACMDB.hudFade = v
            if Active() then FadeHUD(v) end
        end)
    L.Slider("hudalpha", "Opacity of the faded parts", "1 is fully visible, 0 is invisible.",
        0, 1, 0.05, function() return ACMDB.hudAlpha end,
        function(v)
            ACMDB.hudAlpha = v
            if Active() and ACMDB.hudFade then FadeHUD(true) end
        end, "%.2f")

    L.Header("Messages")
    L.Check("chat", "Chat messages", "Status lines in the chat window. Off keeps the addon silent (slash commands still answer).",
        function() return ACMDB.chat end, function(v) ACMDB.chat = v end)
    L.Check("screentext", "On-screen ON/OFF and cursor hints", "The big text when the mode switches, and 'Cursor free - click again'.",
        function() return ACMDB.screenText ~= false end, function(v) ACMDB.screenText = v end)
    L.Check("trace", "Log every click to chat (debug)", "Prints what each click did. Useful when something does not work. Turn off afterwards.",
        function() return ACMDB.trace end, function(v) ACMDB.trace = v end)
    L.Finish()
    panel.default = function() ACM.ResetDefaults() end
end

local function FModeState()
    if ACMDB.smartF and ACMDB.lootF then return 3 end
    if ACMDB.smartF then return 2 end
    if ACMDB.lootF then return 4 end
    return 1
end

local function ClickTargetState()
    if ACMDB.direct then return "plain" end
    if ACMDB.clickSelect then return "select" end
    if ACMDB.autoTarget ~= false then return "target" end
    return "fire"
end

local function BuildInteraction()
    local L = ACM.NewPage("interaction", "Targeting & Plates", "Targeting & nameplates")
    ACM.pages = ACM.pages or {}
    ACM.pages.interaction = L

    L.Header("What a click does to your target")
    L.Cycle("clicktarget",
        function()
            local n = {
                target = "Target the aimed enemy, then fire",
                select = "First click selects, next click fires",
                fire = "Fire only (never changes target)",
                plain = "Plain bindings (no targeting, no auto-attack)",
            }
            return "Click targeting: " .. n[ClickTargetState()]
        end,
        "Target + fire: one click targets the enemy under the reticle and casts at once.\nSelect first: left click on a NEW enemy only targets it; the next click fires (right click still targets + fires).\nFire only: clicks press your buttons on whatever you already have targeted.\nPlain bindings: the buttons are bound straight to the action bar with no extras.\nTargeting by click only works out of combat and needs nameplate aiming (below) or a working mouseover.",
        function()
            local order = { target = "select", select = "fire", fire = "plain", plain = "target" }
            local nxt = order[ClickTargetState()]
            ACMDB.direct = (nxt == "plain")
            ACMDB.clickSelect = (nxt == "select")
            ACMDB.autoTarget = (nxt == "target" or nxt == "select")
            ApplyConfig()
        end, 500)

    L.Header("Interact key and friendly targeting")
    L.Cycle("fmode",
        function()
            local names = {
                "F mode: Classic (interact with your target)",
                "F mode: Smart (target the NPC under the reticle, then interact)",
                "F mode: Smart + double-press loot",
                "F mode: Double-press loot only",
            }
            return names[FModeState()]
        end,
        "Classic: the key is the game's Interact With Target.\nSmart: aim at a friendly NPC (quest giver, vendor, guard); the first press targets it, the next interacts.\nDouble-press loot: with nothing aimed, the first press frees the cursor at the reticle and the second does the game's Interact With Mouseover - works on corpses, chests, herbs and ore.",
        function()
            local nxt = { 2, 3, 1, 1 }
            local st = nxt[FModeState()]
            ACMDB.smartF = (st == 2 or st == 3)
            ACMDB.lootF = (st == 3)
        end, 500)
    L.Check("gplayers", "Friendly-target key picks PLAYERS only", "Off lets it pick friendly NPCs too. Aiming at a player's nameplate always targets that player.",
        function() return ACMDB.gPlayersOnly ~= false end,
        function(v) ACMDB.gPlayersOnly = v end)

    L.Header("Clicking the world")
    L.Check("worldclick", "Left click with nothing aimed = the game's own click", "First click frees the cursor at the reticle, the second is a real click (select, loot, talk). Needed because the game ignores plain clicks while mouselooking. Aim at an enemy or be in combat and it casts again.",
        function() return ACMDB.worldClick end,
        function(v) ACMDB.worldClick = v end)
    L.Check("worldfriends", "...also when aiming at friendly NPCs / players", "Lets you click friendly units directly, for example to open a quest giver by mouse.",
        function() return ACMDB.worldClickFriends end,
        function(v) ACMDB.worldClickFriends = v end)

    L.Header("Nameplates and names")
    L.Check("plates", "Nameplate aiming", "Reads the nameplates to know what is under the reticle (colors, click targeting). Turn off only if a nameplate addon replaces the default ones.",
        function() return ACMDB.plates end,
        function(v) ACMDB.plates = v end)
    L.Cycle("namemode",
        function()
            local n = { plates = "Normal nameplates (use the two buttons below)",
                        names = "Plate names only (bars hidden)",
                        own = "Game's own names (plates OFF, aim via mouseover)" }
            return "Names above units: " .. n[ACMDB.nameMode or "plates"]
        end,
        "Normal: plates as the game draws them.\nNames only: every plate is hidden except its name text, aiming still works.\nGame's own names: the 3D names the game draws above units, always original color and size at any distance. This needs plates off, so aiming then depends on the game's mouseover (test with /acm hovertest).",
        function()
            local m = ACMDB.nameMode or "plates"
            m = (m == "plates") and "names" or ((m == "names") and "own" or "plates")
            ACMDB.nameMode = m
            ACMDB.namesOnly = (m == "names")
            ACMDB.ownNames = (m == "own")
            if Active() then
                ApplyOwnNames(m == "own")
                if m == "own" then
                    pcall(SetCVar, "nameplateShowEnemies", 0)
                    pcall(SetCVar, "nameplateShowFriends", 0)
                elseif ACMDB.plates then
                    PulseOn(PLATE_CVARS)
                end
            end
        end, 500)
    L.Cycle("hideenemy",
        function() return "Enemy nameplates in action mode: " .. (((ACMDB.enemyAlpha or 1) < 0.05) and "hidden" or "visible") end,
        "Hidden plates still work for aiming. With 'Names only' their name text stays.",
        function() ACMDB.enemyAlpha = ((ACMDB.enemyAlpha or 1) < 0.05) and 1 or 0 end, 360)
    L.Cycle("hidefriend",
        function() return "Friendly nameplates in action mode: " .. (((ACMDB.friendAlpha or 0) < 0.05) and "hidden" or "visible") end,
        "Same for friendly NPCs and players.",
        function() ACMDB.friendAlpha = ((ACMDB.friendAlpha or 0) < 0.05) and 1 or 0 end, 360)
    L.Cycle("namecolor",
        function()
            local m = ACMDB.nameColor or "game"
            local n = { game = "game's own", reaction = "reaction colors (red/yellow/green)", white = "white" }
            return "Names-only text color: " .. n[m]
        end,
        "Only for 'Plate names only'. If names look grey, choose reaction colors.",
        function()
            local m = ACMDB.nameColor or "game"
            ACMDB.nameColor = (m == "game") and "reaction" or ((m == "reaction") and "white" or "game")
        end, 360)
    L.Slider("namescale", "Names-only text size", "Only for 'Plate names only'. 1.00 is the game's own size.",
        0.6, 1.6, 0.05, function() return ACMDB.nameScale or 1 end, function(v) ACMDB.nameScale = v end, "%.2f")
    L.Finish()
end

local function BuildReticlePage()
    local L = ACM.NewPage("reticle", "Position & Tests", "Reticle position & diagnostics")
    ACM.pages = ACM.pages or {}
    ACM.pages.reticle = L

    L.Header("Where the reticle is drawn")
    L.Cycle("rmode",
        function() return "Reticle: " .. (ACMDB.reticleFollow and "at the mouse pointer" or "fixed (screen center + offset)") end,
        "At the pointer follows where the game froze the cursor when mouselook started. Fixed puts it at the screen center plus the offsets below, so ALT shows the cursor where the pointer froze, not at the reticle.",
        function() ACMDB.reticleFollow = not ACMDB.reticleFollow end, 360)
    L.Slider("rx", "Fixed reticle: horizontal offset", "Pixels right (+) or left (-) of the screen center.",
        -900, 900, 5, function() return ACMDB.reticleX or 0 end, function(v) ACMDB.reticleX = v end, "%d")
    L.Slider("ry", "Fixed reticle: vertical offset", "Pixels up (+) or down (-) from the screen center.",
        -540, 540, 5, function() return ACMDB.reticleY or 0 end, function(v) ACMDB.reticleY = v end, "%d")
    L.Button("rreset", "Reset offset", "A preview reticle is shown while this page is open.",
        function()
            ACMDB.reticleX, ACMDB.reticleY = 0, 0
            for i = 1, #L.controls do L.controls[i].refresh() end
        end, 140)

    L.Header("Mouseover")
    L.Check("trusthover", "Trust the game's mouseover while mouselooking", "Uses the unit under the pointer for colors and targeting if the game keeps updating it during mouselook. Check with /acm hovertest first.",
        function() return ACMDB.trustHover end,
        function(v) ACMDB.trustHover = v; ApplyConfig() end)

    L.Header("Leaving the mode")
    L.Slider("camnormal", "Camera distance when leaving action mode", "Where the camera goes back to (this client cannot report the old distance).",
        1, 15, 1, function() return ACMDB.camNormal or 10 end, function(v) ACMDB.camNormal = v end, "%d")

    L.Header("Diagnostics")
    L.Button("probe", "Run API probe", "Opens a report of extra functions, CVars and key bindings this client has. Copy it and send it back if you want me to check compatibility. Also /acm probe.",
        ShowProbe, 220)
    L.Finish(function() previewing = true end, function() previewing = false end)
end


-------------------------------------------------------------------------------
-- Reset to the built-in defaults (Interface Options > Defaults, or /acm reset)
-------------------------------------------------------------------------------
function ACM.ResetDefaults()
    for k, v in pairs(ACM_DEFAULTS) do ACMDB[k] = v end
    for k, v in pairs(ACM.moduleDefaults) do
        if type(v) == "table" then ACMDB[k] = {} else ACMDB[k] = v end
    end
    ACMDB.snd = nil
    ACMDB.nameMode = "plates"
    ACMDB.ownNames, ACMDB.namesOnly = false, false
    ACMDB.trace = false
    ACM.Fire("reset")
    ApplyConfig()
    for _, f in pairs(ACM.pageFrames) do
        if f.refresh then f.refresh() end
    end
end

-------------------------------------------------------------------------------
-- Events & slash
-------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        ACMDB = ACMDB or {}
        local fresh = (next(ACMDB) == nil)
        for k, v in pairs(ACM_DEFAULTS) do
            if ACMDB[k] == nil then ACMDB[k] = v end
        end
        for k, v in pairs(ACM.moduleDefaults) do
            if ACMDB[k] == nil then ACMDB[k] = v end
        end
        if fresh then
            ACMDB.ver = ACM_VERSION
        elseif (ACMDB.ver or 0) < ACM_VERSION then
            ACMDB.engine = nil
            ACMDB.interactMode = "target"
            ACMDB.reticleFollow = true
            ACMDB.fallback = false
            ACMDB.plates = true
            if not ACMDB.friendKey then ACMDB.friendKey = "G" end
            ACMDB.trace = false
            ACMDB.ver = ACM_VERSION
        end
        if ACMDB.savedNames and not Active() then ApplyOwnNames(false) end
        if ACMDB.nameMode == nil then
            ACMDB.nameMode = ACMDB.ownNames and "own" or (ACMDB.namesOnly and "names" or "plates")
        end
        ApplyConfig()
        BuildMain()
        BuildInteraction()
        BuildReticlePage()
        ACM.Fire("login")
    elseif event == "PLAYER_REGEN_ENABLED" and pending then
        ApplyConfig()
    end
end)

SLASH_ACTIONCOMBAT1 = "/acm"
SLASH_ACTIONCOMBAT2 = "/ce"
SLASH_ACTIONCOMBAT3 = "/combatevolved"
local function ACM_Slash(msg)
    local cmd, arg = msg:match("^(%S*)%s*(%S*)$")
    cmd = (cmd or ""):lower()
    arg = (arg or ""):lower()
    if cmd == "" or cmd == "config" or cmd == "options" then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    elseif cmd == "interact" and (arg == "target" or arg == "mouseover") then
        ACMDB.interactMode = arg
        ApplyConfig()
        Say("interact mode: " .. arg)
    elseif cmd == "friend" and tonumber(arg) and tonumber(arg) >= 0 and tonumber(arg) <= 1 then
        ACMDB.friendAlpha = tonumber(arg)
        Say("friendly nameplate opacity in action mode: " .. arg)
    elseif cmd == "keytest" then
        keytestUntil = GetTime() + 120
        ACM_diagUntil = GetTime() + 125
        keyDown = {}
        for i = 1, #TEST_EVENTS do pcall(kt.RegisterEvent, kt, TEST_EVENTS[i]) end
        Say("key test running for 2 minutes. Turn the mode on, then: (1) stand next to a corpse or NPC, target it, press " ..
            tostring(ACMDB.interactKey) .. "; (2) stand far away and press it again; (3) aim the reticle at a friendly NPC and press " ..
            tostring(ACMDB.friendKey) .. ". Every press prints what the game did.")
    elseif cmd == "hovertest" then
        hoverTestUntil = GetTime() + 60
        ACM_diagUntil = GetTime() + 65
        lastHoverGUID = "start"
        Say("hover test running for 60s. Turn the mode on (middle mouse), then sweep the camera over mobs/NPCs/corpses. If a line appears each time the unit under the reticle changes, hover works while mouselooking.")
    elseif cmd == "fmode" and (arg == "classic" or arg == "smart" or arg == "loot") then
        ACMDB.smartF = (arg == "smart" or arg == "loot")
        ACMDB.lootF = (arg == "loot")
        Say("F mode: " .. arg)
    elseif cmd == "worldclick" then
        ACMDB.worldClick = not ACMDB.worldClick
        Say("world click: " .. tostring(ACMDB.worldClick))
    elseif cmd == "interaction" then
        ACM.OpenPage("interaction")
    elseif (cmd == "look" or cmd == "feedback" or cmd == "immersion") and ACM.pages and ACM.pages[cmd] then
        ACM.pages[cmd].Open()
    elseif cmd == "reset" then
        ACM.ResetDefaults()
        Say("settings reset to defaults")
    elseif cmd == "probe" then
        ShowProbe()
    elseif cmd == "reticle" then
        ACM.OpenPage("reticle")
    elseif cmd == "trace" then
        ACMDB.trace = not ACMDB.trace
        Say("click trace: " .. tostring(ACMDB.trace))
    elseif cmd == "debug" then
        Say("mode active: " .. tostring(Active()) ..
            ", direct: " .. tostring(ACMDB.direct) .. ", clickon: " .. tostring(ACMDB.clickon))
        Say("mouselooking: " .. tostring(IsMouselooking()))
        Say("blocked by: " .. tostring(Blocker()))
        Say("target: " .. tostring(UnitExists("target") and UnitName("target") or nil) ..
            ", mouseover: " .. tostring(UnitExists("mouseover") and UnitName("mouseover") or nil))
        ScanChildren()
        local pf = PlateUnderReticle()
        local pn = pf and PlateInfo(pf) or nil
        Say("nameplates found: " .. #plates .. ", under reticle: " .. tostring(pn) ..
            ", enemy plates cvar: " .. tostring(GetCVar("nameplateShowEnemies")))
        Say("MMB -> " .. tostring(GetBindingAction("BUTTON3")))
        Say("LMB -> " .. tostring(GetBindingAction("BUTTON1")))
        Say("RMB -> " .. tostring(GetBindingAction("BUTTON2")))
        Say("interact: " .. tostring(ACMDB.interact) .. ", key " .. tostring(ACMDB.interactKey) ..
            " -> " .. tostring(toggle:GetAttribute("interactaction")))
        Say("F key now -> " .. tostring(GetBindingAction(ACMDB.interactKey or "F")))
        Say("friend key " .. tostring(ACMDB.friendKey) .. " -> " .. tostring(GetBindingAction(ACMDB.friendKey or "G")))
    else
        Say("/acm = settings panel.  /acm debug = print state, /acm trace = log every click, /acm friend <0-1> = friendly plate opacity, /acm reticle = reticle position panel, /acm probe = API probe, /acm hovertest = does mouseover update in mouselook?, /acm keytest = diagnose F and G, /acm interaction = F/G and nameplate options, /acm fmode classic|smart|loot, /acm worldclick = toggle left-click-at-reticle")
    end
end

SlashCmdList["ACTIONCOMBAT"] = function(msg)
    ACM_inSlash = true
    local ok, err = pcall(ACM_Slash, msg or "")
    ACM_inSlash = false
    if not ok then print("|cff66ccffCombat Evolved:|r error: " .. tostring(err)) end
end
