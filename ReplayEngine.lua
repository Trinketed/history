---------------------------------------------------------------------------
-- TrinketedHistory: ReplayEngine.lua
-- Playback engine: decompression, state management, event processing
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local LibDeflate = LibStub("LibDeflate")

local REPLAY_SPELLS = addon.REPLAY_SPELLS

---------------------------------------------------------------------------
-- Hex color string to r,g,b floats (for CLASS_COLORS "ffc79c6e" format)
---------------------------------------------------------------------------
local function HexToRGB(hex)
    -- Strip leading "ff" alpha if present
    if #hex == 8 then hex = hex:sub(3) end
    local r = tonumber(hex:sub(1, 2), 16) / 255
    local g = tonumber(hex:sub(3, 4), 16) / 255
    local b = tonumber(hex:sub(5, 6), 16) / 255
    return r, g, b
end

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
}

local CLASS_COLORS_RGB = {}
for class, hex in pairs(CLASS_COLORS) do
    local r, g, b = HexToRGB(hex)
    CLASS_COLORS_RGB[class] = { r = r, g = g, b = b }
end
addon.CLASS_COLORS_RGB = CLASS_COLORS_RGB

---------------------------------------------------------------------------
-- Power type colors
---------------------------------------------------------------------------
addon.POWER_COLORS = {
    [0] = { r = 0.0, g = 0.0, b = 1.0 },   -- mana
    [1] = { r = 1.0, g = 0.0, b = 0.0 },   -- rage
    [3] = { r = 1.0, g = 1.0, b = 0.0 },   -- energy
}

---------------------------------------------------------------------------
-- Damage suffixes that subtract from HP
---------------------------------------------------------------------------
local DAMAGE_EVENTS = {
    SWING_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    RANGE_DAMAGE = true,
    DAMAGE_SHIELD = true,
    ENVIRONMENTAL_DAMAGE = true,
}

---------------------------------------------------------------------------
-- Heal suffixes that add to HP
---------------------------------------------------------------------------
local HEAL_EVENTS = {
    SPELL_HEAL = true,
    SPELL_PERIODIC_HEAL = true,
}

---------------------------------------------------------------------------
-- Decompress a gameLog string into parsed data
-- Returns: { initialState, events, matchDuration } or nil, errorMsg
---------------------------------------------------------------------------
function addon:DecompressGameLog(gameLogStr)
    if not gameLogStr or gameLogStr == "" then
        return nil, "No game log data."
    end

    local decoded = LibDeflate:DecodeForPrint(gameLogStr)
    if not decoded then return nil, "Failed to decode game log." end

    local json = LibDeflate:DecompressZlib(decoded)
    if not json then return nil, "Failed to decompress game log." end

    -- JSONToTable is local in Core.lua, so we use the global reference set there
    local data = addon.JSONToTable(json)
    if not data then return nil, "Failed to parse game log JSON." end

    if data.v ~= 1 then
        return nil, "Unsupported game log version: " .. tostring(data.v)
    end

    local events = data.events
    if not events or #events == 0 then
        return nil, "No events in game log."
    end

    local initialState = data.initialState or { players = {}, timestamp = events[1][1] }
    local baseTs = initialState.timestamp

    -- Convert all event timestamps to match-relative seconds
    -- and restore nil sentinels ("\0") back to actual nil
    for _, ev in ipairs(events) do
        ev[1] = ev[1] - baseTs
        local n = #ev
        for i = n, 2, -1 do
            if ev[i] == "\0" then ev[i] = nil end
        end
    end
    initialState.timestamp = 0

    local matchDuration = events[#events][1]

    return {
        initialState = initialState,
        events = events,
        matchDuration = matchDuration,
    }
end

---------------------------------------------------------------------------
-- Build initial replay state from parsed data
---------------------------------------------------------------------------
local function BuildInitialState(parsedData)
    local state = { players = {} }
    for guid, info in pairs(parsedData.initialState.players) do
        state.players[guid] = {
            name = info.name,
            class = info.class,
            team = info.team,
            health = info.health or 0,
            healthMax = info.healthMax or 0,
            power = info.power or 0,
            powerMax = info.powerMax or 0,
            powerType = info.powerType or 0,
            auras = {},
            cooldowns = {},
            alive = true,
        }
    end
    return state
end

---------------------------------------------------------------------------
-- Deep-copy replay state (for reset during seek)
---------------------------------------------------------------------------
local function CopyState(src)
    local dst = { players = {} }
    for guid, p in pairs(src.players) do
        dst.players[guid] = {
            name = p.name,
            class = p.class,
            team = p.team,
            health = p.health,
            healthMax = p.healthMax,
            power = p.power,
            powerMax = p.powerMax,
            powerType = p.powerType,
            auras = {},
            cooldowns = {},
            alive = p.alive,
        }
    end
    return dst
end

---------------------------------------------------------------------------
-- Process a single CLEU event and update replay state
-- ev format: { relativeTs, subevent, hideCaster, srcGUID, srcName,
--              srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags,
--              dstRaidFlags, spellID/swingAmount, spellName/..., ... }
---------------------------------------------------------------------------
local function ProcessEvent(state, ev, currentTime)
    local subevent = ev[2]
    local srcGUID = ev[4]
    local srcName = ev[5]
    local dstGUID = ev[8]
    local dstName = ev[9]

    -- Ensure player entries exist for GUIDs we haven't seen
    -- Infer team from CLEU flags: 0x10 = friendly, 0x40 = hostile
    if srcGUID and not state.players[srcGUID] and srcName then
        local srcFlags = ev[6]
        local team = nil
        if srcFlags then
            if bit.band(srcFlags, 0x00000010) > 0 then
                team = "friendly"
            elseif bit.band(srcFlags, 0x00000040) > 0 then
                team = "enemy"
            end
        end
        state.players[srcGUID] = {
            name = srcName,
            class = nil,
            team = team,
            health = 0,
            healthMax = 0,
            power = 0,
            powerMax = 0,
            powerType = 0,
            auras = {},
            cooldowns = {},
            alive = true,
        }
    end
    if dstGUID and not state.players[dstGUID] and dstName then
        local dstFlags = ev[10]
        local team = nil
        if dstFlags then
            if bit.band(dstFlags, 0x00000010) > 0 then
                team = "friendly"
            elseif bit.band(dstFlags, 0x00000040) > 0 then
                team = "enemy"
            end
        end
        state.players[dstGUID] = {
            name = dstName,
            class = nil,
            team = team,
            health = 0,
            healthMax = 0,
            power = 0,
            powerMax = 0,
            powerType = 0,
            auras = {},
            cooldowns = {},
            alive = true,
        }
    end

    -- Damage events
    if DAMAGE_EVENTS[subevent] then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount
            if subevent == "SWING_DAMAGE" then
                amount = ev[12]  -- swing damage: amount is at position 12
            elseif subevent == "ENVIRONMENTAL_DAMAGE" then
                amount = ev[13]
            else
                amount = ev[15]  -- spell/range damage: spellID(12), spellName(13), spellSchool(14), amount(15)
            end
            if amount and type(amount) == "number" then
                player.health = math.max(0, player.health - amount)
            end
        end

    -- Heal events
    elseif HEAL_EVENTS[subevent] then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount = ev[15]       -- spellID(12), spellName(13), spellSchool(14), amount(15)
            local overhealing = ev[16]  -- overhealing(16)
            if amount and type(amount) == "number" then
                local effective = amount - (overhealing or 0)
                player.health = math.min(player.healthMax, player.health + effective)
            end
        end

    -- Power events
    elseif subevent == "SPELL_ENERGIZE" or subevent == "SPELL_PERIODIC_ENERGIZE" then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount = ev[15]
            if amount and type(amount) == "number" then
                player.power = math.min(player.powerMax, player.power + amount)
            end
        end

    elseif subevent == "SPELL_DRAIN" or subevent == "SPELL_LEECH" then
        local player = dstGUID and state.players[dstGUID]
        if player then
            local amount = ev[15]
            if amount and type(amount) == "number" then
                player.power = math.max(0, player.power - amount)
            end
        end
        -- SPELL_LEECH also energizes the source
        if subevent == "SPELL_LEECH" then
            local source = srcGUID and state.players[srcGUID]
            if source then
                local extraAmount = ev[17]
                if extraAmount and type(extraAmount) == "number" then
                    source.power = math.min(source.powerMax, source.power + extraAmount)
                end
            end
        end

    -- Death
    elseif subevent == "UNIT_DIED" then
        local player = dstGUID and state.players[dstGUID]
        if player then
            player.health = 0
            player.alive = false
        end

    -- Aura applied
    elseif subevent == "SPELL_AURA_APPLIED" then
        local spellName = ev[13]
        local spellID = ev[12]
        local auraType = ev[15]  -- "BUFF" or "DEBUFF"
        if spellName and REPLAY_SPELLS[spellName] then
            local player = dstGUID and state.players[dstGUID]
            if player then
                local spellInfo = REPLAY_SPELLS[spellName]
                player.auras[spellName] = {
                    spellID = spellID,
                    applied = currentTime,
                    duration = spellInfo.dur,
                    isDebuff = (auraType == "DEBUFF"),
                    cat = spellInfo.cat,
                }
            end
        end

    -- Aura removed
    elseif subevent == "SPELL_AURA_REMOVED" then
        local spellName = ev[13]
        if spellName and REPLAY_SPELLS[spellName] then
            local player = dstGUID and state.players[dstGUID]
            if player then
                player.auras[spellName] = nil
            end
        end

    -- Cooldown tracking via cast success
    elseif subevent == "SPELL_CAST_SUCCESS" then
        local spellName = ev[13]
        local spellID = ev[12]
        if spellName and REPLAY_SPELLS[spellName] then
            local spellInfo = REPLAY_SPELLS[spellName]
            local cat = spellInfo.cat
            if cat == "trinket" or cat == "offensive" or cat == "defensive" then
                local player = srcGUID and state.players[srcGUID]
                if player then
                    player.cooldowns[spellName] = {
                        spellID = spellID,
                        cast = currentTime,
                        duration = spellInfo.dur,
                    }
                end
            end
        end
    end
end
addon.ProcessEvent = ProcessEvent

---------------------------------------------------------------------------
-- Build event list for the event feed — includes ALL captured events
-- Returns array of { time, subevent, spellName, spellID, srcName, dstName,
--                     srcClass, dstClass, cat, amount, duration }
---------------------------------------------------------------------------
local function BuildFeedEvents(parsedData, state)
    local feed = {}
    local initialPlayers = parsedData.initialState.players

    -- Build GUID->class lookup from initial state
    local guidToClass = {}
    for guid, info in pairs(initialPlayers) do
        guidToClass[guid] = info.class
    end

    for _, ev in ipairs(parsedData.events) do
        local subevent = ev[2]
        local srcGUID = ev[4]
        local srcName = ev[5]
        local dstGUID = ev[8]
        local dstName = ev[9]

        local spellName, spellID, cat, amount, duration

        if subevent == "UNIT_DIED" then
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = "death",
                srcName = nil,
                dstName = dstName,
                srcClass = nil,
                dstClass = dstGUID and guidToClass[dstGUID],
            })
        elseif DAMAGE_EVENTS[subevent] then
            if subevent == "SWING_DAMAGE" then
                spellName = "Melee"
                amount = ev[12]
            elseif subevent == "ENVIRONMENTAL_DAMAGE" then
                spellName = "Environment"
                amount = ev[13]
            else
                spellID = ev[12]
                spellName = ev[13]
                amount = ev[15]
            end
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = "damage",
                spellName = spellName,
                spellID = spellID,
                srcName = srcName,
                dstName = dstName,
                srcClass = srcGUID and guidToClass[srcGUID],
                dstClass = dstGUID and guidToClass[dstGUID],
                amount = amount,
            })
        elseif HEAL_EVENTS[subevent] then
            spellID = ev[12]
            spellName = ev[13]
            amount = ev[15]
            local overhealing = ev[16] or 0
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = "healing",
                spellName = spellName or "Heal",
                spellID = spellID,
                srcName = srcName,
                dstName = dstName,
                srcClass = srcGUID and guidToClass[srcGUID],
                dstClass = dstGUID and guidToClass[dstGUID],
                amount = amount - overhealing,
            })
        elseif subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REMOVED" then
            spellName = ev[13]
            spellID = ev[12]
            local replayInfo = spellName and REPLAY_SPELLS[spellName]
            cat = replayInfo and replayInfo.cat or "aura"
            duration = replayInfo and replayInfo.dur
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = cat,
                spellName = spellName,
                spellID = spellID,
                srcName = srcName,
                dstName = dstName,
                srcClass = srcGUID and guidToClass[srcGUID],
                dstClass = dstGUID and guidToClass[dstGUID],
                duration = duration,
            })
        elseif subevent == "SPELL_CAST_SUCCESS" then
            spellName = ev[13]
            spellID = ev[12]
            local replayInfo = spellName and REPLAY_SPELLS[spellName]
            if replayInfo then
                cat = replayInfo.cat
            else
                cat = "cast"
            end
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = cat,
                spellName = spellName,
                spellID = spellID,
                srcName = srcName,
                dstName = dstName,
                srcClass = srcGUID and guidToClass[srcGUID],
                dstClass = dstGUID and guidToClass[dstGUID],
            })
        elseif subevent == "SPELL_ENERGIZE" or subevent == "SPELL_PERIODIC_ENERGIZE"
            or subevent == "SPELL_DRAIN" or subevent == "SPELL_LEECH" then
            spellID = ev[12]
            spellName = ev[13]
            amount = ev[15]
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = "power",
                spellName = spellName,
                spellID = spellID,
                srcName = srcName,
                dstName = dstName,
                srcClass = srcGUID and guidToClass[srcGUID],
                dstClass = dstGUID and guidToClass[dstGUID],
                amount = amount,
            })
        elseif subevent == "SPELL_AURA_APPLIED_DOSE" or subevent == "SPELL_AURA_REMOVED_DOSE"
            or subevent == "SPELL_MISSED" or subevent == "SPELL_INTERRUPT"
            or subevent == "SPELL_DISPEL" or subevent == "SPELL_STOLEN"
            or subevent == "SPELL_EXTRA_ATTACKS" or subevent == "SPELL_SUMMON"
            or subevent == "SPELL_RESURRECT" or subevent == "SPELL_INSTAKILL"
            or subevent == "SPELL_ABSORBED" or subevent == "PARTY_KILL"
            or subevent == "SPELL_CAST_START" or subevent == "SPELL_CAST_FAILED" then
            spellID = ev[12]
            spellName = ev[13]
            table.insert(feed, {
                time = ev[1],
                subevent = subevent,
                cat = "other",
                spellName = spellName or subevent,
                spellID = spellID,
                srcName = srcName,
                dstName = dstName,
                srcClass = srcGUID and guidToClass[srcGUID],
                dstClass = dstGUID and guidToClass[dstGUID],
            })
        end
    end
    return feed
end

---------------------------------------------------------------------------
-- Build timeline markers for the scrubber
-- Returns array of { time, cat, label }
---------------------------------------------------------------------------
local function BuildTimelineMarkers(parsedData)
    local markers = {}
    for _, ev in ipairs(parsedData.events) do
        local subevent = ev[2]
        if subevent == "UNIT_DIED" then
            table.insert(markers, { time = ev[1], cat = "death", label = ev[9] })
        elseif subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_AURA_APPLIED" then
            local spellName = ev[13]
            if spellName and REPLAY_SPELLS[spellName] then
                local info = REPLAY_SPELLS[spellName]
                if info.cat == "trinket" or info.cat == "offensive" or info.cat == "defensive" then
                    table.insert(markers, { time = ev[1], cat = info.cat, label = spellName })
                end
            end
        end
    end
    return markers
end

---------------------------------------------------------------------------
-- Replay session object
-- Created when user opens replay, destroyed on close
---------------------------------------------------------------------------
function addon:CreateReplaySession(gameLogStr)
    local parsed, err = self:DecompressGameLog(gameLogStr)
    if not parsed then
        return nil, err
    end

    local initialState = BuildInitialState(parsed)
    local feedEvents = BuildFeedEvents(parsed, initialState)
    local markers = BuildTimelineMarkers(parsed)

    local session = {
        parsed = parsed,
        initialState = initialState,
        state = CopyState(initialState),
        feedEvents = feedEvents,
        markers = markers,

        -- Playback state
        status = "stopped",   -- "stopped", "playing", "paused"
        currentTime = 0,
        cursorIndex = 1,
        speed = 1,
        matchDuration = parsed.matchDuration,
        seeking = false,      -- true during seek (disables lerp)
    }

    -- Seek to a specific time
    function session:SeekTo(targetTime)
        self.seeking = true
        self.state = CopyState(self.initialState)
        self.cursorIndex = 1
        local events = self.parsed.events
        while self.cursorIndex <= #events and events[self.cursorIndex][1] <= targetTime do
            ProcessEvent(self.state, events[self.cursorIndex], events[self.cursorIndex][1])
            self.cursorIndex = self.cursorIndex + 1
        end
        self.currentTime = targetTime
    end

    -- Advance playback by dt seconds (called from OnUpdate)
    function session:Advance(dt)
        if self.status ~= "playing" then return end
        self.seeking = false
        self.currentTime = math.min(self.currentTime + dt * self.speed, self.matchDuration)
        local events = self.parsed.events
        while self.cursorIndex <= #events and events[self.cursorIndex][1] <= self.currentTime do
            ProcessEvent(self.state, events[self.cursorIndex], events[self.cursorIndex][1])
            self.cursorIndex = self.cursorIndex + 1
        end
        -- Auto-pause at end
        if self.currentTime >= self.matchDuration then
            self.status = "paused"
        end
    end

    function session:Play()
        if self.currentTime >= self.matchDuration then
            self:SeekTo(0)
        end
        self.status = "playing"
        self.seeking = false
    end

    function session:Pause()
        self.status = "paused"
    end

    function session:TogglePlayPause()
        if self.status == "playing" then
            self:Pause()
        else
            self:Play()
        end
    end

    function session:SetSpeed(speed)
        self.speed = speed
    end

    function session:Destroy()
        self.parsed = nil
        self.state = nil
        self.initialState = nil
        self.feedEvents = nil
        self.markers = nil
    end

    return session
end
