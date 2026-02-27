---------------------------------------------------------------------------
-- TrinketedHistory: Core.lua
-- Arena match history tracking, VOD timestamp overlay, export/import
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local ARENA_ZONES = {
    ["Nagrand Arena"] = true,
    ["Blade's Edge Arena"] = true,
    ["Ruins of Lordaeron"] = true,
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
        map = GetRealZoneText(),
        enemyComp = {},
        result = nil,
        friendlyTeam = {},
        enemyTeam = {},
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

---------------------------------------------------------------------------
-- Session Computation
---------------------------------------------------------------------------
local SESSION_GAP_SECONDS = 3600  -- 60 minutes

-- Build a sorted slash-separated key from the friendly team, excluding self.
local function GetPartnerKey(game)
    local me = UnitName("player")
    local names = {}
    for _, p in ipairs(game.friendlyTeam or {}) do
        if p.name ~= me then
            table.insert(names, p.name)
        end
    end
    table.sort(names)
    return table.concat(names, "/")
end

-- Group a games array into sessions based on time gaps and partner changes.
-- bracketFilter: "2v2", "3v3", "5v5", or nil (all)
-- daysFilter:    0 or nil = all time, 7/30/90 = last N days
-- Returns an array of session objects sorted chronologically (oldest first).
local function ComputeSessions(games, bracketFilter, daysFilter)
    if not games or #games == 0 then return {} end

    -- Determine cutoff timestamp for daysFilter
    local cutoff = 0
    if daysFilter and daysFilter > 0 then
        cutoff = time() - (daysFilter * 86400)
    end

    -- Filter games
    local filtered = {}
    for _, g in ipairs(games) do
        local dominated = true
        if bracketFilter and g.bracket ~= bracketFilter then
            dominated = false
        end
        if dominated and cutoff > 0 and (g.startTime or 0) < cutoff then
            dominated = false
        end
        if dominated then
            table.insert(filtered, g)
        end
    end

    if #filtered == 0 then return {} end

    -- Sort chronologically (oldest first)
    table.sort(filtered, function(a, b)
        return (a.startTime or 0) < (b.startTime or 0)
    end)

    -- Walk through filtered games and group into sessions
    local sessions = {}
    local cur = nil  -- current session being built

    for _, g in ipairs(filtered) do
        local pk = GetPartnerKey(g)
        local needNew = false

        if not cur then
            needNew = true
        else
            local gap = (g.startTime or 0) - (cur.endTime or 0)
            if gap > SESSION_GAP_SECONDS then
                needNew = true
            elseif pk ~= cur.partnerKey then
                needNew = true
            end
        end

        if needNew then
            -- Finalise previous session if any (aggregates computed later)
            if cur then
                table.insert(sessions, cur)
            end
            cur = {
                games     = {},
                startTime = g.startTime,
                endTime   = g.endTime,
                bracket   = g.bracket,
                partnerKey = pk,
            }
        else
            -- Extend current session
            cur.endTime = g.endTime
            if cur.bracket ~= g.bracket then
                cur.bracket = "Mixed"
            end
        end

        table.insert(cur.games, g)
    end

    -- Don't forget the last session
    if cur then
        table.insert(sessions, cur)
    end

    -- Compute aggregates for each session
    local me = UnitName("player")
    for _, s in ipairs(sessions) do
        local wins, losses = 0, 0
        local totalRatingChange = 0

        for _, g in ipairs(s.games) do
            if g.result == "WIN" then
                wins = wins + 1
            elseif g.result == "LOSS" then
                losses = losses + 1
            end
            totalRatingChange = totalRatingChange + (g.ratingChange or 0)
        end

        s.wins         = wins
        s.losses       = losses
        s.ratingChange = totalRatingChange
        s.ratingStart  = s.games[1].ratingBefore
        s.ratingEnd    = s.games[#s.games].ratingAfter

        -- Collect unique partners (friendly team members excluding self)
        local seen = {}
        local partners = {}
        for _, g in ipairs(s.games) do
            for _, p in ipairs(g.friendlyTeam or {}) do
                if p.name ~= me and not seen[p.name] then
                    seen[p.name] = true
                    table.insert(partners, { name = p.name, class = p.class })
                end
            end
        end
        s.partners = partners
    end

    return sessions
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
-- History Window
---------------------------------------------------------------------------
local historyFrame = CreateFrame("Frame", "TrinketedHistoryFrame", UIParent, "BasicFrameTemplateWithInset")
historyFrame:SetSize(800, 560)
historyFrame:SetPoint("CENTER")
historyFrame:SetFrameStrata("DIALOG")
historyFrame:SetMovable(true)
historyFrame:EnableMouse(true)
historyFrame:RegisterForDrag("LeftButton")
historyFrame:SetScript("OnDragStart", historyFrame.StartMoving)
historyFrame:SetScript("OnDragStop", historyFrame.StopMovingOrSizing)
historyFrame:Hide()

historyFrame.title = historyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
historyFrame.title:SetPoint("TOP", 0, -5)
historyFrame.title:SetText("Trinketed — Arena History")

---------------------------------------------------------------------------
-- Tab Bar
---------------------------------------------------------------------------
local activeTab = "matches" -- "matches" or "sessions"

-- Container frame for Matches tab content
local matchesContainer = CreateFrame("Frame", nil, historyFrame)
matchesContainer:SetPoint("TOPLEFT", 0, 0)
matchesContainer:SetPoint("BOTTOMRIGHT", 0, 0)

-- Container frame for Sessions tab content
local sessionsContainer = CreateFrame("Frame", nil, historyFrame)
sessionsContainer:SetPoint("TOPLEFT", 0, 0)
sessionsContainer:SetPoint("BOTTOMRIGHT", 0, 0)
sessionsContainer:Hide()

local function CreateTab(parent, text, tabKey)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(80, 22)

    tab.bg = tab:CreateTexture(nil, "BACKGROUND")
    tab.bg:SetAllPoints()

    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tab.label:SetPoint("CENTER", 0, 0)
    tab.label:SetText(text)

    tab.tabKey = tabKey

    tab:SetScript("OnEnter", function(self)
        if activeTab ~= self.tabKey then
            self.bg:SetColorTexture(0.15, 0.15, 0.15, 1)
        end
    end)
    tab:SetScript("OnLeave", function(self)
        if activeTab ~= self.tabKey then
            self.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        end
    end)

    return tab
end

local matchesTab = CreateTab(historyFrame, "Matches", "matches")
matchesTab:SetPoint("TOPLEFT", 12, -22)

local sessionsTab = CreateTab(historyFrame, "Sessions", "sessions")
sessionsTab:SetPoint("LEFT", matchesTab, "RIGHT", 4, 0)

-- Forward declarations for tab refresh functions
local RefreshHistory
local RefreshSessions

local function UpdateTabAppearance()
    if activeTab == "matches" then
        matchesTab.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
        matchesTab.label:SetTextColor(1, 1, 1)
        sessionsTab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        sessionsTab.label:SetTextColor(0.6, 0.6, 0.6)
    else
        sessionsTab.bg:SetColorTexture(0.2, 0.2, 0.2, 1)
        sessionsTab.label:SetTextColor(1, 1, 1)
        matchesTab.bg:SetColorTexture(0.1, 0.1, 0.1, 0.5)
        matchesTab.label:SetTextColor(0.6, 0.6, 0.6)
    end
end

local function SwitchTab(tabKey)
    activeTab = tabKey
    UpdateTabAppearance()
    if tabKey == "matches" then
        matchesContainer:Show()
        sessionsContainer:Hide()
        RefreshHistory()
    else
        matchesContainer:Hide()
        sessionsContainer:Show()
        if RefreshSessions then RefreshSessions() end
    end
end

matchesTab:SetScript("OnClick", function() SwitchTab("matches") end)
sessionsTab:SetScript("OnClick", function() SwitchTab("sessions") end)

UpdateTabAppearance()

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
    btnBg:SetColorTexture(0.1, 0.1, 0.1, 1)

    local bdr = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    bdr:SetAllPoints()
    bdr:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    bdr:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    popBg:SetColorTexture(0.05, 0.05, 0.05, 1)
    popup:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    popup:Hide()

    -- "Clear All" button
    local clrBtn = CreateFrame("Button", nil, popup)
    clrBtn:SetSize(width + 10, SD_ROW_H)
    clrBtn:SetPoint("TOPLEFT", 5, -5)
    local clrTxt = clrBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clrTxt:SetPoint("LEFT", 4, 0)
    clrTxt:SetText("|cffaaaaaaAll (clear)|r")
    local clrHL = clrBtn:CreateTexture(nil, "HIGHLIGHT")
    clrHL:SetAllPoints()
    clrHL:SetColorTexture(1, 1, 1, 0.1)
    clrBtn:SetScript("OnClick", function()
        if opts.onClear then opts.onClear() end
        dd:Refresh()
    end)

    -- Search box
    local sBox = CreateFrame("EditBox", ddName .. "Srch", popup, "InputBoxTemplate")
    sBox:SetSize(width + 4, 18)
    sBox:SetPoint("TOPLEFT", 8, -5 - SD_ROW_H - 2)
    sBox:SetAutoFocus(false)
    sBox:SetFontObject("GameFontNormalSmall")
    local sPH = sBox:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
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
        hl:SetColorTexture(1, 1, 1, 0.1)
        r.chk = r:CreateTexture(nil, "OVERLAY")
        r.chk:SetSize(12, 12)
        r.chk:SetPoint("LEFT", 2, 0)
        r.txt = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
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
    btn:SetScript("OnEnter", function() btnBg:SetColorTexture(0.15, 0.15, 0.15, 1) end)
    btn:SetScript("OnLeave", function() btnBg:SetColorTexture(0.1, 0.1, 0.1, 1) end)

    return dd
end

---------------------------------------------------------------------------
-- Filter Row 1: Player Comp | Partner | Enemy Comp
---------------------------------------------------------------------------
local friendlyCompDD = CreateSearchableDropdown(matchesContainer, "TkCompDD", 155, {
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
friendlyCompDD.frame:SetPoint("TOPLEFT", 12, -48)

local partnerDD = CreateSearchableDropdown(matchesContainer, "TkPartDD", 155, {
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
partnerDD.frame:SetPoint("TOPLEFT", 177, -48)

local enemyCompDD = CreateSearchableDropdown(matchesContainer, "TkECompDD", 155, {
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
enemyCompDD.frame:SetPoint("TOPLEFT", 342, -48)

---------------------------------------------------------------------------
-- Filter Row 2: Enemy Players | Enemy Race | Result | Reset
---------------------------------------------------------------------------
local enemyPlayerDD = CreateSearchableDropdown(matchesContainer, "TkEPlrDD", 155, {
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
enemyPlayerDD.frame:SetPoint("TOPLEFT", 12, -74)

local enemyRaceDD = CreateSearchableDropdown(matchesContainer, "TkERaceDD", 155, {
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
enemyRaceDD.frame:SetPoint("TOPLEFT", 177, -74)

local resultDD = CreateSearchableDropdown(matchesContainer, "TkResultDD", 155, {
    defaultLabel = "Result: All",
    getOptions = function()
        return {
            { key = "WIN",  text = "|cff00ff00WIN|r",  searchText = "win",  isChecked = function() return filters.result == "WIN" end },
            { key = "LOSS", text = "|cffff0000LOSS|r", searchText = "loss", isChecked = function() return filters.result == "LOSS" end },
        }
    end,
    onToggle = function(key)
        -- Single-select toggle: clicking the active one clears it, otherwise sets it
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
resultDD.frame:SetPoint("TOPLEFT", 342, -74)

local exportBtn = CreateFrame("Button", nil, matchesContainer, "UIPanelButtonTemplate")
exportBtn:SetSize(60, 22)
exportBtn:SetPoint("TOPRIGHT", -80, -78)
exportBtn:SetNormalFontObject("GameFontNormalSmall")
exportBtn:SetHighlightFontObject("GameFontHighlightSmall")
exportBtn:SetText("Export")
exportBtn:SetScript("OnClick", function() ShowExportDialog() end)

local resetBtn = CreateFrame("Button", nil, matchesContainer, "UIPanelButtonTemplate")
resetBtn:SetSize(60, 22)
resetBtn:SetPoint("TOPRIGHT", -16, -78)
resetBtn:SetNormalFontObject("GameFontNormalSmall")
resetBtn:SetHighlightFontObject("GameFontHighlightSmall")
resetBtn:SetText("Reset")
resetBtn:SetScript("OnClick", function()
    filters.friendlyComps = {}
    filters.partners = {}
    filters.enemyComps = {}
    filters.enemyPlayers = {}
    filters.enemyRaces = {}
    filters.result = nil
    friendlyCompDD:SetLabel("Player Comp: All")
    partnerDD:SetLabel("Partner: All")
    enemyCompDD:SetLabel("Enemy Comp: All")
    enemyPlayerDD:SetLabel("Enemy Players: All")
    enemyRaceDD:SetLabel("Race: All")
    resultDD:SetLabel("Result: All")
    RefreshHistory()
end)

-- Column headers
local headerY = -104
local headers = {
    { text = "#",        x = 4,   w = 24, justify = "RIGHT" },
    { text = "Result",   x = 32,  w = 36, justify = "LEFT" },
    { text = "Friendly", x = 68,  w = 210, justify = "LEFT" },
    { text = "",         x = 282, w = 20, justify = "CENTER" },  -- vs column (no header)
    { text = "Enemy",    x = 305, w = 210, justify = "LEFT" },
    { text = "Rating",   x = 520, w = 95, justify = "CENTER" },
    { text = "Dur",      x = 620, w = 45, justify = "LEFT" },
    { text = "Time",     x = 670, w = 60, justify = "RIGHT" },
}
for _, h in ipairs(headers) do
    if h.text ~= "" then
        local fs = matchesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h.x, headerY)
        fs:SetWidth(h.w)
        fs:SetJustifyH(h.justify)
        fs:SetWordWrap(false)
        fs:SetText("|cff888888" .. h.text .. "|r")
    end
end

-- Thin separator line below headers
local headerSep = matchesContainer:CreateTexture(nil, "ARTWORK")
headerSep:SetHeight(1)
headerSep:SetPoint("TOPLEFT", 4, headerY - 12)
headerSep:SetPoint("TOPRIGHT", -16, headerY - 12)
headerSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)

-- Scroll frame
local scrollFrame = CreateFrame("ScrollFrame", nil, matchesContainer, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 10, headerY - 14)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 100)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(740, 1) -- height grows dynamically
scrollFrame:SetScrollChild(content)

---------------------------------------------------------------------------
-- Stats Panel (bottom of history window)
---------------------------------------------------------------------------
local statsSep = matchesContainer:CreateTexture(nil, "ARTWORK")
statsSep:SetHeight(1)
statsSep:SetPoint("BOTTOMLEFT", 8, 90)
statsSep:SetPoint("BOTTOMRIGHT", -16, 90)
statsSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)

local bestHeader = matchesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
bestHeader:SetPoint("BOTTOMLEFT", 14, 72)
bestHeader:SetText("|cff00ff00Best Matchups|r")

local worstHeader = matchesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
worstHeader:SetPoint("BOTTOMLEFT", 380, 72)
worstHeader:SetText("|cffff4444Worst Matchups|r")

local NUM_STAT_ROWS = 5
local STAT_COL_COMP = 0      -- comp name offset from row left
local STAT_COL_RECORD = 175  -- W/L record offset
local STAT_COL_PCT = 235     -- percentage offset
local STAT_COL_BAR = 270     -- win% bar offset
local STAT_BAR_WIDTH = 70    -- max bar width
local STAT_ROW_WIDTH = 350

local function CreateStatRow(parent, x, y)
    local row = {}

    row.comp = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.comp:SetPoint("BOTTOMLEFT", x + STAT_COL_COMP, y)
    row.comp:SetWidth(170)
    row.comp:SetJustifyH("LEFT")
    row.comp:SetWordWrap(false)

    row.record = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.record:SetPoint("BOTTOMLEFT", x + STAT_COL_RECORD, y)
    row.record:SetWidth(55)
    row.record:SetJustifyH("LEFT")
    row.record:SetWordWrap(false)

    row.pct = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pct:SetPoint("BOTTOMLEFT", x + STAT_COL_PCT, y)
    row.pct:SetWidth(35)
    row.pct:SetJustifyH("RIGHT")
    row.pct:SetWordWrap(false)

    -- Win% bar background (dark)
    row.barBg = parent:CreateTexture(nil, "ARTWORK")
    row.barBg:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x + STAT_COL_BAR, y + 1)
    row.barBg:SetSize(STAT_BAR_WIDTH, 8)
    row.barBg:SetColorTexture(0.15, 0.15, 0.15, 1)

    -- Win% bar fill
    row.barFill = parent:CreateTexture(nil, "OVERLAY")
    row.barFill:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x + STAT_COL_BAR, y + 1)
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

local bestRows = {}
local worstRows = {}
for i = 1, NUM_STAT_ROWS do
    local y = 72 - i * 12
    bestRows[i] = CreateStatRow(matchesContainer, 14, y)
    worstRows[i] = CreateStatRow(matchesContainer, 380, y)
end

local function RefreshStats(filteredList)
    -- Tally wins/losses per enemy comp from the filtered list
    local compStats = {} -- compKey → { wins, losses }
    for _, entry in ipairs(filteredList) do
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
    end

    -- Build sorted list
    local compList = {}
    for comp, stats in pairs(compStats) do
        local total = stats.wins + stats.losses
        local winPct = (total > 0) and (stats.wins / total * 100) or 0
        table.insert(compList, { comp = comp, wins = stats.wins, losses = stats.losses, total = total, pct = winPct })
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
        bestRows[i]:SetData(best[i])
        worstRows[i]:SetData(worst[i])
    end
end

local function FormatDuration(seconds)
    if not seconds or seconds < 0 then return "--:--" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
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

function RefreshHistory()
    -- Recycle existing rows
    for _, row in ipairs(rowPool) do
        row:Hide()
    end

    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}

    -- Apply filters — build list of {originalIndex, game} pairs, newest first
    local filtered = {}
    for i = #allGames, 1, -1 do
        if GameMatchesFilters(allGames[i]) then
            table.insert(filtered, { idx = i, game = allGames[i] })
        end
    end

    local totalHeight = 0

    for displayIdx = 1, #filtered do
        local i = filtered[displayIdx].idx
        local game = filtered[displayIdx].game

        local row = rowPool[displayIdx]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetSize(740, ROW_HEIGHT)
            rowPool[displayIdx] = row

            row.index = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.index:SetPoint("LEFT", 4, 0)
            row.index:SetWidth(24)
            row.index:SetJustifyH("RIGHT")

            row.result = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.result:SetPoint("LEFT", 32, 0)
            row.result:SetWidth(32)

            row.friendly = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.friendly:SetPoint("LEFT", 68, 0)
            row.friendly:SetWidth(210)
            row.friendly:SetJustifyH("LEFT")
            row.friendly:SetMaxLines(2)
            row.friendly:SetNonSpaceWrap(false)
            row.friendly:SetWordWrap(true)

            row.vs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.vs:SetPoint("LEFT", 282, 0)
            row.vs:SetWidth(20)
            row.vs:SetJustifyH("CENTER")
            row.vs:SetTextColor(0.4, 0.4, 0.4)

            row.enemy = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.enemy:SetPoint("LEFT", 305, 0)
            row.enemy:SetWidth(210)
            row.enemy:SetJustifyH("LEFT")
            row.enemy:SetMaxLines(2)
            row.enemy:SetNonSpaceWrap(false)
            row.enemy:SetWordWrap(true)

            row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.rating:SetPoint("LEFT", 520, 0)
            row.rating:SetWidth(95)
            row.rating:SetJustifyH("CENTER")

            row.duration = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.duration:SetPoint("LEFT", 620, 0)
            row.duration:SetWidth(45)
            row.duration:SetJustifyH("CENTER")

            row.timeStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.timeStr:SetPoint("LEFT", 670, 0)
            row.timeStr:SetWidth(60)
            row.timeStr:SetJustifyH("RIGHT")

            -- Alternating background
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
        end

        row:SetPoint("TOPLEFT", 0, -((displayIdx - 1) * ROW_HEIGHT))

        -- Alternating row color
        if displayIdx % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.05)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.index:SetText("#" .. i)
        row.index:SetTextColor(0.5, 0.5, 0.5)

        if game.result == "WIN" then
            row.result:SetText("|cff00ff00WIN|r")
        else
            row.result:SetText("|cffff0000LOSS|r")
        end

        -- Friendly team — show class-colored names
        local friendlyStr = FormatTeamNames(game.friendlyTeam)
        row.friendly:SetText(friendlyStr or "—")

        row.vs:SetText("vs")

        -- Enemy team — prefer names, fall back to class-only from enemyComp
        local enemyStr = FormatTeamNames(game.enemyTeam)
        if not enemyStr then
            local parts = {}
            for _, class in ipairs(game.enemyComp or {}) do
                table.insert(parts, ColorClass(class))
            end
            enemyStr = #parts > 0 and table.concat(parts, " ") or "?"
        end
        row.enemy:SetText(enemyStr)

        -- Rating: show change + enemy MMR (e.g., "+16 vs 1820")
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
        row.duration:SetTextColor(0.8, 0.8, 0.8)

        row.timeStr:SetText(FormatTime(game.startTime))
        row.timeStr:SetTextColor(0.6, 0.6, 0.6)

        row:Show()
        totalHeight = totalHeight + ROW_HEIGHT
    end

    content:SetHeight(math.max(totalHeight, 1))

    -- Update title with win/loss count and net rating (from filtered results)
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
    historyFrame.title:SetText("Trinketed — " .. countStr .. " (" ..
        "|cff00ff00" .. wins .. "W|r / |cffff0000" .. losses .. "L|r)" .. ratingStr)

    -- Update stats panel
    RefreshStats(filtered)
end

---------------------------------------------------------------------------
-- Sessions Tab Content
---------------------------------------------------------------------------
local sessionFilters = {
    bracket = "All",
    days = 0,
}

local sessionBracketDD = CreateSearchableDropdown(sessionsContainer, "TkSBracketDD", 120, {
    defaultLabel = "Bracket: All",
    getOptions = function()
        local out = {}
        local brackets = { "2v2", "3v3", "5v5" }
        for _, b in ipairs(brackets) do
            table.insert(out, {
                key = b,
                text = b,
                searchText = b:lower(),
                isChecked = function() return sessionFilters.bracket == b end,
            })
        end
        return out
    end,
    onToggle = function(key)
        if sessionFilters.bracket == key then
            sessionFilters.bracket = "All"
        else
            sessionFilters.bracket = key
        end
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function()
        sessionFilters.bracket = "All"
        if RefreshSessions then RefreshSessions() end
    end,
    getLabel = function()
        if sessionFilters.bracket == "All" then return "Bracket: All" end
        return "Bracket: " .. sessionFilters.bracket
    end,
})
sessionBracketDD.frame:SetPoint("TOPLEFT", sessionsContainer, "TOPLEFT", 12, -24)

local sessionDaysDD = CreateSearchableDropdown(sessionsContainer, "TkSDaysDD", 120, {
    defaultLabel = "Time: All",
    getOptions = function()
        local out = {}
        local dayOpts = {
            { key = "7",  text = "Last 7 Days" },
            { key = "30", text = "Last 30 Days" },
            { key = "90", text = "Last 90 Days" },
        }
        for _, d in ipairs(dayOpts) do
            table.insert(out, {
                key = d.key,
                text = d.text,
                searchText = d.text:lower(),
                isChecked = function() return sessionFilters.days == tonumber(d.key) end,
            })
        end
        return out
    end,
    onToggle = function(key)
        local val = tonumber(key)
        if sessionFilters.days == val then
            sessionFilters.days = 0
        else
            sessionFilters.days = val
        end
        if RefreshSessions then RefreshSessions() end
    end,
    onClear = function()
        sessionFilters.days = 0
        if RefreshSessions then RefreshSessions() end
    end,
    getLabel = function()
        if sessionFilters.days == 0 then return "Time: All" end
        return "Last " .. sessionFilters.days .. " Days"
    end,
})
sessionDaysDD.frame:SetPoint("LEFT", sessionBracketDD.frame, "RIGHT", 10, 0)

-- Session column headers
local sessionHeaderY = -54
local sessionHeaders = {
    { text = "#",        x = 4,   w = 24,  justify = "RIGHT" },
    { text = "Date",     x = 32,  w = 100, justify = "LEFT" },
    { text = "Partners", x = 136, w = 160, justify = "LEFT" },
    { text = "Bracket",  x = 300, w = 50,  justify = "CENTER" },
    { text = "Games",    x = 355, w = 40,  justify = "CENTER" },
    { text = "W-L",      x = 400, w = 50,  justify = "CENTER" },
    { text = "Win%",     x = 455, w = 45,  justify = "CENTER" },
    { text = "Rating",   x = 505, w = 120, justify = "CENTER" },
    { text = "Net",      x = 630, w = 50,  justify = "CENTER" },
}
for _, h in ipairs(sessionHeaders) do
    if h.text ~= "" then
        local fs = sessionsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", h.x, sessionHeaderY)
        fs:SetWidth(h.w)
        fs:SetJustifyH(h.justify)
        fs:SetWordWrap(false)
        fs:SetText("|cff888888" .. h.text .. "|r")
    end
end

-- Thin separator line below session headers
local sessHeaderSep = sessionsContainer:CreateTexture(nil, "ARTWORK")
sessHeaderSep:SetHeight(1)
sessHeaderSep:SetPoint("TOPLEFT", 4, sessionHeaderY - 12)
sessHeaderSep:SetPoint("TOPRIGHT", -16, sessionHeaderY - 12)
sessHeaderSep:SetColorTexture(0.4, 0.4, 0.4, 0.5)

-- Sessions scroll frame
local sessScrollFrame = CreateFrame("ScrollFrame", nil, sessionsContainer, "UIPanelScrollFrameTemplate")
sessScrollFrame:SetPoint("TOPLEFT", 10, sessionHeaderY - 14)
sessScrollFrame:SetPoint("BOTTOMRIGHT", -30, 10)

local sessContent = CreateFrame("Frame", nil, sessScrollFrame)
sessContent:SetSize(740, 1)
sessScrollFrame:SetScrollChild(sessContent)

local SESSION_ROW_HEIGHT = 28
local MATCH_ROW_HEIGHT = 26
local sessionRowPool = {}   -- session summary rows
local matchDrillPool = {}   -- match drill-down rows
local expandedSession = nil -- stores startTime of expanded session for stable identity

---------------------------------------------------------------------------
-- RefreshSessions
---------------------------------------------------------------------------
function RefreshSessions()
    -- Recycle existing rows
    for _, row in ipairs(sessionRowPool) do
        row:Hide()
    end
    for _, row in ipairs(matchDrillPool) do
        row:Hide()
    end

    local allGames = TrinketedHistoryDB and TrinketedHistoryDB.games or {}

    -- Build filter args
    local bracketFilter = sessionFilters.bracket ~= "All" and sessionFilters.bracket or nil
    local daysFilter = sessionFilters.days

    local sessions = ComputeSessions(allGames, bracketFilter, daysFilter)

    local totalHeight = 0
    local rowIdx = 0
    local matchRowIdx = 0
    local totalGames = 0
    local totalWins = 0
    local totalLosses = 0
    local totalNetRating = 0
    local hasRating = false

    -- Render sessions newest-first
    local displayNum = 0
    for si = #sessions, 1, -1 do
        displayNum = displayNum + 1
        local s = sessions[si]
        rowIdx = rowIdx + 1

        totalGames = totalGames + #s.games
        totalWins = totalWins + s.wins
        totalLosses = totalLosses + s.losses
        totalNetRating = totalNetRating + s.ratingChange
        if s.ratingStart or s.ratingEnd then hasRating = true end

        -- Create or reuse session row (Button for clickability)
        local row = sessionRowPool[rowIdx]
        if not row then
            row = CreateFrame("Button", nil, sessContent)
            row:SetSize(740, SESSION_ROW_HEIGHT)
            sessionRowPool[rowIdx] = row

            row.index = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.index:SetPoint("LEFT", 4, 0)
            row.index:SetWidth(24)
            row.index:SetJustifyH("RIGHT")

            row.dateStr = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.dateStr:SetPoint("LEFT", 32, 0)
            row.dateStr:SetWidth(100)
            row.dateStr:SetJustifyH("LEFT")
            row.dateStr:SetWordWrap(false)

            row.partners = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.partners:SetPoint("LEFT", 136, 0)
            row.partners:SetWidth(160)
            row.partners:SetJustifyH("LEFT")
            row.partners:SetWordWrap(false)

            row.bracket = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.bracket:SetPoint("LEFT", 300, 0)
            row.bracket:SetWidth(50)
            row.bracket:SetJustifyH("CENTER")

            row.games = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.games:SetPoint("LEFT", 355, 0)
            row.games:SetWidth(40)
            row.games:SetJustifyH("CENTER")

            row.wl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.wl:SetPoint("LEFT", 400, 0)
            row.wl:SetWidth(50)
            row.wl:SetJustifyH("CENTER")

            row.winPct = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.winPct:SetPoint("LEFT", 455, 0)
            row.winPct:SetWidth(45)
            row.winPct:SetJustifyH("CENTER")

            row.rating = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.rating:SetPoint("LEFT", 505, 0)
            row.rating:SetWidth(120)
            row.rating:SetJustifyH("CENTER")
            row.rating:SetWordWrap(false)

            row.net = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.net:SetPoint("LEFT", 630, 0)
            row.net:SetWidth(50)
            row.net:SetJustifyH("CENTER")

            row.expandIndicator = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.expandIndicator:SetPoint("RIGHT", -4, 0)
            row.expandIndicator:SetWidth(16)
            row.expandIndicator:SetJustifyH("CENTER")

            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()

            -- Highlight on hover
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.05)
        end

        row:SetPoint("TOPLEFT", 0, -totalHeight)

        -- Alternating row color
        if displayNum % 2 == 0 then
            row.bg:SetColorTexture(1, 1, 1, 0.05)
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row.index:SetText("#" .. displayNum)
        row.index:SetTextColor(0.5, 0.5, 0.5)

        row.dateStr:SetText(date("%m/%d %H:%M", s.startTime))
        row.dateStr:SetTextColor(0.7, 0.7, 0.7)

        -- Partners: class-colored names joined by ", " or "Solo"
        if s.partners and #s.partners > 0 then
            local pParts = {}
            for _, p in ipairs(s.partners) do
                local color = CLASS_COLORS[p.class] or "ffffffff"
                table.insert(pParts, "|c" .. color .. p.name .. "|r")
            end
            row.partners:SetText(table.concat(pParts, ", "))
        else
            row.partners:SetText("|cff888888Solo|r")
        end

        row.bracket:SetText(s.bracket or "?")
        row.bracket:SetTextColor(0.9, 0.9, 0.9)

        row.games:SetText(#s.games)
        row.games:SetTextColor(0.9, 0.9, 0.9)

        row.wl:SetText("|cff00ff00" .. s.wins .. "|r-|cffff0000" .. s.losses .. "|r")

        -- Win% with color gradient: red at 0%, yellow at 50%, green at 100%
        local totalSGames = s.wins + s.losses
        local pct = (totalSGames > 0) and (s.wins / totalSGames * 100) or 0
        local pr, pg
        if pct <= 50 then
            pr = 1
            pg = pct / 50
        else
            pr = 1 - (pct - 50) / 50
            pg = 1
        end
        local pctHex = string.format("|cff%02x%02x00%d%%|r",
            math.floor(pr * 255 + 0.5), math.floor(pg * 255 + 0.5), math.floor(pct + 0.5))
        row.winPct:SetText(pctHex)

        -- Rating: startRating -> endRating
        if s.ratingStart and s.ratingEnd then
            row.rating:SetText("|cffcccccc" .. s.ratingStart .. " → " .. s.ratingEnd .. "|r")
        else
            row.rating:SetText("|cff555555—|r")
        end

        -- Net rating change
        if s.ratingChange and s.ratingChange ~= 0 then
            local sign = s.ratingChange >= 0 and "+" or ""
            local netColor = s.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
            row.net:SetText(netColor .. sign .. s.ratingChange .. "|r")
        elseif s.ratingStart or s.ratingEnd then
            row.net:SetText("|cff888888" .. "0" .. "|r")
        else
            row.net:SetText("|cff555555—|r")
        end

        -- Expand indicator
        local isExpanded = (expandedSession == s.startTime)
        row.expandIndicator:SetText(isExpanded and "▼" or "▶")
        row.expandIndicator:SetTextColor(0.5, 0.5, 0.5)

        -- OnClick: toggle drill-down (use startTime as stable identity)
        local capturedStartTime = s.startTime
        row:SetScript("OnClick", function()
            if expandedSession == capturedStartTime then
                expandedSession = nil
            else
                expandedSession = capturedStartTime
            end
            RefreshSessions()
        end)

        row:Show()
        totalHeight = totalHeight + SESSION_ROW_HEIGHT

        -- Drill-down: render column header + individual games if expanded
        if isExpanded then
            -- Column header row for drill-down
            matchRowIdx = matchRowIdx + 1
            local hrow = matchDrillPool[matchRowIdx]
            if not hrow then
                hrow = CreateFrame("Frame", nil, sessContent)
                hrow:SetSize(740, 16)
                matchDrillPool[matchRowIdx] = hrow
                hrow.bg = hrow:CreateTexture(nil, "BACKGROUND")
                hrow.bg:SetAllPoints()
            end
            hrow:SetPoint("TOPLEFT", 0, -totalHeight)
            hrow.bg:SetColorTexture(0.06, 0.06, 0.10, 0.9)
            -- Lazily create header labels
            if not hrow.isHeader then
                hrow.isHeader = true
                local drillHeaders = {
                    { text = "Result", x = 40,  w = 36 },
                    { text = "Enemy",  x = 80,  w = 260 },
                    { text = "Rating", x = 500, w = 50 },
                    { text = "Dur",    x = 560, w = 45 },
                    { text = "Time",   x = 620, w = 60 },
                }
                for _, dh in ipairs(drillHeaders) do
                    local fs = hrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    fs:SetPoint("LEFT", dh.x, 0)
                    fs:SetWidth(dh.w)
                    fs:SetJustifyH("LEFT")
                    fs:SetText("|cff666666" .. dh.text .. "|r")
                end
            end
            hrow:Show()
            totalHeight = totalHeight + 16

            for gi, game in ipairs(s.games) do
                matchRowIdx = matchRowIdx + 1
                local mrow = matchDrillPool[matchRowIdx]
                if not mrow then
                    mrow = CreateFrame("Frame", nil, sessContent)
                    mrow:SetSize(740, MATCH_ROW_HEIGHT)
                    matchDrillPool[matchRowIdx] = mrow

                    mrow.result = mrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mrow.result:SetPoint("LEFT", 40, 0)
                    mrow.result:SetWidth(36)
                    mrow.result:SetJustifyH("LEFT")

                    mrow.enemy = mrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mrow.enemy:SetPoint("LEFT", 80, 0)
                    mrow.enemy:SetWidth(260)
                    mrow.enemy:SetJustifyH("LEFT")
                    mrow.enemy:SetWordWrap(false)

                    mrow.ratingChg = mrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mrow.ratingChg:SetPoint("LEFT", 500, 0)
                    mrow.ratingChg:SetWidth(50)
                    mrow.ratingChg:SetJustifyH("CENTER")

                    mrow.duration = mrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mrow.duration:SetPoint("LEFT", 560, 0)
                    mrow.duration:SetWidth(45)
                    mrow.duration:SetJustifyH("CENTER")

                    mrow.timeStr = mrow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    mrow.timeStr:SetPoint("LEFT", 620, 0)
                    mrow.timeStr:SetWidth(60)
                    mrow.timeStr:SetJustifyH("RIGHT")

                    mrow.bg = mrow:CreateTexture(nil, "BACKGROUND")
                    mrow.bg:SetAllPoints()
                end

                mrow:SetPoint("TOPLEFT", 0, -totalHeight)
                mrow.bg:SetColorTexture(0.08, 0.08, 0.12, 0.8)

                -- Result
                if game.result == "WIN" then
                    mrow.result:SetText("|cff00ff00WIN|r")
                else
                    mrow.result:SetText("|cffff0000LOSS|r")
                end

                -- Enemy team — class-colored names with spec/class subtitle
                local enemyNames = {}
                local enemyDetails = {}
                if game.enemyTeam and #game.enemyTeam > 0 then
                    for _, p in ipairs(game.enemyTeam) do
                        local color = CLASS_COLORS[p.class] or "ffffffff"
                        table.insert(enemyNames, "|c" .. color .. p.name .. "|r")
                        local spec = p.spec and (SPEC_SHORT[p.spec] or p.spec) or nil
                        table.insert(enemyDetails, spec and (spec .. " " .. (p.class or "?")) or (p.class or "?"))
                    end
                elseif game.enemyComp then
                    for _, class in ipairs(game.enemyComp) do
                        table.insert(enemyNames, ColorClass(class))
                    end
                end
                local enemyStr = table.concat(enemyNames, ", ")
                if #enemyDetails > 0 then
                    enemyStr = enemyStr .. " |cff888888(" .. table.concat(enemyDetails, ", ") .. ")|r"
                end
                mrow.enemy:SetText(enemyStr ~= "" and enemyStr or "?")

                -- Rating change
                if game.ratingChange then
                    local sign = game.ratingChange >= 0 and "+" or ""
                    local chgColor = game.ratingChange >= 0 and "|cff00ff00" or "|cffff0000"
                    mrow.ratingChg:SetText(chgColor .. sign .. game.ratingChange .. "|r")
                else
                    mrow.ratingChg:SetText("|cff555555—|r")
                end

                -- Duration
                local dur = (game.startTime and game.endTime) and (game.endTime - game.startTime) or nil
                mrow.duration:SetText(FormatDuration(dur))
                mrow.duration:SetTextColor(0.8, 0.8, 0.8)

                -- Time
                mrow.timeStr:SetText(FormatTime(game.startTime))
                mrow.timeStr:SetTextColor(0.6, 0.6, 0.6)

                mrow:Show()
                totalHeight = totalHeight + MATCH_ROW_HEIGHT
            end
        end
    end

    sessContent:SetHeight(math.max(totalHeight, 1))

    -- Update title with session/game counts and net rating
    local sessionCount = #sessions
    local countStr = sessionCount .. " session" .. (sessionCount ~= 1 and "s" or "") ..
        ", " .. totalGames .. " game" .. (totalGames ~= 1 and "s" or "")
    local ratingStr = ""
    if hasRating then
        local sign = totalNetRating >= 0 and "+" or ""
        local color = totalNetRating >= 0 and "|cff00ff00" or "|cffff0000"
        ratingStr = " | Net: " .. color .. sign .. totalNetRating .. "|r"
    end
    historyFrame.title:SetText("Trinketed — " .. countStr .. " (" ..
        "|cff00ff00" .. totalWins .. "W|r / |cffff0000" .. totalLosses .. "L|r)" .. ratingStr)
end

local function ToggleHistory()
    if historyFrame:IsShown() then
        historyFrame:Hide()
    else
        if activeTab == "sessions" then
            RefreshSessions()
        else
            RefreshHistory()
        end
        historyFrame:Show()
    end
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
        print("  /trinketed history — toggle game history window")
        print("  /trinketed export — export game history")
        print("  /trinketed import — import game history")
        print("  /trinketed minimap — toggle minimap button")
        print("  /trinketed hdebug — toggle history debug logging")
        print("  /trinketed status — dump current state")
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Trinketed", 0, 0.8, 1)
    local count = TrinketedHistoryDB and #TrinketedHistoryDB.games or 0
    GameTooltip:AddLine(count .. " games recorded", 1, 1, 1)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cff00ff00Left-click|r to toggle history", 0.8, 0.8, 0.8)
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
    local data = { v = 1, t = time(), g = TrinketedHistoryDB.games }
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
    local f = CreateFrame("Frame", "TrinketedExportFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(520, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    f.title:SetText("Trinketed Export — " .. count .. " games (" .. #str .. " chars)")

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
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", 0, 14)
    hint:SetText("|cff999999Ctrl+A to select all, Ctrl+C to copy|r")

    f:SetScript("OnHide", function(self) self:SetParent(nil) end)
    exportFrame = f
end

ShowImportDialog = function()
    if importFrame then importFrame:Hide() end

    local f = CreateFrame("Frame", "TrinketedImportFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(520, 320)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOP", 0, -5)
    f.title:SetText("Trinketed Import — Paste string below")

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
    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(120, 26)
    btn:SetPoint("BOTTOM", 0, 14)
    btn:SetText("Import")
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
        if historyFrame and historyFrame:IsShown() then
            if activeTab == "sessions" then RefreshSessions() else RefreshHistory() end
        end
        f:Hide()
    end)

    -- Hint text
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", 0, 44)
    hint:SetText("|cff999999Ctrl+V to paste, then click Import|r")

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
        local _, eventType, _, sourceGUID, _, _, _, destGUID, _, _, _, spellID, spellName = CombatLogGetCurrentEventInfo()

        -- Try to discover unknown GUIDs from arena/party units
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
            if historyFrame:IsShown() then
                if activeTab == "sessions" then RefreshSessions() else RefreshHistory() end
            end
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
end

---------------------------------------------------------------------------
-- Register with Trinketed Options Panel
---------------------------------------------------------------------------
lib:RegisterSubAddon("History", {
    order = 2,
    OnSelect = function(contentFrame)
        local C = lib.C
        local info = contentFrame:CreateFontString(nil, "OVERLAY")
        info:SetFont(lib.FONT_BODY, 12, "")
        info:SetPoint("TOPLEFT", 20, -20)
        info:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
        info:SetText("Arena match history and VOD timestamp overlay.\n\nUse |cffE8B923/trinketed history|r to open the history window.")

        lib:CreateButton(contentFrame, 20, -70, 180, "Open History Window", function()
            ToggleHistory()
        end)
    end,
})

RegisterSubCommands()
