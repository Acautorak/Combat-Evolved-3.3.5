-- Combat Evolved: Immersion module (auto enter/exit, HUD fade, sensitivity profile, combat text, sounds)
local D = ACM.moduleDefaults
D.autoCombat = false
D.autoExit = true
D.autoMount = false
D.barFade = false
D.unitFade = false
D.fadeAlpha = 0.25
D.sensOn = false
D.sensVal = 0.8
D.fctOn = false
D.sndMode = false
D.sndLock = false
D.saved = nil

local BARS = { "MainMenuBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight", "ShapeshiftBarFrame", "PetActionBarFrame" }
local UNITS = { "PlayerFrame", "TargetFrame", "PetFrame" }

-- CVar profile (saved to the DB so a crash/disconnect can still restore) -----------
local FCT = { "floatingCombatTextCombatDamage", "floatingCombatTextCombatHealing" }

local function SaveCVar(k)
    ACMDB.saved = ACMDB.saved or {}
    if ACMDB.saved[k] == nil then ACMDB.saved[k] = GetCVar(k) end
end

local function ApplyProfile()
    if ACMDB.sensOn and GetCVar("mouseSpeed") ~= nil then
        SaveCVar("mouseSpeed")
        pcall(SetCVar, "mouseSpeed", ACMDB.sensVal)
    end
    if ACMDB.fctOn then
        for _, k in ipairs(FCT) do
            if GetCVar(k) ~= nil then SaveCVar(k); pcall(SetCVar, k, 1) end
        end
    end
end

local function RestoreProfile()
    if not ACMDB.saved then return end
    for k, v in pairs(ACMDB.saved) do
        if v ~= nil then pcall(SetCVar, k, v) end
    end
    ACMDB.saved = nil
end

-- HUD fade (out of combat, in mode) --------------------------------------------------
local orig, cur, applied = {}, 0, 0
local function Frames()
    local list = {}
    if ACMDB.barFade then for _, n in ipairs(BARS) do list[#list + 1] = n end end
    if ACMDB.unitFade then for _, n in ipairs(UNITS) do list[#list + 1] = n end end
    return list
end

local function ApplyFade(amount)   -- amount 0..1
    for _, n in ipairs(BARS) do
        local fr = _G[n]
        if fr then
            local on = ACMDB.barFade and amount > 0
            if on then
                if orig[n] == nil then orig[n] = fr:GetAlpha() end
                fr:SetAlpha(orig[n] * (1 - (1 - ACMDB.fadeAlpha) * amount))
            elseif orig[n] ~= nil then
                fr:SetAlpha(orig[n]); orig[n] = nil
            end
        end
    end
    for _, n in ipairs(UNITS) do
        local fr = _G[n]
        if fr then
            local on = ACMDB.unitFade and amount > 0
            if on then
                if orig[n] == nil then orig[n] = fr:GetAlpha() end
                fr:SetAlpha(orig[n] * (1 - (1 - ACMDB.fadeAlpha) * amount))
            elseif orig[n] ~= nil then
                fr:SetAlpha(orig[n]); orig[n] = nil
            end
        end
    end
end

local wasMounted, exitedForMount = false, false
local acc = 0
ACM.On("tick", function(dt)
    if not ACMDB then return end
    local want = (ACM.Active() and not UnitAffectingCombat("player") and (ACMDB.barFade or ACMDB.unitFade)) and 1 or 0
    if cur ~= want or cur ~= applied then
        cur = cur + (want - cur) * math.min(1, dt * 6)
        if math.abs(cur - want) < 0.01 then cur = want end
        ApplyFade(cur)
        applied = cur
    end
    acc = acc + dt
    if acc < 0.5 then return end
    acc = 0
    if ACMDB.autoMount and IsMounted and not InCombatLockdown() then
        local m = IsMounted() and true or false
        if m ~= wasMounted then
            wasMounted = m
            if m and ACM.Active() then
                exitedForMount = true
                ACM.ToggleMode()
            elseif not m and exitedForMount then
                exitedForMount = false
                if not ACM.Active() then ACM.ToggleMode() end
            end
        end
    end
end)

-- Sound cues: each event can use any of these built-in game sounds (or none)
local SOUNDS = {
    { "off", "Off" },
    { "igMainMenuOptionCheckBoxOn", "Click" },
    { "igMainMenuOptionCheckBoxOff", "Soft click" },
    { "igMainMenuOpen", "Menu open" },
    { "igMainMenuClose", "Menu close" },
    { "igSpellBookOpen", "Spellbook" },
    { "igBackPackOpen", "Backpack" },
    { "LOOTWINDOWCOINSOUND", "Coins" },
    { "igQuestLogOpen", "Quest log" },
    { "MapPing", "Ping" },
    { "RaidWarning", "Raid warning" },
    { "ReadyCheck", "Ready check" },
    { "igCreatureAggroSelect", "Enemy select" },
    { "igCreatureNeutralSelect", "Neutral select" },
    { "igCharacterNPCSelect", "Friendly select" },
    { "TellMessage", "Whisper" },
    { "AuctionWindowOpen", "Auction" },
}
local SOUND_NAME = {}
for _, v in ipairs(SOUNDS) do SOUND_NAME[v[1]] = v[2] end
local EVENTS = {
    { "modeOn",    "Mode turns on",              "Plays when you enter action mode.",                          "igMainMenuOpen" },
    { "modeOff",   "Mode turns off",             "Plays when you leave action mode.",                          "igMainMenuClose" },
    { "lockEnemy", "Reticle locks onto an enemy", "A tick as the reticle snaps onto something hostile (needs 'Lock-on animation' on the Reticle Look page).", "igMainMenuOptionCheckBoxOn" },
    { "lockFriend","Reticle locks onto a friendly", "Same for friendly NPCs and players, such as quest givers.",  "off" },
    { "hit",       "You hit something",          "Plays on every damage hit you land. Very frequent, so pick a quiet one.", "off" },
    { "crit",      "You land a critical hit",    "Plays on critical hits (instead of the normal hit sound).",  "off" },
    { "kill",      "You land a killing blow",    "Plays when you kill something.",                              "off" },
}
local lastPlayed = {}
function ACM.Sound(ev)
    local snd = ACMDB and ACMDB.snd and ACMDB.snd[ev]
    if not snd or snd == "off" then return end
    local now = GetTime()
    if lastPlayed[ev] and now - lastPlayed[ev] < 0.1 then return end
    lastPlayed[ev] = now
    pcall(PlaySound, snd)
end

ACM.OnLock = function(state)
    if state == "hostile" then ACM.Sound("lockEnemy")
    elseif state == "friend" then ACM.Sound("lockFriend") end
end

ACM.On("mode", function(active)
    if active then
        ApplyProfile()
        ACM.Sound("modeOn")
    else
        RestoreProfile()
        ACM.Sound("modeOff")
    end
end)

ACM.On("login", function()
    if ACMDB.saved and not ACM.Active() then RestoreProfile() end
    if type(ACMDB.snd) ~= "table" then
        -- first run of the sound system: carry over the old two tickboxes
        ACMDB.snd = {}
        for _, e in ipairs(EVENTS) do ACMDB.snd[e[1]] = e[4] end
        if not ACMDB.sndMode then ACMDB.snd.modeOn, ACMDB.snd.modeOff = "off", "off" end
        if not ACMDB.sndLock then ACMDB.snd.lockEnemy = "off" end
    end
    ACM.On("reset", function()
        ACMDB.snd = {}
        for _, e in ipairs(EVENTS) do ACMDB.snd[e[1]] = e[4] end
        ACMDB.snd.modeOn, ACMDB.snd.modeOff, ACMDB.snd.lockEnemy = "off", "off", "off"
    end)
    local P = ACM.NewPage("Immersion", "Immersion", "Immersion")
    ACM.pages = ACM.pages or {}
    ACM.pages.immersion = P

    P.Header("Automatic entering and leaving")
    P.Check("autocombat", "Enter action mode when combat starts", "Switches the mode on by itself the moment you enter combat, even mid-fight.",
        function() return ACMDB.autoCombat end,
        function(v) ACMDB.autoCombat = v; ACM.ApplyConfig() end)
    P.Check("autoexit", "Leave it again when combat ends", "Only if the mode was entered automatically; a mode you turned on yourself stays on.",
        function() return ACMDB.autoExit end,
        function(v) ACMDB.autoExit = v; ACM.ApplyConfig() end)
    P.Check("automount", "Leave on mounting, return on dismounting", "Handy for riding with the normal camera. Checked twice a second, out of combat only.",
        function() return ACMDB.autoMount end, function(v) ACMDB.autoMount = v end)

    P.Header("Hide the interface out of combat")
    P.Check("barfade", "Fade action bars", "Dims your action bars while you are in action mode and not fighting; they return in combat.",
        function() return ACMDB.barFade end, function(v) ACMDB.barFade = v end)
    P.Check("unitfade", "Fade player, target and pet frames", "Same for the unit frames.",
        function() return ACMDB.unitFade end, function(v) ACMDB.unitFade = v end)
    P.Slider("fadealpha", "Opacity when faded", "1 is fully visible, 0 is invisible.",
        0, 1, 0.05, function() return ACMDB.fadeAlpha end, function(v) ACMDB.fadeAlpha = v end, "%.2f")

    P.Header("Feel")
    P.Check("sens", "Separate mouse sensitivity in action mode", "Uses the sensitivity below while the mode is on, then restores yours.",
        function() return ACMDB.sensOn end,
        function(v)
            ACMDB.sensOn = v
            if ACM.Active() then if v then ApplyProfile() else RestoreProfile(); ApplyProfile() end end
        end)
    P.Slider("sensval", "Action-mode sensitivity", "Lower is slower and steadier for aiming.",
        0.5, 2, 0.1, function() return ACMDB.sensVal end,
        function(v) ACMDB.sensVal = v; if ACM.Active() and ACMDB.sensOn then pcall(SetCVar, "mouseSpeed", v) end end, "%.1f")
    P.Check("fct", "Floating combat text in action mode", "Turns on the game's damage and healing numbers while the mode is on, then restores your setting.",
        function() return ACMDB.fctOn end,
        function(v)
            ACMDB.fctOn = v
            if ACM.Active() then RestoreProfile(); ApplyProfile() end
        end)

    P.Header("Sound cues")
    P.Note("Click a button to change the sound; it plays as a preview. These are sounds that already ship with the game client.")
    for _, e in ipairs(EVENTS) do
        local ev, label, desc = e[1], e[2], e[3]
        P.Cycle("snd_" .. ev,
            function() return label .. ": " .. (SOUND_NAME[ACMDB.snd[ev] or "off"] or "Off") end,
            desc,
            function()
                local cur = ACMDB.snd[ev] or "off"
                local idx = 1
                for i, v in ipairs(SOUNDS) do if v[1] == cur then idx = i end end
                local nxt = SOUNDS[idx % #SOUNDS + 1][1]
                ACMDB.snd[ev] = nxt
                if nxt ~= "off" then pcall(PlaySound, nxt) end
            end, 320)
    end
    P.Note("Sensitivity and combat text are restored when you leave action mode, and at next login if the game closed while it was on.")
    P.Finish()
end)
