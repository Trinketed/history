---------------------------------------------------------------------------
-- TrinketedHistory: Core.lua
-- Arena match history tracking, VOD timestamp overlay, export/import
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local ARENA_ZONES = {
    ["Nagrand Arena"] = true,
    ["Blade's Edge Arena"] = true,
    ["Ruins of Lordaeron"] = true,
}

-- Spells only available via UNIT_SPELLCAST_SUCCEEDED (not in CLEU)
local API_ONLY_SPELLS = {
    [42292] = true,   -- PvP Trinket
    [59752] = true,   -- Every Man for Himself
}

local ADDON_NAME = "TrinketedHistory"
local DISPLAY_NAME = "Trinketed"
local PREP_BUFF = "Arena Preparation"
local ROW_HEIGHT = 34
local CLASS_COLORS = {
    ["Warrior"]     = "ffc79c6e",
    ["Paladin"]     = "fff58cba",
    ["Hunter"]      = "ffabd473",
    ["Rogue"]       = "fffff569",
    ["Priest"]      = "ffffffff",
    ["Shaman"]      = "ff0070de",
    ["Mage"]        = "ff69ccf0",
    ["Warlock"]     = "ff9482c9",
    ["Druid"]       = "ffff7d0a",
    ["Deathknight"] = "ffc41f3b",
}

-- Abbreviated spec names (used in comp keys and row display)
local SPEC_SHORT = {
    -- Warrior
    ["Arms"]            = "Arms",
    ["Fury"]            = "Fury",
    ["Protection"]      = "Prot",
    -- Paladin
    ["Holy"]            = "Holy",
    ["Retribution"]     = "Ret",
    -- Rogue
    ["Assassination"]   = "Assa",
    ["Combat"]          = "Combat",
    ["Subtlety"]        = "Sub",
    -- Priest
    ["Discipline"]      = "Disc",
    ["Shadow"]          = "Shadow",
    -- Death Knight
    ["Blood"]           = "Blood",
    ["Frost"]           = "Frost",
    ["Unholy"]          = "UH",
    -- Mage
    ["Arcane"]          = "Arc",
    ["Fire"]            = "Fire",
    -- Warlock
    ["Affliction"]      = "Aff",
    ["Demonology"]      = "Demo",
    ["Destruction"]     = "Destro",
    -- Shaman
    ["Elemental"]       = "Ele",
    ["Enhancement"]     = "Enh",
    ["Restoration"]     = "Resto",
    -- Hunter
    ["Beast Mastery"]   = "BM",
    ["Marksmanship"]    = "MM",
    ["Survival"]        = "Surv",
    -- Druid
    ["Balance"]         = "Bal",
    ["Feral"]           = "Feral",
}

-- Spell name → { class, spec } mapping for spec detection (Wrath-era talent spells)
local SPEC_SPELLS = {
    -- WARRIOR
    ["Mortal Strike"]       = { class = "Warrior",     spec = "Arms" },
    ["Bladestorm"]          = { class = "Warrior",     spec = "Arms" },
    ["Bloodthirst"]         = { class = "Warrior",     spec = "Fury" },
    ["Concussion Blow"]     = { class = "Warrior",     spec = "Protection" },
    ["Shockwave"]           = { class = "Warrior",     spec = "Protection" },
    ["Devastate"]           = { class = "Warrior",     spec = "Protection" },
    -- PALADIN
    ["Avenger's Shield"]    = { class = "Paladin",     spec = "Protection" },
    ["Holy Shock"]          = { class = "Paladin",     spec = "Holy" },
    ["Beacon of Light"]     = { class = "Paladin",     spec = "Holy" },
    ["Crusader Strike"]     = { class = "Paladin",     spec = "Retribution" },
    ["Divine Storm"]        = { class = "Paladin",     spec = "Retribution" },
    ["Repentance"]          = { class = "Paladin",     spec = "Retribution" },
    -- ROGUE
    ["Mutilate"]            = { class = "Rogue",       spec = "Assassination" },
    ["Cold Blood"]          = { class = "Rogue",       spec = "Assassination" },
    ["Killing Spree"]       = { class = "Rogue",       spec = "Combat" },
    ["Blade Flurry"]        = { class = "Rogue",       spec = "Combat" },
    ["Adrenaline Rush"]     = { class = "Rogue",       spec = "Combat" },
    ["Shadowstep"]          = { class = "Rogue",       spec = "Subtlety" },
    ["Hemorrhage"]          = { class = "Rogue",       spec = "Subtlety" },
    ["Shadow Dance"]        = { class = "Rogue",       spec = "Subtlety" },
    -- PRIEST
    ["Penance"]             = { class = "Priest",      spec = "Discipline" },
    ["Power Infusion"]      = { class = "Priest",      spec = "Discipline" },
    ["Pain Suppression"]    = { class = "Priest",      spec = "Discipline" },
    ["Circle of Healing"]   = { class = "Priest",      spec = "Holy" },
    ["Guardian Spirit"]     = { class = "Priest",      spec = "Holy" },
    ["Silence"]             = { class = "Priest",      spec = "Shadow" },
    ["Vampiric Touch"]      = { class = "Priest",      spec = "Shadow" },
    -- DEATHKNIGHT
    ["Heart Strike"]        = { class = "Deathknight", spec = "Blood" },
    ["Hysteria"]            = { class = "Deathknight", spec = "Blood" },
    ["Hungering Cold"]      = { class = "Deathknight", spec = "Frost" },
    ["Frost Strike"]        = { class = "Deathknight", spec = "Frost" },
    ["Howling Blast"]       = { class = "Deathknight", spec = "Frost" },
    ["Scourge Strike"]      = { class = "Deathknight", spec = "Unholy" },
    ["Bone Shield"]         = { class = "Deathknight", spec = "Unholy" },
    -- MAGE
    ["Arcane Barrage"]      = { class = "Mage",        spec = "Arcane" },
    ["Living Bomb"]         = { class = "Mage",        spec = "Fire" },
    ["Dragon's Breath"]     = { class = "Mage",        spec = "Fire" },
    ["Blast Wave"]          = { class = "Mage",        spec = "Fire" },
    ["Deep Freeze"]         = { class = "Mage",        spec = "Frost" },
    ["Ice Barrier"]         = { class = "Mage",        spec = "Frost" },
    -- WARLOCK
    ["Haunt"]               = { class = "Warlock",     spec = "Affliction" },
    ["Unstable Affliction"] = { class = "Warlock",     spec = "Affliction" },
    ["Metamorphosis"]       = { class = "Warlock",     spec = "Demonology" },
    ["Demonic Empowerment"] = { class = "Warlock",     spec = "Demonology" },
    ["Chaos Bolt"]          = { class = "Warlock",     spec = "Destruction" },
    ["Shadowfury"]          = { class = "Warlock",     spec = "Destruction" },
    -- SHAMAN
    ["Thunderstorm"]        = { class = "Shaman",      spec = "Elemental" },
    ["Elemental Mastery"]   = { class = "Shaman",      spec = "Elemental" },
    ["Feral Spirit"]        = { class = "Shaman",      spec = "Enhancement" },
    ["Shamanistic Rage"]    = { class = "Shaman",      spec = "Enhancement" },
    ["Stormstrike"]         = { class = "Shaman",      spec = "Enhancement" },
    ["Riptide"]             = { class = "Shaman",      spec = "Restoration" },
    ["Cleanse Spirit"]      = { class = "Shaman",      spec = "Restoration" },
    -- HUNTER
    ["Intimidation"]        = { class = "Hunter",      spec = "Beast Mastery" },
    ["The Beast Within"]    = { class = "Hunter",      spec = "Beast Mastery" },
    ["Chimera Shot"]        = { class = "Hunter",      spec = "Marksmanship" },
    ["Silencing Shot"]      = { class = "Hunter",      spec = "Marksmanship" },
    ["Explosive Shot"]      = { class = "Hunter",      spec = "Survival" },
    ["Wyvern Sting"]        = { class = "Hunter",      spec = "Survival" },
    -- DRUID
    ["Starfall"]            = { class = "Druid",       spec = "Balance" },
    ["Typhoon"]             = { class = "Druid",       spec = "Balance" },
    ["Moonkin Form"]        = { class = "Druid",       spec = "Balance" },
    ["Mangle (Cat)"]        = { class = "Druid",       spec = "Feral" },
    ["Mangle (Bear)"]       = { class = "Druid",       spec = "Feral" },
    ["Survival Instincts"]  = { class = "Druid",       spec = "Feral" },
    ["Berserk"]             = { class = "Druid",       spec = "Feral" },
    ["Swiftmend"]           = { class = "Druid",       spec = "Restoration" },
    ["Wild Growth"]         = { class = "Druid",       spec = "Restoration" },
    ["Tree of Life"]        = { class = "Druid",       spec = "Restoration" },
    -- Note: Nature's Swiftness excluded — shared between Druid Resto and Shaman Resto
}

-- Arena bracket teamSize → GetPersonalRatedInfo() bracketIndex mapping
local BRACKET_TO_RATED_INDEX = { [2] = 1, [3] = 2, [5] = 3 }

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local debugMode = false
local inArena = false
local gameStarted = false
local hadPrepBuff = false
local currentGame = nil
local guidToPlayer = {}   -- GUID → { team = "friendly"|"enemy", index = N }
local snapshotTicker = nil -- periodic re-snapshot timer handle
local needsReload = false  -- set after a game is saved, triggers reload on next queue
local pendingSave = nil    -- set to "WIN"/"LOSS" when match ends, cleared after save
local UpdateOverlayVisibility  -- forward declaration

-- Sessions tab state
local activeTab = "sessions"
local sessionCollapsed = {}         -- sessionStartTime → boolean
local sessionHeaderPool = {}
local sessionMatchRowPool = {}
local SESSION_HEADER_HEIGHT = 38

-- Shared UI state for options-panel-embedded tabs
local ui = {}           -- History tab UI references (including stats sub-tab)
local lastFilteredList = {}  -- populated by RefreshHistory, consumed by RefreshStats

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local function dbg(...)
    if not debugMode then return end
    print("|cffff9900" .. DISPLAY_NAME .. " [DEBUG]:|r", ...)
end

---------------------------------------------------------------------------
-- Timestamp Overlay (shown only while in queue, top center, scale-independent)
---------------------------------------------------------------------------
-- Target physical size: 260x20 pixels at 1.0 effective scale
local OVERLAY_WIDTH = 260
local OVERLAY_HEIGHT = 20
local OVERLAY_FONT_SIZE = 14

local overlay = CreateFrame("Frame", "TrinketedTimestampFrame", UIParent)
overlay:SetFrameStrata("HIGH")
overlay:Hide()  -- hidden by default, shown only when queued

local bg = overlay:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetColorTexture(0, 0, 0, 1)

-- OCR anchor markers — bright solid blocks flanking the timestamp
-- Left marker: magenta | Right marker: cyan — easy for OCR to locate
local MARKER_WIDTH = 4
local leftMarker = overlay:CreateTexture(nil, "ARTWORK")
leftMarker:SetColorTexture(1, 0, 1, 1)   -- magenta
leftMarker:SetPoint("RIGHT", overlay, "LEFT", 0, 0)

local rightMarker = overlay:CreateTexture(nil, "ARTWORK")
rightMarker:SetColorTexture(0, 1, 1, 1)  -- cyan
rightMarker:SetPoint("LEFT", overlay, "RIGHT", 0, 0)

local tsText = overlay:CreateFontString(nil, "OVERLAY")
tsText:SetPoint("CENTER")
tsText:SetTextColor(1, 1, 1, 1)

-- Adjust size and font to compensate for UI scale, so the overlay
-- always occupies the same physical screen pixels regardless of scale.
local function UpdateOverlayScale()
    local effectiveScale = UIParent:GetEffectiveScale()
    if effectiveScale <= 0 then effectiveScale = 1 end
    local inv = 1 / effectiveScale
    overlay:SetSize(OVERLAY_WIDTH * inv, OVERLAY_HEIGHT * inv)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOP", UIParent, "TOP", 0, 0)
    tsText:SetFont("Fonts\\FRIZQT__.TTF", math.floor(OVERLAY_FONT_SIZE * inv + 0.5), "OUTLINE")
    leftMarker:SetSize(MARKER_WIDTH * inv, OVERLAY_HEIGHT * inv)
    rightMarker:SetSize(MARKER_WIDTH * inv, OVERLAY_HEIGHT * inv)
end
UpdateOverlayScale()

-- Re-adjust if UI scale changes mid-session (e.g., Display settings)
overlay:RegisterEvent("UI_SCALE_CHANGED")
overlay:SetScript("OnEvent", function()
    UpdateOverlayScale()
end)

-- Sync GetTime() (session-relative, fractional) with time() (epoch, integer)
-- so we can display epoch timestamps with millisecond precision
local tsBaseEpoch = time()
local tsBaseGetTime = GetTime()

overlay:SetScript("OnUpdate", function(self, dt)
    local now = tsBaseEpoch + (GetTime() - tsBaseGetTime)
    local secs = math.floor(now)
    local ms = math.floor((now - secs) * 1000)
    tsText:SetText(string.format("%d.%03d", secs, ms))
end)

-- Separate always-running frame to periodically check visibility
-- (overlay's OnUpdate only fires when shown, so we need an independent ticker)
local visTicker = CreateFrame("Frame")
local visCheckElapsed = 0
visTicker:SetScript("OnUpdate", function(self, dt)
    visCheckElapsed = visCheckElapsed + dt
    if visCheckElapsed >= 2 then
        visCheckElapsed = 0
        UpdateOverlayVisibility()
    end
end)

-- Check queue/prep status and show/hide overlay accordingly.
-- Visible when: in queue, waiting for confirm, or in arena prep room.
-- Hidden when: game is active, or not queued at all.
UpdateOverlayVisibility = function()
    -- Always hide during active game
    if gameStarted then
        overlay:Hide()
        return
    end
    -- Show in arena prep room
    if inArena and hadPrepBuff then
        overlay:Show()
        return
    end
    -- Show if queued or confirming
    for i = 1, GetMaxBattlefieldID() do
        local status = GetBattlefieldStatus(i)
        if status == "queued" or status == "confirm" then
            overlay:Show()
            return
        end
    end
    overlay:Hide()
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function FormatClassName(class)
    if not class then return nil end
    return class:sub(1, 1):upper() .. class:sub(2):lower()
end

local function HasPrepBuff()
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if name == PREP_BUFF then return true end
    end
    return false
end

local function StripRealm(name)
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

-- Snapshot all bracket ratings: returns { [1]=rating, [2]=rating, [3]=rating }
local function SnapshotAllRatings()
    if not GetPersonalRatedInfo then return nil end
    local ratings = {}
    for i = 1, 3 do
        local rating = GetPersonalRatedInfo(i)
        ratings[i] = rating or 0
    end
    dbg("SnapshotAllRatings:", ratings[1], ratings[2], ratings[3])
    return ratings
end

local function ResetGameState()
    dbg("ResetGameState()")
    gameStarted = false
    hadPrepBuff = false
    pendingSave = nil
    guidToPlayer = {}
    -- Stop periodic re-snapshot ticker if running
    if snapshotTicker then
        snapshotTicker:Cancel()
        snapshotTicker = nil
    end
    currentGame = {
        startTime = nil,
        endTime = nil,
        startTimeExact = nil,  -- GetTime() when game starts (for CLEU ms offsets)
        map = GetRealZoneText(),
        enemyComp = {},
        result = nil,
        friendlyTeam = {},
        enemyTeam = {},
        cleu = {},             -- captured combat log events
        ratingsBefore = nil,  -- { [1]=2v2, [2]=3v3, [3]=5v5 } snapshot before game
        bracket = nil,
        ratingBefore = nil,
        ratingAfter = nil,
        ratingChange = nil,
        enemyMMR = nil,
    }
end

local function SaveGame(result)
    dbg("SaveGame() called with result:", result)
    if not currentGame or not currentGame.startTime then
        dbg("SaveGame() aborted — no currentGame or startTime")
        return
    end

    currentGame.endTime = time()
    currentGame.result = result

    -- Capture post-game rating: snapshot all brackets and compare to before
    if currentGame.ratingsBefore then
        local ratingsAfter = SnapshotAllRatings()
        if ratingsAfter then
            -- Find which bracket changed
            for i = 1, 3 do
                local before = currentGame.ratingsBefore[i] or 0
                local after = ratingsAfter[i] or 0
                if before > 0 and after > 0 and before ~= after then
                    local bracketNames = { "2v2", "3v3", "5v5" }
                    currentGame.bracket = bracketNames[i]
                    currentGame.ratingBefore = before
                    currentGame.ratingAfter = after
                    currentGame.ratingChange = after - before
                    dbg("  Rating detected via bracket", bracketNames[i], ":", before, "→", after, "(change:", currentGame.ratingChange .. ")")
                    break
                end
            end
        end
    end
    -- Fallback: try GetBattlefieldScore for ratingChange from scoreboard
    if not currentGame.ratingChange and GetBattlefieldScore then
        local playerName = StripRealm(UnitName("player"))
        local numScores = GetNumBattlefieldScores and GetNumBattlefieldScores() or 0
        for si = 1, numScores do
            local name, _, _, _, _, _, _, _, _, _, _, bgRating, ratingChange = GetBattlefieldScore(si)
            if name and StripRealm(name) == playerName and ratingChange and ratingChange ~= 0 then
                currentGame.ratingBefore = currentGame.ratingBefore or (bgRating or 0)
                currentGame.ratingChange = ratingChange
                currentGame.ratingAfter = (currentGame.ratingBefore or 0) + ratingChange
                dbg("  Rating (scoreboard fallback):", currentGame.ratingBefore, "change:", ratingChange)
                break
            end
        end
    end

    -- Capture enemy team MMR from GetBattlefieldTeamInfo
    if GetBattlefieldTeamInfo then
        local playerFaction = GetBattlefieldArenaFaction() or 0
        local enemyFaction = (playerFaction == 0) and 1 or 0
        local _, _, _, enemyMMR = GetBattlefieldTeamInfo(enemyFaction)
        if enemyMMR and enemyMMR > 0 then
            currentGame.enemyMMR = enemyMMR
            dbg("  Enemy MMR:", enemyMMR)
        end
    end

    -- Capture per-player ratings from the scoreboard
    if GetBattlefieldScore and GetNumBattlefieldScores then
        local playerFaction = GetBattlefieldArenaFaction()
        local numScores = GetNumBattlefieldScores() or 0
        for si = 1, numScores do
            local name, _, _, _, _, faction, _, _, _, _, _, bgRating, ratingChange, preMatchMMR, mmrChange = GetBattlefieldScore(si)
            if name then
                local cleanName = StripRealm(name)
                -- Match scoreboard entries to our tracked players by name
                if faction ~= playerFaction then
                    -- Enemy player
                    for _, p in ipairs(currentGame.enemyTeam) do
                        if p.name == cleanName then
                            p.rating = bgRating
                            p.ratingChange = ratingChange
                            p.mmr = preMatchMMR
                            dbg("  Enemy scoreboard:", cleanName, "rating=" .. tostring(bgRating), "change=" .. tostring(ratingChange), "mmr=" .. tostring(preMatchMMR))
                            break
                        end
                    end
                else
                    -- Friendly player
                    for _, p in ipairs(currentGame.friendlyTeam) do
                        if p.name == cleanName then
                            p.rating = bgRating
                            p.ratingChange = ratingChange
                            p.mmr = preMatchMMR
                            dbg("  Friendly scoreboard:", cleanName, "rating=" .. tostring(bgRating), "change=" .. tostring(ratingChange), "mmr=" .. tostring(preMatchMMR))
                            break
                        end
                    end
                end
            end
        end
    end

    dbg("  startTime:", currentGame.startTime, "endTime:", currentGame.endTime)
    dbg("  enemyComp:", table.concat(currentGame.enemyComp, ", "))

    table.insert(TrinketedHistoryDB.games, {
        startTime = currentGame.startTime,
        endTime = currentGame.endTime,
        map = currentGame.map,
        enemyComp = currentGame.enemyComp,
        result = currentGame.result,
        playerName = StripRealm(UnitName("player")),
        friendlyTeam = currentGame.friendlyTeam,
        enemyTeam = currentGame.enemyTeam,
        bracket = currentGame.bracket,
        ratingBefore = currentGame.ratingBefore,
        ratingAfter = currentGame.ratingAfter,
        ratingChange = currentGame.ratingChange,
        enemyMMR = currentGame.enemyMMR,
        cleu = currentGame.cleu,
    })

    -- Flush combat log between games
    LoggingCombat(false)
    LoggingCombat(true)
    dbg("Combat log flushed")

    UpdateOverlayVisibility()

    local count = #TrinketedHistoryDB.games
    local ratingStr = ""
    if currentGame.ratingChange then
        local sign = currentGame.ratingChange >= 0 and "+" or ""
        local color = currentGame.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
        ratingStr = " " .. color .. "(" .. sign .. currentGame.ratingChange .. " rating, " ..
            (currentGame.ratingBefore or "?") .. "→" .. (currentGame.ratingAfter or "?") .. ")|r"
        if currentGame.enemyMMR and currentGame.enemyMMR > 0 then
            ratingStr = ratingStr .. " |cff888888vs " .. currentGame.enemyMMR .. " MMR|r"
        end
    end
    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Game #" .. count .. " recorded — " .. result .. ratingStr)

    needsReload = true

    ResetGameState()
end

local function SnapshotEnemyTeam()
    if not currentGame then return end
    local seen = {}
    for _, p in ipairs(currentGame.enemyTeam) do
        seen[p.name] = true
    end
    -- Also maintain enemyComp for backward compat
    local seenClass = {}
    for _, class in ipairs(currentGame.enemyComp) do
        seenClass[class] = true
    end
    for i = 1, 5 do
        local unit = "arena" .. i
        local name = StripRealm(UnitName(unit))
        local _, className = UnitClass(unit)
        if name and className then
            local formatted = FormatClassName(className)
            dbg("  " .. unit .. ":", name, formatted)
            if not seen[name] then
                local race = UnitRace(unit)
                table.insert(currentGame.enemyTeam, { name = name, class = formatted, race = race })
                seen[name] = true
            end
            if formatted and not seenClass[formatted] then
                table.insert(currentGame.enemyComp, formatted)
                seenClass[formatted] = true
            end
            -- Track GUID for combat log spec detection
            local guid = UnitGUID(unit)
            if guid then
                local idx = #currentGame.enemyTeam
                -- Find this player's index
                for j, p in ipairs(currentGame.enemyTeam) do
                    if p.name == name then idx = j; break end
                end
                guidToPlayer[guid] = { team = "enemy", index = idx }
                dbg("  GUID mapped:", guid, "→ enemy[" .. idx .. "]", name)
            end
            -- Try GetArenaOpponentSpec API for immediate spec detection
            if GetArenaOpponentSpec and GetSpecializationInfoByID then
                local specID = GetArenaOpponentSpec(i)
                if specID and specID > 0 then
                    local _, specName = GetSpecializationInfoByID(specID)
                    if specName then
                        for j, p in ipairs(currentGame.enemyTeam) do
                            if p.name == name and not p.spec then
                                p.spec = specName
                                dbg("  Spec via API:", name, "=", specName)
                            end
                        end
                    end
                end
            end
        end
    end
    dbg("SnapshotEnemyTeam() result:", #currentGame.enemyTeam, "players")
end

local function SnapshotFriendlyTeam()
    if not currentGame then return end
    local seen = {}
    for _, p in ipairs(currentGame.friendlyTeam) do
        seen[p.name] = true
    end

    -- Helper to track GUID after adding a player
    local function trackGUID(unit, name)
        local guid = UnitGUID(unit)
        if guid and name then
            for j, p in ipairs(currentGame.friendlyTeam) do
                if p.name == name then
                    guidToPlayer[guid] = { team = "friendly", index = j }
                    dbg("  GUID mapped:", guid, "→ friendly[" .. j .. "]", name)
                    break
                end
            end
        end
    end

    -- Player themselves
    local playerName = StripRealm(UnitName("player"))
    local _, playerClass = UnitClass("player")
    if playerName and playerClass and not seen[playerName] then
        local race = UnitRace("player")
        table.insert(currentGame.friendlyTeam, { name = playerName, class = FormatClassName(playerClass), race = race })
        seen[playerName] = true
    end
    trackGUID("player", playerName)

    -- Party members
    for i = 1, 4 do
        local unit = "party" .. i
        local name = StripRealm(UnitName(unit))
        local _, className = UnitClass(unit)
        if name and className and not seen[name] then
            local race = UnitRace(unit)
            table.insert(currentGame.friendlyTeam, { name = name, class = FormatClassName(className), race = race })
            seen[name] = true
        end
        trackGUID(unit, name)
    end
    dbg("SnapshotFriendlyTeam() result:", #currentGame.friendlyTeam, "players")
end

-- Assign detected spec to a player entry (by GUID or by name+unit)
local function AssignSpec(guid, spellName)
    local specInfo = SPEC_SPELLS[spellName]
    if not specInfo or not currentGame then return end

    local ref = guidToPlayer[guid]
    if not ref then return end

    local team = (ref.team == "friendly") and currentGame.friendlyTeam or currentGame.enemyTeam
    local player = team[ref.index]
    if not player then return end

    -- Validate class matches (e.g., don't assign Warrior spec to a Mage)
    if player.class and player.class ~= specInfo.class then return end

    if not player.spec then
        player.spec = specInfo.spec
        dbg("Spec detected:", player.name, "=", specInfo.spec, "(from", spellName .. ")")
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r Spec detected: " ..
            "|c" .. (CLASS_COLORS[player.class] or "ffffffff") .. player.name .. "|r" ..
            " = " .. specInfo.spec)
    end
end

-- Discover a player from a combat log GUID by checking arena/party units.
-- If found and not already tracked, adds them to the appropriate team.
local function DiscoverPlayerByGUID(guid)
    if not guid or not currentGame then return end
    if guidToPlayer[guid] then return end  -- already known

    -- Check enemy arena units
    for i = 1, 5 do
        local unit = "arena" .. i
        local unitGUID = UnitGUID(unit)
        if unitGUID == guid then
            local name = StripRealm(UnitName(unit))
            local _, className = UnitClass(unit)
            if name and className then
                local formatted = FormatClassName(className)
                -- Check if already in enemy team by name
                local found = false
                for j, p in ipairs(currentGame.enemyTeam) do
                    if p.name == name then
                        -- Already have the player, just map the GUID
                        guidToPlayer[guid] = { team = "enemy", index = j }
                        dbg("GUID discovery: mapped existing enemy", name, "→ enemy[" .. j .. "]")
                        found = true
                        break
                    end
                end
                if not found then
                    local race = UnitRace(unit)
                    table.insert(currentGame.enemyTeam, { name = name, class = formatted, race = race })
                    local idx = #currentGame.enemyTeam
                    guidToPlayer[guid] = { team = "enemy", index = idx }
                    -- Also update enemyComp
                    local seenClass = {}
                    for _, c in ipairs(currentGame.enemyComp) do seenClass[c] = true end
                    if formatted and not seenClass[formatted] then
                        table.insert(currentGame.enemyComp, formatted)
                    end
                    dbg("GUID discovery: NEW enemy", name, formatted, "→ enemy[" .. idx .. "]")
                    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Discovered enemy: " ..
                        "|c" .. (CLASS_COLORS[formatted] or "ffffffff") .. name .. "|r")
                end
                -- Try GetArenaOpponentSpec API
                if GetArenaOpponentSpec and GetSpecializationInfoByID then
                    local specID = GetArenaOpponentSpec(i)
                    if specID and specID > 0 then
                        local _, specName = GetSpecializationInfoByID(specID)
                        if specName then
                            for j, p in ipairs(currentGame.enemyTeam) do
                                if p.name == name and not p.spec then
                                    p.spec = specName
                                    dbg("  Spec via API (discovery):", name, "=", specName)
                                end
                            end
                        end
                    end
                end
            end
            return
        end
    end

    -- Check friendly party units (in case we missed someone)
    local playerGUID = UnitGUID("player")
    if guid == playerGUID then
        local name = StripRealm(UnitName("player"))
        if name then
            for j, p in ipairs(currentGame.friendlyTeam) do
                if p.name == name then
                    guidToPlayer[guid] = { team = "friendly", index = j }
                    dbg("GUID discovery: mapped player", name, "→ friendly[" .. j .. "]")
                    return
                end
            end
        end
        return
    end
    for i = 1, 4 do
        local unit = "party" .. i
        local unitGUID = UnitGUID(unit)
        if unitGUID == guid then
            local name = StripRealm(UnitName(unit))
            if name then
                for j, p in ipairs(currentGame.friendlyTeam) do
                    if p.name == name then
                        guidToPlayer[guid] = { team = "friendly", index = j }
                        dbg("GUID discovery: mapped party", name, "→ friendly[" .. j .. "]")
                        return
                    end
                end
            end
            return
        end
    end
end

-- Periodic re-snapshot: catches enemies who weren't visible at initial snapshot
-- (e.g., stealthed rogues who become arena1/arena2 units after unstealthing)
local function StartSnapshotTicker()
    if snapshotTicker then return end  -- already running
    snapshotTicker = C_Timer.NewTicker(2, function()
        if not inArena or not gameStarted or not currentGame then
            -- Game ended or left arena, stop the ticker
            if snapshotTicker then
                snapshotTicker:Cancel()
                snapshotTicker = nil
            end
            return
        end
        SnapshotEnemyTeam()
    end)
    dbg("Snapshot ticker started (every 2s)")
end

local function StopSnapshotTicker()
    if snapshotTicker then
        snapshotTicker:Cancel()
        snapshotTicker = nil
        dbg("Snapshot ticker stopped")
    end
end

---------------------------------------------------------------------------
-- History Filters
---------------------------------------------------------------------------
local filters = {
    friendlyComps = {},   -- table of compKey = true for selected player comps (empty = all)
    partners = {},        -- table of name = true for selected partners (empty = all)
    enemyComps = {},      -- table of compKey = true for selected enemy comps (empty = all)
    enemyPlayers = {},    -- table of name = true for selected enemy players (empty = all)
    enemyRaces = {},      -- table of race = true for selected enemy races (empty = all)
    result = nil,
}

-- Build a sorted slash-separated comp string from a team table
-- Includes spec abbreviation when available: "Arms Warrior/Disc Priest"
local function GetCompKey(team)
    if not team or #team == 0 then return nil end
    local entries = {}
    for _, p in ipairs(team) do
        local label = p.class or "?"
        if p.spec and SPEC_SHORT[p.spec] then
            label = SPEC_SHORT[p.spec] .. " " .. label
        end
        table.insert(entries, label)
    end
    table.sort(entries)
    return table.concat(entries, "/")
end

local function GameMatchesFilters(game)
    if filters.result and game.result ~= filters.result then
        return false
    end
    -- Player comp filter (multi-select)
    if next(filters.friendlyComps) then
        local comp = GetCompKey(game.friendlyTeam)
        if not comp or not filters.friendlyComps[comp] then return false end
    end
    -- Partners filter (multi-select)
    if next(filters.partners) then
        local found = false
        for _, p in ipairs(game.friendlyTeam or {}) do
            if filters.partners[p.name] then found = true; break end
        end
        if not found then return false end
    end
    -- Enemy comp filter (multi-select)
    if next(filters.enemyComps) then
        local comp = GetCompKey(game.enemyTeam)
        if not comp or not filters.enemyComps[comp] then return false end
    end
    -- Enemy players filter (multi-select)
    if next(filters.enemyPlayers) then
        local found = false
        for _, p in ipairs(game.enemyTeam or {}) do
            if filters.enemyPlayers[p.name] then found = true; break end
        end
        if not found then return false end
    end
    -- Enemy races filter (multi-select)
    if next(filters.enemyRaces) then
        local found = false
        for _, p in ipairs(game.enemyTeam or {}) do
            if p.race and filters.enemyRaces[p.race] then found = true; break end
        end
        if not found then return false end
    end
    return true
end

local function CollectUniqueComps(teamKey)
    local comps = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        local key = GetCompKey(game[teamKey])
        if key and not seen[key] then
            table.insert(comps, key)
            seen[key] = true
        end
    end
    table.sort(comps)
    return comps
end

local function CollectUniquePartners()
    local playerName = UnitName("player")
    local partners = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        -- Scope partners to selected friendly comps if any
        if next(filters.friendlyComps) then
            local comp = GetCompKey(game.friendlyTeam)
            if not comp or not filters.friendlyComps[comp] then
                -- skip this game
            else
                for _, p in ipairs(game.friendlyTeam or {}) do
                    if p.name ~= playerName and not seen[p.name] then
                        table.insert(partners, { name = p.name, class = p.class })
                        seen[p.name] = true
                    end
                end
            end
        else
            for _, p in ipairs(game.friendlyTeam or {}) do
                if p.name ~= playerName and not seen[p.name] then
                    table.insert(partners, { name = p.name, class = p.class })
                    seen[p.name] = true
                end
            end
        end
    end
    table.sort(partners, function(a, b) return a.name < b.name end)
    return partners
end

local function CollectUniqueEnemyPlayers()
    local players = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        -- Scope to selected enemy comps if any
        if next(filters.enemyComps) then
            local comp = GetCompKey(game.enemyTeam)
            if not comp or not filters.enemyComps[comp] then
                -- skip
            else
                for _, p in ipairs(game.enemyTeam or {}) do
                    if not seen[p.name] then
                        table.insert(players, { name = p.name, class = p.class })
                        seen[p.name] = true
                    end
                end
            end
        else
            for _, p in ipairs(game.enemyTeam or {}) do
                if not seen[p.name] then
                    table.insert(players, { name = p.name, class = p.class })
                    seen[p.name] = true
                end
            end
        end
    end
    table.sort(players, function(a, b) return a.name < b.name end)
    return players
end

local function CollectUniqueEnemyRaces()
    local races = {}
    local seen = {}
    for _, game in ipairs(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) do
        -- Scope to selected enemy comps if any
        if next(filters.enemyComps) then
            local comp = GetCompKey(game.enemyTeam)
            if not comp or not filters.enemyComps[comp] then
                -- skip
            else
                for _, p in ipairs(game.enemyTeam or {}) do
                    if p.race and not seen[p.race] then
                        table.insert(races, p.race)
                        seen[p.race] = true
                    end
                end
            end
        else
            for _, p in ipairs(game.enemyTeam or {}) do
                if p.race and not seen[p.race] then
                    table.insert(races, p.race)
                    seen[p.race] = true
                end
            end
        end
    end
    table.sort(races)
    return races
end

-- Forward declarations for export/import (defined after minimap section)
local ShowExportDialog
local ShowImportDialog

---------------------------------------------------------------------------
-- History UI (embedded in Options Panel)
---------------------------------------------------------------------------
-- Forward declare RefreshHistory so filter widgets can call it
local RefreshHistory
local RefreshStats

-- Tab buttons: Sessions | History | Stats
local function CreateTabButton(parent, label, x)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(80, 20)
    btn:SetPoint("TOPLEFT", x, -24)

    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(unpack(C.sidebarBg))

    btn.text = btn:CreateFontString(nil, "OVERLAY")
    btn.text:SetFont(lib.FONT_BODY, 11, "")
    btn.text:SetPoint("CENTER", 0, 0)
    btn.text:SetText(label)
    btn.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    btn.underline = btn:CreateTexture(nil, "ARTWORK")
    btn.underline:SetHeight(2)
    btn.underline:SetPoint("BOTTOMLEFT", 0, 0)
    btn.underline:SetPoint("BOTTOMRIGHT", 0, 0)
    btn.underline:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    btn.underline:Hide()

    return btn
end

local function SetActiveTab(tab)
    activeTab = tab
    if not ui.sessionsTabBtn then return end
    local tabs = { ui.sessionsTabBtn, ui.historyTabBtn, ui.statsTabBtn }
    local activeKey = { sessions = 1, history = 2, stats = 3 }
    local activeIdx = activeKey[tab] or 1
    for i, btn in ipairs(tabs) do
        if i == activeIdx then
            btn.bg:SetColorTexture(unpack(C.tabActive))
            btn.underline:Show()
            btn.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        else
            btn.bg:SetColorTexture(unpack(C.sidebarBg))
            btn.underline:Hide()
            btn.text:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        end
    end
    if RefreshHistory then RefreshHistory() end
end

-- Format a comp key ("Disc Priest/Arms Warrior") into class-colored text
local function FormatCompLabel(compKey)
    if not compKey then return "All" end
    local parts = {}
    for entry in compKey:gmatch("[^/]+") do
        -- Entry might be "Spec Class" or just "Class"
        local spec, class = entry:match("^(.+) (%S+)$")
        if spec and CLASS_COLORS[class] then
            local color = CLASS_COLORS[class]
            table.insert(parts, "|cffcccccc" .. spec .. "|r " .. "|c" .. color .. class .. "|r")
        else
            -- No spec prefix or unrecognized — color the whole thing
            local color = CLASS_COLORS[entry] or "ffffffff"
            table.insert(parts, "|c" .. color .. entry .. "|r")
        end
    end
    return table.concat(parts, "/")
end

---------------------------------------------------------------------------
-- Searchable Multi-Select Dropdown Widget
---------------------------------------------------------------------------
local SD_ROW_H = 18
local SD_MAX_ROWS = 10
local activePopup = nil  -- track which popup is currently open

local function CreateSearchableDropdown(parent, ddName, width, opts)
    local dd = {}

    -- Main trigger button
    local btn = CreateFrame("Button", ddName .. "Btn", parent)
    btn:SetSize(width, 24)
    dd.frame = btn

    local btnBg = btn:CreateTexture(nil, "BACKGROUND")
    btnBg:SetAllPoints()
    btnBg:SetColorTexture(unpack(C.sidebarBg))

    local bdr = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bdr:SetAllPoints()
    bdr:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    bdr:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], C.borderDefault[4] or 1)

    local lbl = btn:CreateFontString(nil, "OVERLAY")
    lbl:SetFont(lib.FONT_BODY, 10, "")
    lbl:SetPoint("LEFT", 6, 0)
    lbl:SetPoint("RIGHT", -16, 0)
    lbl:SetJustifyH("LEFT")
    lbl:SetWordWrap(false)

    local arrow = btn:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -4, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    function dd:SetLabel(text) lbl:SetText(text) end
    dd:SetLabel(opts.defaultLabel or "All")

    -- Full-screen click-catcher backdrop
    local bdrop = CreateFrame("Button", nil, UIParent)
    bdrop:SetFrameStrata("FULLSCREEN")
    bdrop:SetAllPoints(UIParent)
    bdrop:Hide()
    bdrop:SetScript("OnClick", function() dd:Close() end)

    -- Popup frame
    local popup = CreateFrame("Frame", ddName .. "Pop", UIParent, "BackdropTemplate")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetClampedToScreen(true)
    popup:SetSize(width + 20, 200)
    -- Solid background (no bgFile — tooltip texture has built-in transparency)
    popup:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    -- Manual solid background texture
    local popBg = popup:CreateTexture(nil, "BACKGROUND")
    popBg:SetAllPoints()
    popBg:SetColorTexture(C.frameBg[1], C.frameBg[2], C.frameBg[3], C.frameBg[4])
    popup:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], C.borderDefault[4] or 1)
    popup:Hide()

    -- "Clear All" button
    local clrBtn = CreateFrame("Button", nil, popup)
    clrBtn:SetSize(width + 10, SD_ROW_H)
    clrBtn:SetPoint("TOPLEFT", 5, -5)
    local clrTxt = clrBtn:CreateFontString(nil, "OVERLAY")
    clrTxt:SetFont(lib.FONT_BODY, 10, "")
    clrTxt:SetPoint("LEFT", 4, 0)
    clrTxt:SetText("|cffaaaaaaAll (clear)|r")
    local clrHL = clrBtn:CreateTexture(nil, "HIGHLIGHT")
    clrHL:SetAllPoints()
    clrHL:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
    clrBtn:SetScript("OnClick", function()
        if opts.onClear then opts.onClear() end
        dd:Refresh()
    end)

    -- Search box
    local sBox = CreateFrame("EditBox", ddName .. "Srch", popup, "InputBoxTemplate")
    sBox:SetSize(width + 4, 18)
    sBox:SetPoint("TOPLEFT", 8, -5 - SD_ROW_H - 2)
    sBox:SetAutoFocus(false)
    sBox:SetFont(lib.FONT_BODY, 10, "")
    local sPH = sBox:CreateFontString(nil, "ARTWORK")
    sPH:SetFont(lib.FONT_BODY, 10, "")
    sPH:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    sPH:SetPoint("LEFT", 5, 0)
    sPH:SetText("Search...")
    sBox:SetScript("OnEditFocusGained", function() sPH:Hide() end)
    sBox:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then sPH:Show() end end)
    sBox:SetScript("OnEscapePressed", function() dd:Close() end)

    -- Scroll frame for options
    local scrollY = -5 - SD_ROW_H - 2 - 22 - 2
    local sf = CreateFrame("ScrollFrame", ddName .. "SF", popup, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 5, scrollY)
    sf:SetPoint("BOTTOMRIGHT", -26, 5)
    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(width - 10, 1)
    sf:SetScrollChild(sc)

    local rowPool = {}
    local curOpts = {}

    local function MakeRow(idx)
        local r = CreateFrame("Button", nil, sc)
        r:SetSize(width - 10, SD_ROW_H)
        local hl = r:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
        r.chk = r:CreateTexture(nil, "OVERLAY")
        r.chk:SetSize(12, 12)
        r.chk:SetPoint("LEFT", 2, 0)
        r.txt = r:CreateFontString(nil, "OVERLAY")
        r.txt:SetFont(lib.FONT_BODY, 10, "")
        r.txt:SetPoint("LEFT", 18, 0)
        r.txt:SetPoint("RIGHT", -2, 0)
        r.txt:SetJustifyH("LEFT")
        r.txt:SetWordWrap(false)
        rowPool[idx] = r
        return r
    end

    local function SetChk(tex, on)
        tex:SetTexture(on and "Interface\\Buttons\\UI-CheckBox-Check" or "Interface\\Buttons\\UI-CheckBox-Up")
    end

    local function FilterDisplay()
        local q = (sBox:GetText() or ""):lower()
        for _, r in ipairs(rowPool) do r:Hide() end
        local vi = 0
        for _, opt in ipairs(curOpts) do
            if q == "" or opt.searchText:find(q, 1, true) then
                vi = vi + 1
                local r = rowPool[vi] or MakeRow(vi)
                r:SetPoint("TOPLEFT", 0, -((vi - 1) * SD_ROW_H))
                r.txt:SetText(opt.text)
                SetChk(r.chk, opt.isChecked())
                r:SetScript("OnClick", function()
                    if opts.onToggle then opts.onToggle(opt.key) end
                    SetChk(r.chk, opt.isChecked())
                    if opts.getLabel then dd:SetLabel(opts.getLabel()) end
                end)
                r:Show()
            end
        end
        sc:SetHeight(math.max(vi * SD_ROW_H, 1))
        local listH = math.min(vi, SD_MAX_ROWS) * SD_ROW_H
        popup:SetHeight(math.max(5 + SD_ROW_H + 2 + 22 + 2 + listH + 8, 60))
    end

    sBox:SetScript("OnTextChanged", function() FilterDisplay() end)

    function dd:Refresh()
        if opts.getLabel then dd:SetLabel(opts.getLabel()) end
        if popup:IsShown() then
            curOpts = opts.getOptions and opts.getOptions() or {}
            FilterDisplay()
        end
    end

    function dd:Open()
        if activePopup and activePopup ~= dd then activePopup:Close() end
        CloseDropDownMenus()
        curOpts = opts.getOptions and opts.getOptions() or {}
        sBox:SetText("")
        sPH:Show()
        popup:ClearAllPoints()
        popup:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
        bdrop:Show()
        popup:Show()
        sBox:SetFocus()
        activePopup = dd
        FilterDisplay()
    end

    function dd:Close()
        popup:Hide()
        bdrop:Hide()
        sBox:ClearFocus()
        if activePopup == dd then activePopup = nil end
    end

    btn:SetScript("OnClick", function()
        if popup:IsShown() then dd:Close() else dd:Open() end
    end)
    btn:SetScript("OnEnter", function() btnBg:SetColorTexture(C.tabHover[1], C.tabHover[2], C.tabHover[3], C.tabHover[4] or 1) end)
    btn:SetScript("OnLeave", function() btnBg:SetColorTexture(unpack(C.sidebarBg)) end)

    return dd
end

-- (Filter dropdowns created inside BuildHistoryUI)

local function CreateBrandButton(parent, width, height, label, onClick)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    btn:SetBackdropBorderColor(C.divider[1], C.divider[2], C.divider[3], C.divider[4])
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(C.sidebarBg))
    btn._bg = bg
    local txt = btn:CreateFontString(nil, "OVERLAY")
    txt:SetFont(lib.FONT_BODY, 10, "")
    txt:SetPoint("CENTER")
    txt:SetText(label)
    txt:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    btn._txt = txt
    btn:SetScript("OnEnter", function()
        bg:SetColorTexture(unpack(C.tabActive))
        txt:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    end)
    btn:SetScript("OnLeave", function()
        bg:SetColorTexture(unpack(C.sidebarBg))
        txt:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    end)
    btn:SetScript("OnClick", onClick)
    return btn
end

-- (Export/Reset buttons, column headers, scroll frame, stats panel created inside BuildHistoryUI)

local NUM_STAT_ROWS = 10
local STAT_COL_COMP = 0      -- comp name offset from row left
local STAT_COL_RECORD = 165  -- W/L record offset
local STAT_COL_PCT = 220     -- percentage offset
local STAT_COL_BAR = 255     -- win% bar offset
local STAT_BAR_WIDTH = 55    -- max bar width
local STAT_ROW_WIDTH = 310

local function CreateStatRow(parent, x, y)
    local row = {}

    row.comp = parent:CreateFontString(nil, "OVERLAY")
    row.comp:SetFont(lib.FONT_BODY, 10, "")
    row.comp:SetPoint("TOPLEFT", x + STAT_COL_COMP, y)
    row.comp:SetWidth(160)
    row.comp:SetJustifyH("LEFT")
    row.comp:SetWordWrap(false)

    row.record = parent:CreateFontString(nil, "OVERLAY")
    row.record:SetFont(lib.FONT_BODY, 10, "")
    row.record:SetPoint("TOPLEFT", x + STAT_COL_RECORD, y)
    row.record:SetWidth(55)
    row.record:SetJustifyH("LEFT")
    row.record:SetWordWrap(false)

    row.pct = parent:CreateFontString(nil, "OVERLAY")
    row.pct:SetFont(lib.FONT_BODY, 10, "")
    row.pct:SetPoint("TOPLEFT", x + STAT_COL_PCT, y)
    row.pct:SetWidth(35)
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetWordWrap(false)

    -- Win% bar background (dark)
    row.barBg = parent:CreateTexture(nil, "ARTWORK")
    row.barBg:SetPoint("TOPLEFT", parent, "TOPLEFT", x + STAT_COL_BAR, y + 1)
    row.barBg:SetSize(STAT_BAR_WIDTH, 8)
    row.barBg:SetColorTexture(unpack(C.sidebarBg))

    -- Win% bar fill
    row.barFill = parent:CreateTexture(nil, "OVERLAY")
    row.barFill:SetPoint("TOPLEFT", parent, "TOPLEFT", x + STAT_COL_BAR, y + 1)
    row.barFill:SetSize(1, 8)
    row.barFill:SetColorTexture(0, 1, 0, 0.8)

    row.SetData = function(self, entry)
        if not entry then
            self.comp:SetText("")
            self.record:SetText("")
            self.pct:SetText("")
            self.barBg:Hide()
            self.barFill:Hide()
            return
        end
        self.comp:SetText(FormatCompLabel(entry.comp))
        self.record:SetText("|cff00ff00" .. entry.wins .. "W|r |cffff4444" .. entry.losses .. "L|r")
        self.pct:SetText("|cffffffff" .. math.floor(entry.pct + 0.5) .. "%|r")
        self.barBg:Show()
        local fillWidth = math.max(1, STAT_BAR_WIDTH * entry.pct / 100)
        self.barFill:SetWidth(fillWidth)
        -- Color gradient: red at 0%, yellow at 50%, green at 100%
        local r, g
        if entry.pct <= 50 then
            r = 1
            g = entry.pct / 50
        else
            r = 1 - (entry.pct - 50) / 50
            g = 1
        end
        self.barFill:SetColorTexture(r, g, 0, 0.9)
        self.barFill:Show()
    end

    return row
end

function RefreshStats()
    if not ui.built then return end

    -- Tally wins/losses per enemy comp from the filtered list
    local compStats = {} -- compKey → { wins, losses }
    local totalWins, totalLosses, totalNet, totalHasRating = 0, 0, 0, false
    for _, entry in ipairs(lastFilteredList) do
        local comp = GetCompKey(entry.game.enemyTeam)
        if not comp and entry.game.enemyComp and #entry.game.enemyComp > 0 then
            local sorted = {}
            for _, c in ipairs(entry.game.enemyComp) do table.insert(sorted, c) end
            table.sort(sorted)
            comp = table.concat(sorted, "/")
        end
        if comp then
            if not compStats[comp] then compStats[comp] = { wins = 0, losses = 0 } end
            if entry.game.result == "WIN" then
                compStats[comp].wins = compStats[comp].wins + 1
            else
                compStats[comp].losses = compStats[comp].losses + 1
            end
        end
        if entry.game.result == "WIN" then totalWins = totalWins + 1 else totalLosses = totalLosses + 1 end
        if entry.game.ratingChange then
            totalNet = totalNet + entry.game.ratingChange
            totalHasRating = true
        end
    end

    -- Summary line
    local total = totalWins + totalLosses
    local wrPct = (total > 0) and math.floor(totalWins / total * 100 + 0.5) or 0
    local summaryParts = { total .. " games", "|cff00ff00" .. totalWins .. "W|r / |cffff0000" .. totalLosses .. "L|r", wrPct .. "% WR" }
    if totalHasRating then
        local sign = totalNet >= 0 and "+" or ""
        local color = totalNet >= 0 and "|cff00ff00" or "|cffff0000"
        table.insert(summaryParts, "Net: " .. color .. sign .. totalNet .. "|r")
    end
    ui.statsSummaryText:SetText(table.concat(summaryParts, "  |cff555555·|r  "))

    -- Build sorted list
    local compList = {}
    for comp, stats in pairs(compStats) do
        local ct = stats.wins + stats.losses
        local winPct = (ct > 0) and (stats.wins / ct * 100) or 0
        table.insert(compList, { comp = comp, wins = stats.wins, losses = stats.losses, total = ct, pct = winPct })
    end

    -- Sort all comps by win% desc
    local qualified = {}
    for _, v in ipairs(compList) do
        table.insert(qualified, v)
    end
    table.sort(qualified, function(a, b)
        if a.pct ~= b.pct then return a.pct > b.pct end
        return a.total > b.total
    end)

    -- Best = top of sorted list, Worst = bottom of sorted list
    local best = {}
    local worst = {}
    for i = 1, math.min(NUM_STAT_ROWS, #qualified) do
        best[i] = qualified[i]
    end
    for i = 1, math.min(NUM_STAT_ROWS, #qualified) do
        worst[i] = qualified[#qualified - i + 1]
    end

    for i = 1, NUM_STAT_ROWS do
        ui.bestRows[i]:SetData(best[i])
        ui.worstRows[i]:SetData(worst[i])
    end
end

local function FormatDuration(seconds)
    if not seconds or seconds < 0 then return "--:--" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

-- Build a sorted string key of non-player teammate names for session boundary detection
local function GetPartnerKey(game)
    local playerName = UnitName("player")
    local names = {}
    for _, p in ipairs(game.friendlyTeam or {}) do
        if p.name ~= playerName then
            table.insert(names, p.name)
        end
    end
    table.sort(names)
    return table.concat(names, "/")
end

-- Compute sessions from a chronological games array.
-- New session starts on: time gap > gapThreshold, partner change, or bracket change.
-- Returns array of { startTime, endTime, bracket, games={{idx,game},...}, wins, losses, netRating, hasRating, partners }
local function ComputeSessions(games, gapThreshold)
    if not games or #games == 0 then return {} end
    gapThreshold = gapThreshold or 1200

    local sessions = {}
    local cur = nil

    for i = 1, #games do
        local game = games[i]
        local partnerKey = GetPartnerKey(game)
        local bracket = game.bracket or "?"

        local needNew = false
        if not cur then
            needNew = true
        else
            -- Check time gap
            local prevEnd = cur.endTime or cur.startTime
            local thisStart = game.startTime or 0
            if prevEnd and thisStart and (thisStart - prevEnd) > gapThreshold then
                needNew = true
            end
            -- Check partner change
            if not needNew and partnerKey ~= cur.partnerKey then
                needNew = true
            end
            -- Check bracket change
            if not needNew and tostring(bracket) ~= tostring(cur.bracket) then
                needNew = true
            end
        end

        if needNew then
            cur = {
                startTime = game.startTime,
                endTime = game.endTime,
                bracket = bracket,
                partnerKey = partnerKey,
                partners = partnerKey,
                games = {},
                wins = 0,
                losses = 0,
                netRating = 0,
                hasRating = false,
            }
            table.insert(sessions, cur)
        end

        table.insert(cur.games, { idx = i, game = game })
        if game.endTime and (not cur.endTime or game.endTime > cur.endTime) then
            cur.endTime = game.endTime
        end
        if game.startTime and (not cur.startTime or game.startTime < cur.startTime) then
            cur.startTime = game.startTime
        end
        if game.result == "WIN" then
            cur.wins = cur.wins + 1
        else
            cur.losses = cur.losses + 1
        end
        if game.ratingChange then
            cur.netRating = cur.netRating + game.ratingChange
            cur.hasRating = true
        end
    end

    return sessions
end

local function ColorClass(name)
    local color = CLASS_COLORS[name] or "ffffffff"
    return "|c" .. color .. name .. "|r"
end

local function FormatTime(ts)
    if not ts then return "?" end
    return date("%H:%M:%S", ts)
end

local function FormatTeam(team)
    if not team or #team == 0 then return "?" end
    local parts = {}
    for _, p in ipairs(team) do
        table.insert(parts, ColorClass(p.class) .. " " .. p.name)
    end
    return table.concat(parts, ", ")
end

local function FormatTeamClasses(team)
    if not team or #team == 0 then return nil end
    local parts = {}
    for _, p in ipairs(team) do
        table.insert(parts, ColorClass(p.class))
    end
    return table.concat(parts, " ")
end

-- Abbreviate race names to keep row text compact
local RACE_SHORT = {
    ["Night Elf"]            = "Nelf",
    ["Blood Elf"]            = "Belf",
}

local function FormatTeamNames(team)
    if not team or #team == 0 then return nil end
    local names = {}
    local details = {}
    for _, p in ipairs(team) do
        local color = CLASS_COLORS[p.class] or "ffffffff"
        table.insert(names, "|c" .. color .. p.name .. "|r")
        -- Build subtitle: "Spec Race" or fallback to class
        local parts = {}
        if p.spec then table.insert(parts, SPEC_SHORT[p.spec] or p.spec) end
        if p.race then table.insert(parts, RACE_SHORT[p.race] or p.race) end
        if #parts > 0 then
            table.insert(details, table.concat(parts, " "))
        else
            table.insert(details, p.class or "?")
        end
    end
    local line1 = table.concat(names, ", ")
    local line2 = "|cff999999" .. table.concat(details, "  ·  ") .. "|r"
    return line1 .. "\n" .. line2
end

local rowPool = {}

local function CreateMatchRow(pool, idx)
    local row = pool[idx]
    if row then return row end

    row = CreateFrame("Frame", nil, ui.content)
    row:SetSize(610, ROW_HEIGHT)
    pool[idx] = row

    row.result = row:CreateFontString(nil, "OVERLAY")
    row.result:SetFont(lib.FONT_BODY, 10, "")
    row.result:SetPoint("LEFT", 4, 0)
    row.result:SetWidth(36)

    row.friendly = row:CreateFontString(nil, "OVERLAY")
    row.friendly:SetFont(lib.FONT_BODY, 10, "")
    row.friendly:SetPoint("LEFT", 44, 0)
    row.friendly:SetWidth(200)
    row.friendly:SetJustifyH("LEFT")
    row.friendly:SetMaxLines(2)
    row.friendly:SetNonSpaceWrap(false)
    row.friendly:SetWordWrap(true)

    row.vs = row:CreateFontString(nil, "OVERLAY")
    row.vs:SetFont(lib.FONT_BODY, 10, "")
    row.vs:SetPoint("LEFT", 248, 0)
    row.vs:SetWidth(16)
    row.vs:SetJustifyH("CENTER")
    row.vs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], C.textMuted[4] or 1)

    row.enemy = row:CreateFontString(nil, "OVERLAY")
    row.enemy:SetFont(lib.FONT_BODY, 10, "")
    row.enemy:SetPoint("LEFT", 268, 0)
    row.enemy:SetWidth(200)
    row.enemy:SetJustifyH("LEFT")
    row.enemy:SetMaxLines(2)
    row.enemy:SetNonSpaceWrap(false)
    row.enemy:SetWordWrap(true)

    row.rating = row:CreateFontString(nil, "OVERLAY")
    row.rating:SetFont(lib.FONT_BODY, 10, "")
    row.rating:SetPoint("LEFT", 472, 0)
    row.rating:SetWidth(90)
    row.rating:SetJustifyH("CENTER")

    row.duration = row:CreateFontString(nil, "OVERLAY")
    row.duration:SetFont(lib.FONT_BODY, 10, "")
    row.duration:SetPoint("LEFT", 566, 0)
    row.duration:SetWidth(45)
    row.duration:SetJustifyH("CENTER")

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()

    return row
end

local function PopulateMatchRow(row, entry, displayIdx)
    local game = entry.game

    -- Alternating row color
    if displayIdx % 2 == 0 then
        row.bg:SetColorTexture(C.rowHover[1], C.rowHover[2], C.rowHover[3], C.rowHover[4])
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end

    if game.result == "WIN" then
        row.result:SetText("|cff00ff00WIN|r")
    else
        row.result:SetText("|cffff0000LOSS|r")
    end

    local friendlyStr = FormatTeamNames(game.friendlyTeam)
    row.friendly:SetText(friendlyStr or "—")

    row.vs:SetText("vs")

    local enemyStr = FormatTeamNames(game.enemyTeam)
    if not enemyStr then
        local parts = {}
        for _, class in ipairs(game.enemyComp or {}) do
            table.insert(parts, ColorClass(class))
        end
        enemyStr = #parts > 0 and table.concat(parts, " ") or "?"
    end
    row.enemy:SetText(enemyStr)

    if game.ratingChange then
        local sign = game.ratingChange >= 0 and "+" or ""
        local color = game.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
        local ratingText = color .. sign .. game.ratingChange .. "|r"
        if game.enemyMMR and game.enemyMMR > 0 then
            ratingText = ratingText .. " |cff888888vs " .. game.enemyMMR .. "|r"
        end
        row.rating:SetText(ratingText)
    elseif game.enemyMMR and game.enemyMMR > 0 then
        row.rating:SetText("|cff888888vs " .. game.enemyMMR .. "|r")
    else
        row.rating:SetText("|cff555555—|r")
    end

    local dur = (game.startTime and game.endTime) and (game.endTime - game.startTime) or nil
    row.duration:SetText(FormatDuration(dur))
    row.duration:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
end

local function CreateSessionHeaderRow(pool, idx)
    local hdr = pool[idx]
    if hdr then return hdr end

    hdr = CreateFrame("Button", nil, ui.content)
    hdr:SetSize(610, SESSION_HEADER_HEIGHT)
    pool[idx] = hdr

    -- Dark background
    hdr.bg = hdr:CreateTexture(nil, "BACKGROUND")
    hdr.bg:SetAllPoints()
    hdr.bg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], C.bgRaised[4] or 1)

    -- 1px top border
    hdr.topBorder = hdr:CreateTexture(nil, "ARTWORK")
    hdr.topBorder:SetHeight(1)
    hdr.topBorder:SetPoint("TOPLEFT", 0, 0)
    hdr.topBorder:SetPoint("TOPRIGHT", 0, 0)
    hdr.topBorder:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

    -- Collapse arrow
    hdr.arrow = hdr:CreateFontString(nil, "OVERLAY")
    hdr.arrow:SetFont(lib.FONT_BODY, 11, "")
    hdr.arrow:SetPoint("LEFT", 4, 0)
    hdr.arrow:SetText("v")

    -- Date/time
    hdr.dateText = hdr:CreateFontString(nil, "OVERLAY")
    hdr.dateText:SetFont(lib.FONT_BODY, 10, "")
    hdr.dateText:SetPoint("LEFT", 20, 0)
    hdr.dateText:SetWidth(130)
    hdr.dateText:SetJustifyH("LEFT")
    hdr.dateText:SetTextColor(C.accent[1], C.accent[2], C.accent[3])

    -- Game count
    hdr.countText = hdr:CreateFontString(nil, "OVERLAY")
    hdr.countText:SetFont(lib.FONT_BODY, 10, "")
    hdr.countText:SetPoint("LEFT", 155, 0)
    hdr.countText:SetWidth(65)
    hdr.countText:SetJustifyH("LEFT")
    hdr.countText:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    -- W/L record
    hdr.recordText = hdr:CreateFontString(nil, "OVERLAY")
    hdr.recordText:SetFont(lib.FONT_BODY, 10, "")
    hdr.recordText:SetPoint("LEFT", 225, 0)
    hdr.recordText:SetWidth(85)
    hdr.recordText:SetJustifyH("LEFT")

    -- Net rating
    hdr.ratingText = hdr:CreateFontString(nil, "OVERLAY")
    hdr.ratingText:SetFont(lib.FONT_MONO, 10, "")
    hdr.ratingText:SetPoint("LEFT", 315, 0)
    hdr.ratingText:SetWidth(70)
    hdr.ratingText:SetJustifyH("LEFT")

    -- Duration
    hdr.durationText = hdr:CreateFontString(nil, "OVERLAY")
    hdr.durationText:SetFont(lib.FONT_MONO, 10, "")
    hdr.durationText:SetPoint("LEFT", 400, 0)
    hdr.durationText:SetWidth(55)
    hdr.durationText:SetJustifyH("LEFT")
    hdr.durationText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- Bracket
    hdr.bracketText = hdr:CreateFontString(nil, "OVERLAY")
    hdr.bracketText:SetFont(lib.FONT_BODY, 10, "")
    hdr.bracketText:SetPoint("LEFT", 470, 0)
    hdr.bracketText:SetWidth(50)
    hdr.bracketText:SetJustifyH("LEFT")
    hdr.bracketText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- Click handler for collapse/expand
    hdr:SetScript("OnClick", function(self)
        sessionCollapsed[self.sessionStartTime] = not sessionCollapsed[self.sessionStartTime]
        RefreshHistory()
    end)

    -- Hover highlight
    hdr:SetScript("OnEnter", function(self)
        self.bg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], C.bgElevated[4] or 1)
    end)
    hdr:SetScript("OnLeave", function(self)
        self.bg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], C.bgRaised[4] or 1)
    end)

    return hdr
end

---------------------------------------------------------------------------
-- BuildHistoryUI — creates all history UI inside the options panel content frame
---------------------------------------------------------------------------
local function BuildHistoryUI(contentFrame)
    if ui.built then return end

    -- Summary text (replaces the old frame title)
    ui.summaryText = contentFrame:CreateFontString(nil, "OVERLAY")
    ui.summaryText:SetFont(lib.FONT_DISPLAY, 11, "")
    ui.summaryText:SetPoint("TOPLEFT", 8, -6)
    ui.summaryText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    ui.summaryText:SetText("Trinketed — Arena History")

    -- Sub-tabs: Sessions | History | Stats
    ui.sessionsTabBtn = CreateTabButton(contentFrame, "Sessions", 8)
    ui.historyTabBtn = CreateTabButton(contentFrame, "History", 92)
    ui.statsTabBtn = CreateTabButton(contentFrame, "Stats", 176)
    -- Reposition to Y=-22 (plan spec)
    ui.sessionsTabBtn:ClearAllPoints()
    ui.sessionsTabBtn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, -22)
    ui.historyTabBtn:ClearAllPoints()
    ui.historyTabBtn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 92, -22)
    ui.statsTabBtn:ClearAllPoints()
    ui.statsTabBtn:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 176, -22)

    ui.sessionsTabBtn:SetScript("OnClick", function() SetActiveTab("sessions") end)
    ui.historyTabBtn:SetScript("OnClick", function() SetActiveTab("history") end)
    ui.statsTabBtn:SetScript("OnClick", function() SetActiveTab("stats") end)

    -- Filter Row 1 (Y = -46), width = 130 each
    ui.friendlyCompDD = CreateSearchableDropdown(contentFrame, "TkCompDD", 130, {
        defaultLabel = "Player Comp: All",
        getOptions = function()
            local out = {}
            for _, comp in ipairs(CollectUniqueComps("friendlyTeam")) do
                table.insert(out, { key = comp, text = FormatCompLabel(comp), searchText = comp:lower():gsub("/", " "), isChecked = function() return filters.friendlyComps[comp] == true end })
            end
            return out
        end,
        onToggle = function(key)
            if filters.friendlyComps[key] then filters.friendlyComps[key] = nil else filters.friendlyComps[key] = true end
            filters.partners = {}
            RefreshHistory()
        end,
        onClear = function() filters.friendlyComps = {}; filters.partners = {}; RefreshHistory() end,
        getLabel = function()
            if not next(filters.friendlyComps) then return "Player Comp: All" end
            local t = {}; for c in pairs(filters.friendlyComps) do table.insert(t, FormatCompLabel(c)) end
            return "Player Comp: " .. table.concat(t, ", ")
        end,
    })
    ui.friendlyCompDD.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, -46)

    ui.partnerDD = CreateSearchableDropdown(contentFrame, "TkPartDD", 130, {
        defaultLabel = "Partner: All",
        getOptions = function()
            local out = {}
            for _, p in ipairs(CollectUniquePartners()) do
                local color = CLASS_COLORS[p.class] or "ffffffff"
                table.insert(out, { key = p.name, text = "|c" .. color .. p.name .. "|r", searchText = p.name:lower(), isChecked = function() return filters.partners[p.name] == true end })
            end
            return out
        end,
        onToggle = function(key)
            if filters.partners[key] then filters.partners[key] = nil else filters.partners[key] = true end
            RefreshHistory()
        end,
        onClear = function() filters.partners = {}; RefreshHistory() end,
        getLabel = function()
            if not next(filters.partners) then return "Partner: All" end
            local t = {}; for n in pairs(filters.partners) do table.insert(t, n) end
            return "Partner: " .. table.concat(t, ", ")
        end,
    })
    ui.partnerDD.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 146, -46)

    ui.enemyCompDD = CreateSearchableDropdown(contentFrame, "TkECompDD", 130, {
        defaultLabel = "Enemy Comp: All",
        getOptions = function()
            local out = {}
            for _, comp in ipairs(CollectUniqueComps("enemyTeam")) do
                table.insert(out, { key = comp, text = FormatCompLabel(comp), searchText = comp:lower():gsub("/", " "), isChecked = function() return filters.enemyComps[comp] == true end })
            end
            return out
        end,
        onToggle = function(key)
            if filters.enemyComps[key] then filters.enemyComps[key] = nil else filters.enemyComps[key] = true end
            filters.enemyPlayers = {}; filters.enemyRaces = {}
            RefreshHistory()
        end,
        onClear = function() filters.enemyComps = {}; filters.enemyPlayers = {}; filters.enemyRaces = {}; RefreshHistory() end,
        getLabel = function()
            if not next(filters.enemyComps) then return "Enemy Comp: All" end
            local t = {}; for c in pairs(filters.enemyComps) do table.insert(t, FormatCompLabel(c)) end
            return "Enemy Comp: " .. table.concat(t, ", ")
        end,
    })
    ui.enemyCompDD.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 284, -46)

    -- Filter Row 2 (Y = -72), width = 130 each
    ui.enemyPlayerDD = CreateSearchableDropdown(contentFrame, "TkEPlrDD", 130, {
        defaultLabel = "Enemy Players: All",
        getOptions = function()
            local out = {}
            for _, p in ipairs(CollectUniqueEnemyPlayers()) do
                local color = CLASS_COLORS[p.class] or "ffffffff"
                table.insert(out, { key = p.name, text = "|c" .. color .. p.name .. "|r", searchText = p.name:lower(), isChecked = function() return filters.enemyPlayers[p.name] == true end })
            end
            return out
        end,
        onToggle = function(key)
            if filters.enemyPlayers[key] then filters.enemyPlayers[key] = nil else filters.enemyPlayers[key] = true end
            RefreshHistory()
        end,
        onClear = function() filters.enemyPlayers = {}; RefreshHistory() end,
        getLabel = function()
            if not next(filters.enemyPlayers) then return "Enemy Players: All" end
            local t = {}; for n in pairs(filters.enemyPlayers) do table.insert(t, n) end
            return "Enemy Players: " .. table.concat(t, ", ")
        end,
    })
    ui.enemyPlayerDD.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 8, -72)

    ui.enemyRaceDD = CreateSearchableDropdown(contentFrame, "TkERaceDD", 130, {
        defaultLabel = "Race: All",
        getOptions = function()
            local out = {}
            for _, race in ipairs(CollectUniqueEnemyRaces()) do
                table.insert(out, { key = race, text = race, searchText = race:lower(), isChecked = function() return filters.enemyRaces[race] == true end })
            end
            return out
        end,
        onToggle = function(key)
            if filters.enemyRaces[key] then filters.enemyRaces[key] = nil else filters.enemyRaces[key] = true end
            RefreshHistory()
        end,
        onClear = function() filters.enemyRaces = {}; RefreshHistory() end,
        getLabel = function()
            if not next(filters.enemyRaces) then return "Race: All" end
            local t = {}; for r in pairs(filters.enemyRaces) do table.insert(t, r) end
            return "Race: " .. table.concat(t, ", ")
        end,
    })
    ui.enemyRaceDD.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 146, -72)

    ui.resultDD = CreateSearchableDropdown(contentFrame, "TkResultDD", 130, {
        defaultLabel = "Result: All",
        getOptions = function()
            return {
                { key = "WIN",  text = "|cff00ff00WIN|r",  searchText = "win",  isChecked = function() return filters.result == "WIN" end },
                { key = "LOSS", text = "|cffff0000LOSS|r", searchText = "loss", isChecked = function() return filters.result == "LOSS" end },
            }
        end,
        onToggle = function(key)
            if filters.result == key then
                filters.result = nil
            else
                filters.result = key
            end
            RefreshHistory()
        end,
        onClear = function() filters.result = nil; RefreshHistory() end,
        getLabel = function()
            if filters.result == "WIN" then return "|cff00ff00WIN|r" end
            if filters.result == "LOSS" then return "|cffff0000LOSS|r" end
            return "Result: All"
        end,
    })
    ui.resultDD.frame:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 284, -72)

    -- Export / Reset buttons (TOPRIGHT of contentFrame)
    local exportBtn = CreateBrandButton(contentFrame, 58, 22, "Export", function() ShowExportDialog() end)
    exportBtn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -68, -72)

    local resetBtn = CreateBrandButton(contentFrame, 58, 22, "Reset", nil)
    resetBtn:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -6, -72)
    resetBtn:SetScript("OnClick", function()
        filters.friendlyComps = {}
        filters.partners = {}
        filters.enemyComps = {}
        filters.enemyPlayers = {}
        filters.enemyRaces = {}
        filters.result = nil
        ui.friendlyCompDD:SetLabel("Player Comp: All")
        ui.partnerDD:SetLabel("Partner: All")
        ui.enemyCompDD:SetLabel("Enemy Comp: All")
        ui.enemyPlayerDD:SetLabel("Enemy Players: All")
        ui.enemyRaceDD:SetLabel("Race: All")
        ui.resultDD:SetLabel("Result: All")
        RefreshHistory()
    end)

    -- Column headers (Y = -98)
    local headerY = -98
    local headers = {
        { text = "Result",   x = 4,   w = 36,  justify = "LEFT" },
        { text = "Friendly", x = 44,  w = 200, justify = "LEFT" },
        { text = "",         x = 248, w = 16,  justify = "CENTER" },
        { text = "Enemy",    x = 268, w = 200, justify = "LEFT" },
        { text = "Rating",   x = 472, w = 90,  justify = "CENTER" },
        { text = "Dur",      x = 566, w = 45,  justify = "CENTER" },
    }
    ui.headerFontStrings = {}
    for _, h in ipairs(headers) do
        if h.text ~= "" then
            local fs = contentFrame:CreateFontString(nil, "OVERLAY")
            fs:SetFont(lib.FONT_BODY, 10, "")
            fs:SetPoint("TOPLEFT", h.x, headerY)
            fs:SetWidth(h.w)
            fs:SetJustifyH(h.justify)
            fs:SetWordWrap(false)
            fs:SetTextColor(C.textMuted[1], C.textMuted[2], C.textMuted[3], C.textMuted[4] or 1)
            fs:SetText(h.text)
            table.insert(ui.headerFontStrings, fs)
        end
    end

    -- Thin separator line below headers (Y = -110)
    ui.headerSep = contentFrame:CreateTexture(nil, "ARTWORK")
    ui.headerSep:SetHeight(1)
    ui.headerSep:SetPoint("TOPLEFT", 4, -110)
    ui.headerSep:SetPoint("TOPRIGHT", -6, -110)
    ui.headerSep:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4])

    -- Scroll frame (Y = -112 to bottom -4)
    ui.scrollFrame = CreateFrame("ScrollFrame", nil, contentFrame, "UIPanelScrollFrameTemplate")
    ui.scrollFrame:SetPoint("TOPLEFT", 4, -112)
    ui.scrollFrame:SetPoint("BOTTOMRIGHT", -22, 4)

    ui.content = CreateFrame("Frame", nil, ui.scrollFrame)
    ui.content:SetSize(610, 1) -- height grows dynamically
    ui.scrollFrame:SetScrollChild(ui.content)

    -- Stats container frame (hidden until stats tab is active)
    ui.statsFrame = CreateFrame("Frame", nil, contentFrame)
    ui.statsFrame:SetPoint("TOPLEFT", 0, -98)
    ui.statsFrame:SetPoint("BOTTOMRIGHT", 0, 0)
    ui.statsFrame:Hide()

    -- Stats: Summary line
    ui.statsSummaryText = ui.statsFrame:CreateFontString(nil, "OVERLAY")
    ui.statsSummaryText:SetFont(lib.FONT_DISPLAY, 11, "")
    ui.statsSummaryText:SetPoint("TOPLEFT", 14, -6)
    ui.statsSummaryText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    ui.statsSummaryText:SetText("")

    -- Stats: Best Matchups header (left column)
    local bestHeader = ui.statsFrame:CreateFontString(nil, "OVERLAY")
    bestHeader:SetFont(lib.FONT_DISPLAY, 10, "")
    bestHeader:SetPoint("TOPLEFT", 14, -30)
    bestHeader:SetText("|cff00ff00Best Matchups|r")

    -- Stats: Worst Matchups header (right column)
    local worstHeader = ui.statsFrame:CreateFontString(nil, "OVERLAY")
    worstHeader:SetFont(lib.FONT_DISPLAY, 10, "")
    worstHeader:SetPoint("TOPLEFT", 330, -30)
    worstHeader:SetText("|cffff4444Worst Matchups|r")

    -- Stats: Stat rows (10 per column)
    ui.bestRows = {}
    ui.worstRows = {}
    for i = 1, NUM_STAT_ROWS do
        local y = -44 - (i - 1) * 14
        ui.bestRows[i] = CreateStatRow(ui.statsFrame, 14, y)
        ui.worstRows[i] = CreateStatRow(ui.statsFrame, 330, y)
    end

    -- Mark as built before initializing tab (SetActiveTab calls RefreshHistory)
    ui.built = true
    SetActiveTab("sessions")
end


function RefreshHistory()
    if not ui.built then return end

    -- Recycle existing rows
    for _, row in ipairs(rowPool) do
        row:Hide()
    end
    for _, row in ipairs(sessionMatchRowPool) do
        row:Hide()
    end
    for _, hdr in ipairs(sessionHeaderPool) do
        hdr:Hide()
    end

    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}

    if activeTab == "stats" then
        -- Hide scroll area and column headers, show stats frame
        for _, fs in ipairs(ui.headerFontStrings or {}) do fs:Hide() end
        if ui.headerSep then ui.headerSep:Hide() end
        ui.scrollFrame:Hide()
        ui.statsFrame:Show()

        -- Build filtered list from all games (apply current filters)
        lastFilteredList = {}
        for i = #allGames, 1, -1 do
            if GameMatchesFilters(allGames[i]) then
                table.insert(lastFilteredList, { idx = i, game = allGames[i] })
            end
        end

        -- Update summary
        local wins, losses, netRating, hasRating = 0, 0, 0, false
        for _, entry in ipairs(lastFilteredList) do
            if entry.game.result == "WIN" then wins = wins + 1 else losses = losses + 1 end
            if entry.game.ratingChange then
                netRating = netRating + entry.game.ratingChange
                hasRating = true
            end
        end
        local totalGames = #allGames
        local shownGames = #lastFilteredList
        local countStr = (shownGames < totalGames)
            and (shownGames .. "/" .. totalGames .. " games")
            or (totalGames .. " games")
        local ratingStr = ""
        if hasRating then
            local sign = netRating >= 0 and "+" or ""
            local color = netRating >= 0 and "|cff00ff00" or "|cffff0000"
            ratingStr = " | Net: " .. color .. sign .. netRating .. "|r"
        end
        ui.summaryText:SetText(countStr .. " (" ..
            "|cff00ff00" .. wins .. "W|r / |cffff0000" .. losses .. "L|r)" .. ratingStr)

        RefreshStats()

    elseif activeTab == "sessions" then
        -- Hide stats frame, show scroll area and column headers
        ui.statsFrame:Hide()
        ui.scrollFrame:Show()
        for _, fs in ipairs(ui.headerFontStrings or {}) do
            fs:Show()
        end
        if ui.headerSep then ui.headerSep:Show() end

        local gapThreshold = TrinketedHistoryDB and TrinketedHistoryDB.sessionGapThreshold or 1200
        local sessions = ComputeSessions(allGames, gapThreshold)

        -- For each session, filter games and skip empty sessions
        local visibleSessions = {}
        local totalWins, totalLosses, totalNet, totalHasRating, totalGamesCount = 0, 0, 0, false, 0
        for sIdx = #sessions, 1, -1 do  -- newest first
            local sess = sessions[sIdx]
            local filteredGames = {}
            local sWins, sLosses, sNet, sHasRating = 0, 0, 0, false
            for _, entry in ipairs(sess.games) do
                if GameMatchesFilters(entry.game) then
                    table.insert(filteredGames, entry)
                    if entry.game.result == "WIN" then sWins = sWins + 1 else sLosses = sLosses + 1 end
                    if entry.game.ratingChange then
                        sNet = sNet + entry.game.ratingChange
                        sHasRating = true
                    end
                end
            end
            if #filteredGames > 0 then
                table.insert(visibleSessions, {
                    session = sess,
                    filteredGames = filteredGames,
                    wins = sWins,
                    losses = sLosses,
                    netRating = sNet,
                    hasRating = sHasRating,
                })
                totalWins = totalWins + sWins
                totalLosses = totalLosses + sLosses
                totalNet = totalNet + sNet
                if sHasRating then totalHasRating = true end
                totalGamesCount = totalGamesCount + #filteredGames
            end
        end

        local totalHeight = 0
        local sessionRowIdx = 0
        local matchRowIdx = 0

        for _, vs in ipairs(visibleSessions) do
            local sess = vs.session

            -- Session header
            sessionRowIdx = sessionRowIdx + 1
            local hdr = CreateSessionHeaderRow(sessionHeaderPool, sessionRowIdx)
            hdr:SetPoint("TOPLEFT", 0, -totalHeight)

            -- Date/time
            local dateStr = sess.startTime and date("%b %d, %I:%M %p", sess.startTime) or "?"
            hdr.dateText:SetText(dateStr)

            -- Game count
            hdr.countText:SetText(#vs.filteredGames .. " games")

            -- W/L record
            local wlColor = vs.wins >= vs.losses and "|cff00ff00" or "|cffff0000"
            hdr.recordText:SetText(wlColor .. vs.wins .. "W|r / |cffff0000" .. vs.losses .. "L|r")

            -- Net rating
            if vs.hasRating then
                local sign = vs.netRating >= 0 and "+" or ""
                local color = vs.netRating >= 0 and "|cff00ff00" or "|cffff0000"
                hdr.ratingText:SetText(color .. sign .. vs.netRating .. "|r")
            else
                hdr.ratingText:SetText("")
            end

            -- Duration
            local sessDur = (sess.startTime and sess.endTime) and (sess.endTime - sess.startTime) or nil
            hdr.durationText:SetText(sessDur and FormatDuration(sessDur) or "")

            -- Bracket
            hdr.bracketText:SetText(sess.bracket or "")

            -- Collapse arrow
            local collapsed = sessionCollapsed[sess.startTime]
            hdr.arrow:SetText(collapsed and ">" or "v")

            hdr.sessionStartTime = sess.startTime
            hdr:Show()
            totalHeight = totalHeight + SESSION_HEADER_HEIGHT

            -- Match rows (only if expanded)
            if not collapsed then
                for gIdx, entry in ipairs(vs.filteredGames) do
                    matchRowIdx = matchRowIdx + 1
                    local row = CreateMatchRow(sessionMatchRowPool, matchRowIdx)
                    row:SetPoint("TOPLEFT", 0, -totalHeight)
                    PopulateMatchRow(row, entry, gIdx)
                    row:Show()
                    totalHeight = totalHeight + ROW_HEIGHT
                end
            end
        end

        ui.content:SetHeight(math.max(totalHeight, 1))

        -- Sessions summary
        local totalAllGames = #allGames
        local countStr = (totalGamesCount < totalAllGames)
            and (totalGamesCount .. "/" .. totalAllGames .. " games")
            or (totalAllGames .. " games")
        local ratingStr = ""
        if totalHasRating then
            local sign = totalNet >= 0 and "+" or ""
            local color = totalNet >= 0 and "|cff00ff00" or "|cffff0000"
            ratingStr = " | Net: " .. color .. sign .. totalNet .. "|r"
        end
        ui.summaryText:SetText(countStr .. ", " .. #visibleSessions .. " sessions (" ..
            "|cff00ff00" .. totalWins .. "W|r / |cffff0000" .. totalLosses .. "L|r)" .. ratingStr)

        -- Build filtered list for stats tab
        lastFilteredList = {}
        for _, vs in ipairs(visibleSessions) do
            for _, entry in ipairs(vs.filteredGames) do
                table.insert(lastFilteredList, entry)
            end
        end

    else -- "history" tab
        -- Hide stats frame, show scroll area
        ui.statsFrame:Hide()
        ui.scrollFrame:Show()

        -- Show column headers
        for _, fs in ipairs(ui.headerFontStrings or {}) do
            fs:Show()
        end
        if ui.headerSep then ui.headerSep:Show() end

        -- Apply filters — build list of {originalIndex, game} pairs, newest first
        local filtered = {}
        for i = #allGames, 1, -1 do
            if GameMatchesFilters(allGames[i]) then
                table.insert(filtered, { idx = i, game = allGames[i] })
            end
        end

        local totalHeight = 0

        for displayIdx = 1, #filtered do
            local row = CreateMatchRow(rowPool, displayIdx)
            row:SetPoint("TOPLEFT", 0, -((displayIdx - 1) * ROW_HEIGHT))
            PopulateMatchRow(row, filtered[displayIdx], displayIdx)
            row:Show()
            totalHeight = totalHeight + ROW_HEIGHT
        end

        ui.content:SetHeight(math.max(totalHeight, 1))

        -- Update summary with win/loss count and net rating (from filtered results)
        local wins, losses, netRating, hasRating = 0, 0, 0, false
        for _, entry in ipairs(filtered) do
            if entry.game.result == "WIN" then wins = wins + 1 else losses = losses + 1 end
            if entry.game.ratingChange then
                netRating = netRating + entry.game.ratingChange
                hasRating = true
            end
        end
        local totalGames = #allGames
        local shownGames = #filtered
        local countStr = (shownGames < totalGames)
            and (shownGames .. "/" .. totalGames .. " games")
            or (totalGames .. " games")
        local ratingStr = ""
        if hasRating then
            local sign = netRating >= 0 and "+" or ""
            local color = netRating >= 0 and "|cff00ff00" or "|cffff0000"
            ratingStr = " | Net: " .. color .. sign .. netRating .. "|r"
        end
        ui.summaryText:SetText(countStr .. " (" ..
            "|cff00ff00" .. wins .. "W|r / |cffff0000" .. losses .. "L|r)" .. ratingStr)

        lastFilteredList = filtered
    end
end

local function ToggleHistory()
    lib:ShowOptionsPanel("History")
end

---------------------------------------------------------------------------
-- Minimap Button
---------------------------------------------------------------------------
local minimapButton = CreateFrame("Button", "TrinketedMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Icon (Medallion of the Horde)
local mmIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
mmIcon:SetSize(21, 21)
mmIcon:SetPoint("CENTER", 0, 0)
mmIcon:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_02")
mmIcon:SetTexCoord(0.05, 0.95, 0.05, 0.95)  -- crop default icon border

-- Border overlay (standard minimap button ring)
local mmBorder = minimapButton:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT", 0, 0)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local mmDragging = false

local function UpdateMinimapButtonPos(angle)
    local rad = math.rad(angle or 220)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Default position — will be overridden from SavedVariables in ADDON_LOADED
UpdateMinimapButtonPos(220)

minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

minimapButton:SetScript("OnDragStart", function(self)
    mmDragging = true
    self:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        if TrinketedHistoryDB and TrinketedHistoryDB.minimap then
            TrinketedHistoryDB.minimap.minimapPos = angle
        end
        UpdateMinimapButtonPos(angle)
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    mmDragging = false
    self:SetScript("OnUpdate", nil)
end)

minimapButton:SetScript("OnClick", function(self, button)
    if button == "LeftButton" and IsControlKeyDown() then
        ShowExportDialog()
    elseif button == "LeftButton" then
        ToggleHistory()
    elseif button == "RightButton" then
        local count = TrinketedHistoryDB and #TrinketedHistoryDB.games or 0
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r " .. count .. " games recorded.")
        print("  /trinketed history — open game history")
        print("  /trinketed export — export game history")
        print("  /trinketed import — import game history")
        print("  /trinketed minimap — toggle minimap button")
        print("  /trinketed hdebug — toggle history debug logging")
        print("  /trinketed status — dump current state")
        print("  /trinketed dumpcleu — dump CLEU capture (live or saved game #/-1)")
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Trinketed Testing", 0, 0.8, 1)
    local count = TrinketedHistoryDB and #TrinketedHistoryDB.games or 0
    GameTooltip:AddLine(count .. " games recorded", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ff00Left-click|r to open history", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00ff00Ctrl+Left-click|r to export", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00ff00Right-click|r for commands", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("|cff00ff00Drag|r to reposition", 0.8, 0.8, 0.8)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function(self)
    GameTooltip:Hide()
end)

---------------------------------------------------------------------------
-- Export / Import  (LibDeflate zlib + EncodeForPrint)
---------------------------------------------------------------------------
local LibDeflate = LibStub("LibDeflate")

-- Minimal JSON serialiser — handles strings, numbers, booleans, nil, arrays, objects
local function JsonEscape(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    s = s:gsub("\t", "\\t")
    return s
end

local function IsArray(t)
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then
            return false
        end
    end
    return true
end

local function TableToJSON(val)
    local vtype = type(val)
    if val == nil then return "null"
    elseif vtype == "boolean" then return val and "true" or "false"
    elseif vtype == "number" then return tostring(val)
    elseif vtype == "string" then return '"' .. JsonEscape(val) .. '"'
    elseif vtype == "table" then
        local parts = {}
        if IsArray(val) then
            for i = 1, #val do
                parts[i] = TableToJSON(val[i])
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local i = 0
            for k, v in pairs(val) do
                i = i + 1
                parts[i] = '"' .. JsonEscape(tostring(k)) .. '":' .. TableToJSON(v)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

-- Minimal JSON parser (for import)
local function JSONToTable(str)
    local pos = 1
    local function skipWhitespace()
        while pos <= #str and str:sub(pos, pos):match("%s") do pos = pos + 1 end
    end
    local function parseValue()
        skipWhitespace()
        local ch = str:sub(pos, pos)
        if ch == '"' then
            -- string
            pos = pos + 1
            local start = pos
            local result = {}
            while pos <= #str do
                local c = str:sub(pos, pos)
                if c == '\\' then
                    table.insert(result, str:sub(start, pos - 1))
                    pos = pos + 1
                    local esc = str:sub(pos, pos)
                    if esc == 'n' then table.insert(result, "\n")
                    elseif esc == 'r' then table.insert(result, "\r")
                    elseif esc == 't' then table.insert(result, "\t")
                    elseif esc == '"' then table.insert(result, '"')
                    elseif esc == '\\' then table.insert(result, '\\')
                    else table.insert(result, esc) end
                    pos = pos + 1
                    start = pos
                elseif c == '"' then
                    table.insert(result, str:sub(start, pos - 1))
                    pos = pos + 1
                    return table.concat(result)
                else
                    pos = pos + 1
                end
            end
        elseif ch == '{' then
            pos = pos + 1
            local obj = {}
            skipWhitespace()
            if str:sub(pos, pos) == '}' then pos = pos + 1; return obj end
            while true do
                skipWhitespace()
                local key = parseValue() -- must be a string
                skipWhitespace()
                pos = pos + 1 -- skip ':'
                local val = parseValue()
                obj[key] = val
                skipWhitespace()
                local sep = str:sub(pos, pos)
                pos = pos + 1
                if sep == '}' then return obj end
            end
        elseif ch == '[' then
            pos = pos + 1
            local arr = {}
            skipWhitespace()
            if str:sub(pos, pos) == ']' then pos = pos + 1; return arr end
            while true do
                local val = parseValue()
                table.insert(arr, val)
                skipWhitespace()
                local sep = str:sub(pos, pos)
                pos = pos + 1
                if sep == ']' then return arr end
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4; return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5; return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4; return nil
        else
            -- number
            local numStr = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if numStr then
                pos = pos + #numStr
                return tonumber(numStr)
            end
        end
    end
    return parseValue()
end

local EXPORT_HEADER = "!TK:1!"

local function ExportHistory()
    if not TrinketedHistoryDB or not TrinketedHistoryDB.games or #TrinketedHistoryDB.games == 0 then
        return nil, "No games to export."
    end
    local data = { v = 2, t = time(), g = TrinketedHistoryDB.games }
    local json = TableToJSON(data)
    local compressed = LibDeflate:CompressZlib(json, { level = 9 })
    if not compressed then return nil, "Compression failed." end
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then return nil, "Encoding failed." end
    return EXPORT_HEADER .. encoded
end

local function ImportHistory(str)
    if not str or str == "" then return nil, "Empty import string." end
    -- Strip header
    if str:sub(1, #EXPORT_HEADER) ~= EXPORT_HEADER then
        return nil, "Invalid import string (missing !TK:1! header)."
    end
    local encoded = str:sub(#EXPORT_HEADER + 1)
    local compressed = LibDeflate:DecodeForPrint(encoded)
    if not compressed then return nil, "Decoding failed." end
    local json = LibDeflate:DecompressZlib(compressed)
    if not json then return nil, "Decompression failed." end
    local data = JSONToTable(json)
    if not data or type(data) ~= "table" or not data.g then
        return nil, "Invalid data format."
    end
    return data
end

---------------------------------------------------------------------------
-- Export / Import UI
---------------------------------------------------------------------------
local exportFrame, importFrame  -- forward declarations

ShowExportDialog = function()
    if exportFrame then exportFrame:Hide() end

    local str, err = ExportHistory()
    if not str then
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r " .. (err or "Export failed."))
        return
    end

    local count = #TrinketedHistoryDB.games
    local f = CreateFrame("Frame", "TrinketedExportFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(C.frameBg[1], C.frameBg[2], C.frameBg[3], C.frameBg[4])
    f:SetBackdropBorderColor(C.frameBorder[1], C.frameBorder[2], C.frameBorder[3], C.frameBorder[4])

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(lib.FONT_DISPLAY, 12, "")
    f.title:SetPoint("TOP", 0, -8)
    f.title:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    f.title:SetText("Trinketed Export — " .. count .. " games (" .. #str .. " chars)")

    -- Custom close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTxt:SetFont(lib.FONT_BODY, 14, "")
    closeTxt:SetPoint("CENTER")
    closeTxt:SetText("x")
    closeTxt:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end)
    closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3]) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 40)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(460)
    editBox:SetMaxLetters(0)  -- unlimited
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)

    editBox:SetText(str)
    editBox:HighlightText()
    editBox:SetFocus()

    -- Select-all on focus so Ctrl+C copies everything
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    -- Prevent typing into the export box
    editBox:SetScript("OnChar", function(self) self:SetText(str); self:HighlightText() end)

    -- Hint text
    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont(lib.FONT_BODY, 10, "")
    hint:SetPoint("BOTTOM", 0, 14)
    hint:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    hint:SetText("Ctrl+A to select all, Ctrl+C to copy")

    f:SetScript("OnHide", function(self) self:SetParent(nil) end)
    exportFrame = f
end

ShowImportDialog = function()
    if importFrame then importFrame:Hide() end

    local f = CreateFrame("Frame", "TrinketedImportFrame", UIParent, "BackdropTemplate")
    f:SetSize(520, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    f:SetBackdropColor(C.frameBg[1], C.frameBg[2], C.frameBg[3], C.frameBg[4])
    f:SetBackdropBorderColor(C.frameBorder[1], C.frameBorder[2], C.frameBorder[3], C.frameBorder[4])

    f.title = f:CreateFontString(nil, "OVERLAY")
    f.title:SetFont(lib.FONT_DISPLAY, 12, "")
    f.title:SetPoint("TOP", 0, -8)
    f.title:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    f.title:SetText("Trinketed Import — Paste string below")

    -- Custom close button
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -6)
    local closeTxt = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTxt:SetFont(lib.FONT_BODY, 14, "")
    closeTxt:SetPoint("CENTER")
    closeTxt:SetText("x")
    closeTxt:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    closeBtn:SetScript("OnEnter", function() closeTxt:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end)
    closeBtn:SetScript("OnLeave", function() closeTxt:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3]) end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local scrollFrame = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -30)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 70)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(460)
    editBox:SetMaxLetters(0)  -- unlimited
    editBox:SetAutoFocus(true)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scrollFrame:SetScrollChild(editBox)

    -- Import button
    local btn = CreateBrandButton(f, 120, 26, "Import", nil)
    btn:SetPoint("BOTTOM", 0, 14)
    btn:SetScript("OnClick", function()
        local raw = editBox:GetText():trim()
        local data, err = ImportHistory(raw)
        if not data then
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r |cffff4444Import error:|r " .. (err or "Unknown error"))
            return
        end
        -- Merge games
        TrinketedHistoryDB = TrinketedHistoryDB or { games = {} }
        TrinketedHistoryDB.games = TrinketedHistoryDB.games or {}
        local existing = {}
        for _, g in ipairs(TrinketedHistoryDB.games) do
            existing[tostring(g.startTime) .. (g.result or "")] = true
        end
        local added = 0
        for _, g in ipairs(data.g) do
            local key = tostring(g.startTime) .. (g.result or "")
            if not existing[key] then
                table.insert(TrinketedHistoryDB.games, g)
                added = added + 1
                existing[key] = true
            end
        end
        -- Sort by startTime
        table.sort(TrinketedHistoryDB.games, function(a, b) return (a.startTime or 0) < (b.startTime or 0) end)
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r Imported " .. added .. " new games (" .. #data.g .. " total in string, " .. (#data.g - added) .. " duplicates skipped).")
        if ui.built then RefreshHistory() end
        f:Hide()
    end)

    -- Hint text
    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont(lib.FONT_BODY, 10, "")
    hint:SetPoint("BOTTOM", 0, 44)
    hint:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    hint:SetText("Ctrl+V to paste, then click Import")

    f:SetScript("OnHide", function(self) self:SetParent(nil) end)
    importFrame = f
end

---------------------------------------------------------------------------
-- Event Handler
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("ARENA_OPPONENT_UPDATE")
frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:RegisterEvent("PVP_RATED_STATS_UPDATE")
frame:RegisterEvent("UPDATE_BATTLEFIELD_SCORE")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == ADDON_NAME then
            TrinketedHistoryDB = TrinketedHistoryDB or { games = {} }
            TrinketedHistoryDB.games = TrinketedHistoryDB.games or {}
            TrinketedHistoryDB.minimap = TrinketedHistoryDB.minimap or { minimapPos = 220, hide = false }
            TrinketedHistoryDB.sessionGapThreshold = TrinketedHistoryDB.sessionGapThreshold or 1200

            -- Migrate data from old TrinketedDB.games if TrinketedHistoryDB is empty
            if #TrinketedHistoryDB.games == 0 and TrinketedDB and TrinketedDB.games and #TrinketedDB.games > 0 then
                for _, g in ipairs(TrinketedDB.games) do
                    table.insert(TrinketedHistoryDB.games, g)
                end
                if TrinketedDB.minimap then
                    TrinketedHistoryDB.minimap = TrinketedDB.minimap
                end
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Migrated " .. #TrinketedHistoryDB.games .. " games from old SavedVariables.")
            end

            -- Restore minimap button position and visibility
            UpdateMinimapButtonPos(TrinketedHistoryDB.minimap.minimapPos)
            if TrinketedHistoryDB.minimap.hide then
                minimapButton:Hide()
            else
                minimapButton:Show()
            end

            -- Ensure advanced combat logging is enabled
            if GetCVar("advancedCombatLogging") ~= "1" then
                SetCVar("advancedCombatLogging", 1)
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Enabled advanced combat logging.")
            end

            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Loaded. " .. #TrinketedHistoryDB.games .. " games on record.")

            -- Recover state if we reloaded mid-arena
            local zone = GetRealZoneText()
            if ARENA_ZONES[zone] then
                inArena = true
                LoggingCombat(true)
                ResetGameState()

                -- Check if gates already opened (no prep buff = game in progress)
                local hasBuff = HasPrepBuff()
                if hasBuff then
                    -- Still in prep room
                    hadPrepBuff = true
                    dbg("Reload recovery: in prep room")
                    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Reload detected — in arena prep room.")
                else
                    -- Gates already opened, game is in progress
                    gameStarted = true
                    currentGame.startTime = time() -- approximate, we lost the real start time
                    currentGame.startTimeExact = GetTime()
                    dbg("Reload recovery: game in progress")
                    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Reload detected — arena game in progress. Resuming tracking (start time approximated).")
                end
                UpdateOverlayVisibility()

                -- Re-snapshot teams and rebuild GUID tracking
                SnapshotFriendlyTeam()
                SnapshotEnemyTeam()
                if gameStarted then
                    StartSnapshotTicker()
                end
            end
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        local zone = GetRealZoneText()
        dbg("ZONE_CHANGED_NEW_AREA:", zone, "| isArena:", tostring(ARENA_ZONES[zone] ~= nil))
        if ARENA_ZONES[zone] then
            if not inArena then
                inArena = true
                LoggingCombat(true)
                ResetGameState()
                -- Request fresh rating data so GetPersonalRatedInfo is up to date
                if RequestRatedInfo then RequestRatedInfo() end
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Entered arena — combat log started.")
            end
        else
            if inArena then
                -- Left arena zone while game in progress = LOSS
                if gameStarted and currentGame and currentGame.startTime then
                    SaveGame("LOSS")
                end
                StopSnapshotTicker()
                inArena = false
                gameStarted = false
                LoggingCombat(false)
                UpdateOverlayVisibility()
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Left arena — combat log stopped.")
            end
        end

    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit ~= "player" or not inArena or gameStarted then return end

        local hasBuff = HasPrepBuff()
        dbg("UNIT_AURA player: hasPrepBuff:", tostring(hasBuff), "hadPrepBuff:", tostring(hadPrepBuff))
        if hasBuff then
            hadPrepBuff = true
            UpdateOverlayVisibility()
        elseif hadPrepBuff and not hasBuff then
            -- Prep buff was removed = gates opened
            gameStarted = true
            currentGame.startTime = time()
            currentGame.startTimeExact = GetTime()
            -- Snapshot all bracket ratings before the game
            currentGame.ratingsBefore = SnapshotAllRatings()
            dbg("Pre-game ratings snapshot:",
                currentGame.ratingsBefore and currentGame.ratingsBefore[1] or "nil",
                currentGame.ratingsBefore and currentGame.ratingsBefore[2] or "nil",
                currentGame.ratingsBefore and currentGame.ratingsBefore[3] or "nil")
            UpdateOverlayVisibility()
            SnapshotFriendlyTeam()
            SnapshotEnemyTeam()
            StartSnapshotTicker()
            dbg("Game started! startTime:", currentGame.startTime)
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Gates open — game started.")
        end

    elseif event == "ARENA_OPPONENT_UPDATE" then
        dbg("ARENA_OPPONENT_UPDATE | inArena:", tostring(inArena))
        if inArena then
            SnapshotEnemyTeam()
            SnapshotFriendlyTeam()
        end

    elseif event == "UPDATE_BATTLEFIELD_STATUS" then
        UpdateOverlayVisibility()

        -- Check if we just queued and have unsaved data — reload to persist
        if needsReload and not inArena then
            for i = 1, GetMaxBattlefieldID() do
                local status = GetBattlefieldStatus(i)
                if status == "queued" then
                    print("|cff00ccff" .. DISPLAY_NAME .. ":|r Queue detected — reloading UI to save data...")
                    C_Timer.After(0.5, ReloadUI)
                    needsReload = false
                    return
                end
            end
        end

        local winner = GetBattlefieldWinner()
        dbg("UPDATE_BATTLEFIELD_STATUS | inArena:", tostring(inArena), "gameStarted:", tostring(gameStarted), "winner:", tostring(winner))
        if not inArena or not gameStarted then return end

        if winner then
            local playerFaction = GetBattlefieldArenaFaction()
            dbg("  winner:", winner, "playerFaction:", playerFaction)
            local matchResult = (winner == playerFaction) and "WIN" or "LOSS"
            pendingSave = matchResult
            -- Request fresh rating + scoreboard data
            if RequestRatedInfo then RequestRatedInfo() end
            if RequestBattlefieldScoreData then RequestBattlefieldScoreData() end
            -- Fallback timer: save after 2s if UPDATE_BATTLEFIELD_SCORE hasn't fired yet
            C_Timer.After(2, function()
                if pendingSave and currentGame and currentGame.startTime then
                    dbg("Fallback timer: saving game (scoreboard event didn't fire)")
                    SaveGame(pendingSave)
                    pendingSave = nil
                end
            end)
        end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not inArena or not gameStarted then return end
        local timestamp, eventType, hideCaster,
              sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
              destGUID, destName, destFlags, destRaidFlags = CombatLogGetCurrentEventInfo()

        -- Capture full CLEU event into per-game array (stop after game result determined)
        if currentGame and currentGame.cleu and currentGame.startTimeExact and not pendingSave then
            local entry = {
                math.floor((GetTime() - currentGame.startTimeExact) * 1000),  -- [1] ms offset
                eventType,     -- [2]
                sourceGUID,    -- [3]
                sourceName,    -- [4]
                sourceFlags,   -- [5]
                destGUID,      -- [6]
                destName,      -- [7]
                destFlags,     -- [8]
                select(12, CombatLogGetCurrentEventInfo())  -- [9+] spell prefix + suffix (varies by event)
            }
            table.insert(currentGame.cleu, entry)
        end

        -- Try to discover unknown GUIDs from arena/party units
        local spellID, spellName = select(12, CombatLogGetCurrentEventInfo())
        if sourceGUID and not guidToPlayer[sourceGUID] then
            DiscoverPlayerByGUID(sourceGUID)
        end
        if destGUID and destGUID ~= sourceGUID and not guidToPlayer[destGUID] then
            DiscoverPlayerByGUID(destGUID)
        end

        -- Now try spec detection on the source
        if sourceGUID and spellName and SPEC_SPELLS[spellName] and guidToPlayer[sourceGUID] then
            AssignSpec(sourceGUID, spellName)
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not inArena or not gameStarted then return end
        local unit, _, spellID = ...
        if not unit or not spellID then return end
        local guid = UnitGUID(unit)
        if not guid then return end

        -- Capture API-only spells (not in CLEU) into the combat log.
        -- Dedup: only capture once per GUID+spellID per tick (event fires for multiple unitIDs).
        -- Use 0/"" instead of nil to avoid sparse Lua arrays that break JSON serialization.
        if API_ONLY_SPELLS[spellID] and currentGame and currentGame.cleu and currentGame.startTimeExact then
            local ms = math.floor((GetTime() - currentGame.startTimeExact) * 1000)
            local dominated = false
            for i = #currentGame.cleu, math.max(1, #currentGame.cleu - 5), -1 do
                local prev = currentGame.cleu[i]
                if prev[1] == ms and prev[2] == "SPELL_CAST_SUCCESS" and prev[3] == guid and prev[9] == spellID then
                    dominated = true
                    break
                end
            end
            if not dominated then
                local spellName = GetSpellInfo(spellID)
                table.insert(currentGame.cleu, {
                    ms,
                    "SPELL_CAST_SUCCESS",
                    guid, UnitName(unit), 0,
                    "", "", 0,
                    spellID, spellName or "", 0,
                })
            end
        end

        -- Try to discover if unknown
        if not guidToPlayer[guid] then
            DiscoverPlayerByGUID(guid)
        end
        if not guidToPlayer[guid] then return end
        local spellName = GetSpellInfo(spellID)
        if spellName and SPEC_SPELLS[spellName] then
            AssignSpec(guid, spellName)
        end

    elseif event == "PVP_RATED_STATS_UPDATE" then
        -- Rating data refreshed — update pre-game snapshot if we haven't captured it yet
        if inArena and currentGame and not currentGame.ratingsBefore then
            currentGame.ratingsBefore = SnapshotAllRatings()
            dbg("Pre-game ratings (async):",
                currentGame.ratingsBefore and currentGame.ratingsBefore[1] or "nil",
                currentGame.ratingsBefore and currentGame.ratingsBefore[2] or "nil",
                currentGame.ratingsBefore and currentGame.ratingsBefore[3] or "nil")
        end

    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        dbg("UPDATE_BATTLEFIELD_SCORE fired | pendingSave:", tostring(pendingSave))
        -- Scoreboard is now available — this is the best time to save
        if pendingSave and currentGame and currentGame.startTime then
            -- Request fresh personal rating, then save after a brief delay
            -- to let PVP_RATED_STATS_UPDATE arrive
            if RequestRatedInfo then RequestRatedInfo() end
            C_Timer.After(0.5, function()
                if pendingSave and currentGame and currentGame.startTime then
                    dbg("Saving game from UPDATE_BATTLEFIELD_SCORE")
                    SaveGame(pendingSave)
                    pendingSave = nil
                end
            end)
        end
    end
end)

---------------------------------------------------------------------------
-- Sub-Command Registration (via TrinketedLib)
---------------------------------------------------------------------------
local function RegisterSubCommands()
    lib:RegisterSubCommand("history", function()
        ToggleHistory()
    end)

    lib:RegisterSubCommand("clear", function(args)
        if args == "confirm" then
            local old = TrinketedHistoryDB and #TrinketedHistoryDB.games or 0
            TrinketedHistoryDB.games = {}
            if ui.built then RefreshHistory() end
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Cleared " .. old .. " games.")
        else
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r |cffff4444This will delete ALL " .. #(TrinketedHistoryDB and TrinketedHistoryDB.games or {}) .. " recorded games.|r")
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Type |cffffffff/trinketed clear confirm|r to proceed.")
        end
    end)

    lib:RegisterSubCommand("minimap", function()
        TrinketedHistoryDB.minimap = TrinketedHistoryDB.minimap or { minimapPos = 220, hide = false }
        TrinketedHistoryDB.minimap.hide = not TrinketedHistoryDB.minimap.hide
        if TrinketedHistoryDB.minimap.hide then
            minimapButton:Hide()
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Minimap button |cffff0000hidden|r. Type /trinketed minimap to show.")
        else
            minimapButton:Show()
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Minimap button |cff00ff00shown|r.")
        end
    end)

    lib:RegisterSubCommand("export", function()
        ShowExportDialog()
    end)

    lib:RegisterSubCommand("import", function()
        ShowImportDialog()
    end)

    lib:RegisterSubCommand("hdebug", function()
        debugMode = not debugMode
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r History debug mode " .. (debugMode and "|cff00ff00ON" or "|cffff0000OFF") .. "|r")
    end)

    lib:RegisterSubCommand("sessiongap", function(args)
        if args and args ~= "" then
            local val = tonumber(args)
            if val and val >= 1 then
                TrinketedHistoryDB.sessionGapThreshold = val * 60
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Session gap set to " .. val .. " minutes (" .. (val * 60) .. "s).")
                if ui.built then RefreshHistory() end
            else
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Invalid value. Usage: /trinketed sessiongap <minutes>")
            end
        else
            local currentMins = math.floor((TrinketedHistoryDB.sessionGapThreshold or 1200) / 60)
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Session gap threshold: " .. currentMins .. " minutes (" .. (TrinketedHistoryDB.sessionGapThreshold or 1200) .. "s).")
        end
    end)

    lib:RegisterSubCommand("status", function()
        print("|cff00ccff" .. DISPLAY_NAME .. ":|r State dump:")
        print("  combatLogging:", tostring(LoggingCombat()))
        print("  inArena:", tostring(inArena))
        print("  gameStarted:", tostring(gameStarted))
        print("  hadPrepBuff:", tostring(hadPrepBuff))
        if currentGame then
            print("  startTime:", tostring(currentGame.startTime))
            print("  enemyComp:", table.concat(currentGame.enemyComp, ", "))
            print("  friendlyTeam:", #currentGame.friendlyTeam, "players")
            for j, p in ipairs(currentGame.friendlyTeam) do
                local color = CLASS_COLORS[p.class] or "ffffffff"
                print("    [" .. j .. "] |c" .. color .. p.name .. "|r - " .. (p.class or "?") .. " / " .. (p.spec or "no spec"))
            end
            print("  enemyTeam:", #currentGame.enemyTeam, "players")
            for j, p in ipairs(currentGame.enemyTeam) do
                local color = CLASS_COLORS[p.class] or "ffffffff"
                print("    [" .. j .. "] |c" .. color .. p.name .. "|r - " .. (p.class or "?") .. " / " .. (p.spec or "no spec"))
            end
            if currentGame.ratingsBefore then
                print("  ratingsBefore: 2v2=" .. tostring(currentGame.ratingsBefore[1]) ..
                    " 3v3=" .. tostring(currentGame.ratingsBefore[2]) ..
                    " 5v5=" .. tostring(currentGame.ratingsBefore[3]))
            else
                print("  ratingsBefore: not captured")
            end
            print("  bracket:", tostring(currentGame.bracket))
            print("  ratingBefore:", tostring(currentGame.ratingBefore))
            print("  ratingAfter:", tostring(currentGame.ratingAfter))
            print("  ratingChange:", tostring(currentGame.ratingChange))
            print("  enemyMMR:", tostring(currentGame.enemyMMR))
            for j, p in ipairs(currentGame.friendlyTeam) do
                if p.rating or p.mmr then
                    local color = CLASS_COLORS[p.class] or "ffffffff"
                    print("    friendly[" .. j .. "] |c" .. color .. p.name .. "|r rating=" .. tostring(p.rating) .. " mmr=" .. tostring(p.mmr) .. " change=" .. tostring(p.ratingChange))
                end
            end
            for j, p in ipairs(currentGame.enemyTeam) do
                if p.rating or p.mmr then
                    local color = CLASS_COLORS[p.class] or "ffffffff"
                    print("    enemy[" .. j .. "] |c" .. color .. p.name .. "|r rating=" .. tostring(p.rating) .. " mmr=" .. tostring(p.mmr) .. " change=" .. tostring(p.ratingChange))
                end
            end
        end
        print("  debugMode:", tostring(debugMode))
        print("  GetPersonalRatedInfo:", tostring(GetPersonalRatedInfo ~= nil))
        print("  RequestRatedInfo:", tostring(RequestRatedInfo ~= nil))
        print("  GetBattlefieldScore:", tostring(GetBattlefieldScore ~= nil))
        print("  GetBattlefieldTeamInfo:", tostring(GetBattlefieldTeamInfo ~= nil))
        print("  GetArenaOpponentSpec:", tostring(GetArenaOpponentSpec ~= nil))
        print("  GetSpecializationInfoByID:", tostring(GetSpecializationInfoByID ~= nil))
        print("  GetNumArenaOpponentSpecs:", tostring(GetNumArenaOpponentSpecs ~= nil))
        if GetPersonalRatedInfo then
            if RequestRatedInfo then RequestRatedInfo() end
            for bracket, ratedIdx in pairs(BRACKET_TO_RATED_INDEX) do
                local r1, r2, r3, r4, r5, r6, r7, r8, r9, r10, r11, r12 = GetPersonalRatedInfo(ratedIdx)
                print("  PersonalRatedInfo[" .. bracket .. "v" .. bracket .. "] (idx=" .. ratedIdx .. "):")
                print("    ret1=" .. tostring(r1) .. "  ret2=" .. tostring(r2) ..
                    "  ret3=" .. tostring(r3) .. "  ret4=" .. tostring(r4))
                print("    ret5=" .. tostring(r5) .. "  ret6=" .. tostring(r6) ..
                    "  ret7=" .. tostring(r7) .. "  ret8=" .. tostring(r8))
                if r9 ~= nil or r10 ~= nil or r11 ~= nil or r12 ~= nil then
                    print("    ret9=" .. tostring(r9) .. "  ret10=" .. tostring(r10) ..
                        "  ret11=" .. tostring(r11) .. "  ret12=" .. tostring(r12))
                end
            end
        else
            print("  PersonalRatedInfo: API not available")
        end
        local liveBracket = GetCurrentArenaBracket()
        print("  activeBracket:", tostring(liveBracket))
        for i = 1, GetMaxBattlefieldID() do
            local status, mapName, teamSize, registeredMatch, suspendedQueue, queueType, gameType = GetBattlefieldStatus(i)
            if status and status ~= "none" then
                print("  BattlefieldStatus[" .. i .. "]: status=" .. tostring(status) ..
                    " map=" .. tostring(mapName) .. " teamSize=" .. tostring(teamSize) ..
                    " registered=" .. tostring(registeredMatch) ..
                    " queueType=" .. tostring(queueType) .. " gameType=" .. tostring(gameType))
            end
        end
        if GetBattlefieldTeamInfo then
            for fi = 0, 1 do
                local tName, oldR, newR, mmr = GetBattlefieldTeamInfo(fi)
                if tName and tName ~= "" then
                    print("  BattlefieldTeamInfo[" .. fi .. "]: team=\"" .. tName ..
                        "\" old=" .. tostring(oldR) .. " new=" .. tostring(newR) ..
                        " mmr=" .. tostring(mmr))
                end
            end
        end
        if GetBattlefieldScore and GetNumBattlefieldScores then
            local numScores = GetNumBattlefieldScores()
            if numScores and numScores > 0 then
                print("  BattlefieldScores: " .. numScores .. " entries")
                for si = 1, numScores do
                    local name, _, _, _, _, _, _, _, _, _, _, bgRating, ratingChange, preMatchMMR, mmrChange = GetBattlefieldScore(si)
                    if name then
                        print("    [" .. si .. "] " .. name ..
                            " rating=" .. tostring(bgRating) .. " change=" .. tostring(ratingChange) ..
                            " mmr=" .. tostring(preMatchMMR) .. " mmrChange=" .. tostring(mmrChange))
                    end
                end
            end
        end
        if inArena and GetArenaOpponentSpec then
            local numSpecs = GetNumArenaOpponentSpecs and GetNumArenaOpponentSpecs() or 0
            print("  numArenaOpponentSpecs:", numSpecs)
            for i = 1, 5 do
                local specID = GetArenaOpponentSpec(i)
                local specName = "N/A"
                if specID and specID > 0 and GetSpecializationInfoByID then
                    local _, sn = GetSpecializationInfoByID(specID)
                    specName = sn or ("specID=" .. specID)
                end
                local aName = UnitName("arena" .. i)
                if aName then
                    print("    arena" .. i .. ": specID=" .. tostring(specID) .. " (" .. specName .. ") - " .. aName)
                end
            end
        end
    end)

    lib:RegisterSubCommand("dumpcleu", function(args)
        -- Dump CLEU capture state for debugging
        local gameIdx = nil
        if args and args ~= "" then
            gameIdx = tonumber(args)
        end

        if gameIdx then
            -- Dump from a saved game
            if not TrinketedHistoryDB or not TrinketedHistoryDB.games then
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r No saved games.")
                return
            end
            -- Negative index counts from end (-1 = last game)
            if gameIdx < 0 then
                gameIdx = #TrinketedHistoryDB.games + gameIdx + 1
            end
            if gameIdx < 1 or gameIdx > #TrinketedHistoryDB.games then
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Game index out of range (1-" .. #TrinketedHistoryDB.games .. ")")
                return
            end
            local game = TrinketedHistoryDB.games[gameIdx]
            local cleu = game.cleu
            if not cleu or #cleu == 0 then
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Game #" .. gameIdx .. " has no CLEU data.")
                return
            end
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Game #" .. gameIdx .. " CLEU dump (" .. #cleu .. " events):")
            local showCount = math.min(10, #cleu)
            for i = 1, showCount do
                local entry = cleu[i]
                local parts = {}
                for j = 1, math.min(#entry, 12) do
                    parts[j] = tostring(entry[j])
                end
                local suffix = ""
                if #entry > 12 then
                    suffix = " ... (+" .. (#entry - 12) .. " more)"
                end
                print("  [" .. i .. "] " .. table.concat(parts, ", ") .. suffix)
            end
            if #cleu > showCount then
                print("  ... (" .. (#cleu - showCount) .. " more events)")
            end
            -- Show last event too if there are many
            if #cleu > showCount then
                local last = cleu[#cleu]
                local parts = {}
                for j = 1, math.min(#last, 12) do
                    parts[j] = tostring(last[j])
                end
                print("  [" .. #cleu .. "] " .. table.concat(parts, ", "))
            end
        else
            -- Dump live state
            if not currentGame then
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r No active game.")
                return
            end
            local cleu = currentGame.cleu
            if not cleu or #cleu == 0 then
                print("|cff00ccff" .. DISPLAY_NAME .. ":|r Active game has 0 CLEU events captured.")
                print("  startTimeExact:", tostring(currentGame.startTimeExact))
                return
            end
            print("|cff00ccff" .. DISPLAY_NAME .. ":|r Active game CLEU: " .. #cleu .. " events captured")
            print("  startTimeExact:", tostring(currentGame.startTimeExact))
            -- Show first 5 and last entry
            local showCount = math.min(5, #cleu)
            for i = 1, showCount do
                local entry = cleu[i]
                local parts = {}
                for j = 1, math.min(#entry, 12) do
                    parts[j] = tostring(entry[j])
                end
                local suffix = ""
                if #entry > 12 then
                    suffix = " ... (+" .. (#entry - 12) .. " more)"
                end
                print("  [" .. i .. "] " .. table.concat(parts, ", ") .. suffix)
            end
            if #cleu > showCount then
                print("  ... (" .. (#cleu - showCount) .. " more events)")
                local last = cleu[#cleu]
                local parts = {}
                for j = 1, math.min(#last, 12) do
                    parts[j] = tostring(last[j])
                end
                print("  [" .. #cleu .. "] " .. table.concat(parts, ", "))
            end
        end
    end)
end

---------------------------------------------------------------------------
-- Register with Trinketed Options Panel
---------------------------------------------------------------------------
lib:RegisterSubAddon("History", {
    order = 2,
    OnSelect = function(contentFrame)
        BuildHistoryUI(contentFrame)
        contentFrame:SetScript("OnShow", function() RefreshHistory() end)
        RefreshHistory()
    end,
})

RegisterSubCommands()
