---------------------------------------------------------------------------
-- TrinketedHistory: ReplayUI.lua
-- Replay viewer window: unit frames, event feed, timeline, transport
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C
local REPLAY_SPELLS = addon.REPLAY_SPELLS

local replayFrame = nil
local session = nil

-- Layout constants
local FRAME_W, FRAME_H = 950, 560
local UNIT_PANEL_W = 600
local FEED_PANEL_W = 330
local TRANSPORT_H = 40
local UNIT_FRAME_W = 270
local UNIT_FRAME_H = 55
local HP_BAR_H = 12
local POWER_BAR_H = 6
local ICON_SIZE = 16
local ICON_GAP = 2
local FEED_ROW_H = 18

local SPEEDS = { 0.5, 1, 2, 4 }
local speedIndex = 2  -- default 1x

---------------------------------------------------------------------------
-- Helper: format seconds as m:ss
---------------------------------------------------------------------------
local function FormatTime(secs)
    if not secs or secs < 0 then secs = 0 end
    local m = math.floor(secs / 60)
    local s = math.floor(secs % 60)
    return string.format("%d:%02d", m, s)
end

---------------------------------------------------------------------------
-- Helper: format seconds as m:ss.t (with tenths)
---------------------------------------------------------------------------
local function FormatTimeTenths(secs)
    if not secs or secs < 0 then secs = 0 end
    local m = math.floor(secs / 60)
    local s = secs % 60
    return string.format("%d:%04.1f", m, s)
end

---------------------------------------------------------------------------
-- Helper: abbreviate number (1234 -> "1.2k")
---------------------------------------------------------------------------
local function AbbrevNumber(n)
    if not n or type(n) ~= "number" then return "" end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(math.floor(n))
end

---------------------------------------------------------------------------
-- Helper: get class color escape string
---------------------------------------------------------------------------
local function ClassColorStr(class)
    local rgb = addon.CLASS_COLORS_RGB and addon.CLASS_COLORS_RGB[class]
    if rgb then
        return string.format("|cff%02x%02x%02x", rgb.r * 255, rgb.g * 255, rgb.b * 255)
    end
    return "|cffffffff"
end

---------------------------------------------------------------------------
-- Category colors for feed and markers
---------------------------------------------------------------------------
local CAT_COLORS = {
    cc        = { r = 0.3, g = 0.6, b = 1.0 },
    damage    = { r = 1.0, g = 0.3, b = 0.3 },
    healing   = { r = 0.3, g = 1.0, b = 0.3 },
    death     = { r = 1.0, g = 0.1, b = 0.1 },
    defensive = { r = 0.91, g = 0.73, b = 0.14 },
    offensive = { r = 1.0, g = 0.5, b = 0.1 },
    trinket   = { r = 0.91, g = 0.73, b = 0.14 },
    aura      = { r = 0.6, g = 0.4, b = 0.8 },
    cast      = { r = 0.7, g = 0.7, b = 0.7 },
    power     = { r = 0.3, g = 0.5, b = 0.8 },
    other     = { r = 0.5, g = 0.5, b = 0.5 },
}

---------------------------------------------------------------------------
-- Create a single unit frame
---------------------------------------------------------------------------
local function CreateUnitFrame(parent, yOffset)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(UNIT_FRAME_W, UNIT_FRAME_H)
    f:SetPoint("TOPLEFT", 10, yOffset)
    f:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    f:SetBackdropColor(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], C.bgRaised[4] or 1)
    f:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], C.borderSubtle[4] or 1)

    -- Name label
    f.nameText = f:CreateFontString(nil, "OVERLAY")
    f.nameText:SetFont(lib.FONT_BODY, 10, "")
    f.nameText:SetPoint("TOPLEFT", 4, -3)
    f.nameText:SetWidth(UNIT_FRAME_W - 60)
    f.nameText:SetJustifyH("LEFT")

    -- HP text (current/max)
    f.hpText = f:CreateFontString(nil, "OVERLAY")
    f.hpText:SetFont(lib.FONT_MONO, 9, "")
    f.hpText:SetPoint("TOPRIGHT", -4, -3)
    f.hpText:SetJustifyH("RIGHT")
    f.hpText:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    -- HP bar background
    f.hpBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.hpBarBg:SetPoint("TOPLEFT", 3, -15)
    f.hpBarBg:SetSize(UNIT_FRAME_W - 6, HP_BAR_H)
    f.hpBarBg:SetColorTexture(0, 0, 0, 0.5)

    -- HP bar fill
    f.hpBar = f:CreateTexture(nil, "ARTWORK")
    f.hpBar:SetPoint("TOPLEFT", f.hpBarBg, "TOPLEFT")
    f.hpBar:SetHeight(HP_BAR_H)
    f.hpBar:SetColorTexture(0.5, 0.5, 0.5, 1)

    -- Power bar background
    f.powerBarBg = f:CreateTexture(nil, "BACKGROUND", nil, 1)
    f.powerBarBg:SetPoint("TOPLEFT", f.hpBarBg, "BOTTOMLEFT", 0, -1)
    f.powerBarBg:SetSize(UNIT_FRAME_W - 6, POWER_BAR_H)
    f.powerBarBg:SetColorTexture(0, 0, 0, 0.5)

    -- Power bar fill
    f.powerBar = f:CreateTexture(nil, "ARTWORK")
    f.powerBar:SetPoint("TOPLEFT", f.powerBarBg, "TOPLEFT")
    f.powerBar:SetHeight(POWER_BAR_H)
    f.powerBar:SetColorTexture(0, 0, 1, 1)

    -- Icon row container (for auras/cooldowns)
    f.iconRow = CreateFrame("Frame", nil, f)
    f.iconRow:SetPoint("TOPLEFT", f.powerBarBg, "BOTTOMLEFT", 0, -2)
    f.iconRow:SetSize(UNIT_FRAME_W - 6, ICON_SIZE)

    f.icons = {}   -- pool of icon frames

    -- State tracking for lerp
    f.targetHealth = 0
    f.displayHealth = 0
    f.guid = nil

    return f
end

---------------------------------------------------------------------------
-- Update a unit frame from replay state
---------------------------------------------------------------------------
local function UpdateUnitFrame(uf, playerState, currentTime, seeking)
    if not playerState then
        uf:Hide()
        return
    end
    uf:Show()

    -- Name + spec + class color
    local name = playerState.name or "?"
    if playerState.spec then
        name = name .. " (" .. playerState.spec .. ")"
    end
    local classColor = addon.CLASS_COLORS_RGB[playerState.class]
    if classColor then
        uf.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    else
        uf.nameText:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    end
    uf.nameText:SetText(name)

    -- HP
    local hp = playerState.health
    local hpMax = playerState.healthMax
    uf.targetHealth = hp

    if seeking then
        uf.displayHealth = hp
    end
    -- Lerp display health toward target
    local displayHP = uf.displayHealth
    if math.abs(displayHP - hp) > 1 then
        uf.displayHealth = displayHP + (hp - displayHP) * 0.15
    else
        uf.displayHealth = hp
    end

    local barWidth = UNIT_FRAME_W - 6
    local hpFrac = hpMax > 0 and (uf.displayHealth / hpMax) or 0
    uf.hpBar:SetWidth(math.max(1, barWidth * hpFrac))

    -- HP bar color by class
    if classColor then
        uf.hpBar:SetColorTexture(classColor.r, classColor.g, classColor.b, 1)
    end

    -- HP text
    if hpMax > 0 then
        uf.hpText:SetText(math.floor(uf.displayHealth) .. "/" .. hpMax)
    else
        uf.hpText:SetText("?")
    end

    -- Power
    local power = playerState.power
    local powerMax = playerState.powerMax
    local powerType = playerState.powerType
    if powerMax > 0 then
        uf.powerBarBg:Show()
        uf.powerBar:Show()
        local powerFrac = power / powerMax
        uf.powerBar:SetWidth(math.max(1, barWidth * powerFrac))
        local pc = addon.POWER_COLORS[powerType]
        if pc then
            uf.powerBar:SetColorTexture(pc.r, pc.g, pc.b, 1)
        end
    else
        uf.powerBarBg:Hide()
        uf.powerBar:Hide()
    end

    -- Icons: auras + cooldowns
    local iconIdx = 0

    -- Active auras
    for spellName, aura in pairs(playerState.auras) do
        iconIdx = iconIdx + 1
        local icon = uf.icons[iconIdx]
        if not icon then
            icon = CreateFrame("Frame", nil, uf.iconRow)
            icon:SetSize(ICON_SIZE, ICON_SIZE)
            icon.tex = icon:CreateTexture(nil, "ARTWORK")
            icon.tex:SetAllPoints()
            icon.border = icon:CreateTexture(nil, "BACKGROUND")
            icon.border:SetPoint("TOPLEFT", -1, 1)
            icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
            icon.border:SetColorTexture(1, 0, 0, 1)
            icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
            icon.cooldown:SetAllPoints()
            icon.cooldown:SetDrawEdge(false)
            uf.icons[iconIdx] = icon
        end
        icon:SetPoint("TOPLEFT", (iconIdx - 1) * (ICON_SIZE + ICON_GAP), 0)
        -- Icon texture
        local texID = aura.spellID and GetSpellTexture(aura.spellID)
        if texID then
            icon.tex:SetTexture(texID)
            icon.tex:SetDesaturated(false)
        else
            icon.tex:SetColorTexture(0.3, 0.3, 0.3, 1)
        end
        -- Border color: red for debuff, green for buff
        if aura.isDebuff then
            icon.border:SetColorTexture(1, 0, 0, 0.8)
        else
            icon.border:SetColorTexture(0, 1, 0, 0.8)
        end
        -- Duration sweep
        if aura.duration and aura.applied then
            icon.cooldown:SetCooldown(GetTime() - (currentTime - aura.applied), aura.duration)
            icon.cooldown:Show()
        else
            icon.cooldown:Hide()
        end
        icon:Show()
    end

    -- Active cooldowns
    for spellName, cd in pairs(playerState.cooldowns) do
        if cd.cast then
            local cdDur = cd.duration or 3  -- show instant CDs (trinket etc.) for 3s
            local elapsed = currentTime - cd.cast
            if elapsed < cdDur then
                iconIdx = iconIdx + 1
                local icon = uf.icons[iconIdx]
                if not icon then
                    icon = CreateFrame("Frame", nil, uf.iconRow)
                    icon:SetSize(ICON_SIZE, ICON_SIZE)
                    icon.tex = icon:CreateTexture(nil, "ARTWORK")
                    icon.tex:SetAllPoints()
                    icon.border = icon:CreateTexture(nil, "BACKGROUND")
                    icon.border:SetPoint("TOPLEFT", -1, 1)
                    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
                    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
                    icon.cooldown:SetAllPoints()
                    icon.cooldown:SetDrawEdge(false)
                    uf.icons[iconIdx] = icon
                end
                icon:SetPoint("TOPLEFT", (iconIdx - 1) * (ICON_SIZE + ICON_GAP), 0)
                local texID = cd.spellID and GetSpellTexture(cd.spellID)
                if texID then
                    icon.tex:SetTexture(texID)
                    icon.tex:SetDesaturated(true)
                else
                    icon.tex:SetColorTexture(0.2, 0.2, 0.2, 1)
                end
                icon.border:SetColorTexture(C.textDim[1], C.textDim[2], C.textDim[3], 0.8)
                icon.cooldown:SetCooldown(GetTime() - elapsed, cdDur)
                icon.cooldown:Show()
                icon:Show()
            end
        end
    end

    -- Hide unused icons
    for i = iconIdx + 1, #uf.icons do
        uf.icons[i]:Hide()
    end
end

---------------------------------------------------------------------------
-- Create the main replay window
---------------------------------------------------------------------------
local function CreateReplayFrame()
    if replayFrame then return replayFrame end

    local frame = lib:CreateWindowFrame("TrinketedReplayFrame", {
        width = FRAME_W,
        height = FRAME_H,
        title = "Replay",
        onClose = function()
            if session then
                session:Destroy()
                session = nil
            end
        end,
    })

    -- ===== UNIT FRAMES PANEL (left side) =====
    frame.unitPanel = CreateFrame("Frame", nil, frame)
    frame.unitPanel:SetPoint("TOPLEFT", 6, -30)
    frame.unitPanel:SetSize(UNIT_PANEL_W, FRAME_H - TRANSPORT_H - 36)

    -- Section label: Friendly
    frame.friendlyLabel = frame.unitPanel:CreateFontString(nil, "OVERLAY")
    frame.friendlyLabel:SetFont(lib.FONT_DISPLAY, 10, "")
    frame.friendlyLabel:SetPoint("TOPLEFT", 10, -4)
    frame.friendlyLabel:SetTextColor(C.partyBlue[1], C.partyBlue[2], C.partyBlue[3])
    frame.friendlyLabel:SetText("FRIENDLY TEAM")

    -- Friendly unit frames (up to 5)
    frame.friendlyFrames = {}
    for i = 1, 5 do
        frame.friendlyFrames[i] = CreateUnitFrame(frame.unitPanel, -20 - (i - 1) * (UNIT_FRAME_H + 4))
        frame.friendlyFrames[i]:Hide()
    end

    -- Divider (position set dynamically by RefreshUnitFrames)
    local divider = frame.unitPanel:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetColorTexture(C.divider[1], C.divider[2], C.divider[3], C.divider[4] or 0.25)
    frame.teamDivider = divider

    -- Section label: Enemy
    frame.enemyLabel = frame.unitPanel:CreateFontString(nil, "OVERLAY")
    frame.enemyLabel:SetFont(lib.FONT_DISPLAY, 10, "")
    frame.enemyLabel:SetTextColor(C.enemyRed[1], C.enemyRed[2], C.enemyRed[3])
    frame.enemyLabel:SetText("ENEMY TEAM")

    -- Enemy unit frames (up to 5)
    frame.enemyFrames = {}
    for i = 1, 5 do
        frame.enemyFrames[i] = CreateUnitFrame(frame.unitPanel, 0) -- positioned dynamically
        frame.enemyFrames[i]:Hide()
    end

    -- ===== EVENT FEED PANEL (right side) =====
    frame.feedPanel = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.feedPanel:SetPoint("TOPLEFT", UNIT_PANEL_W + 6, -30)
    frame.feedPanel:SetPoint("BOTTOMRIGHT", -6, TRANSPORT_H + 6)
    frame.feedPanel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame.feedPanel:SetBackdropColor(C.sidebarBg[1], C.sidebarBg[2], C.sidebarBg[3], C.sidebarBg[4] or 1)
    frame.feedPanel:SetBackdropBorderColor(C.borderDefault[1], C.borderDefault[2], C.borderDefault[3], C.borderDefault[4] or 1)

    -- Filter chips using lib:CreateCheckbox() toggle chips with custom group logic
    frame.filterChips = {}
    local filterNames = { "All", "CC", "Dmg", "Heal", "CDs", "Deaths", "Other" }
    local filterCats = { "all", "cc", "damage", "healing", "cd", "death", "other" }
    frame.activeFilters = { all = true }

    local chipX = 6
    for idx, label in ipairs(filterNames) do
        local cat = filterCats[idx]
        local isOn = (cat == "all")  -- All starts active

        local function onToggle(newState)
            if cat == "all" then
                frame.activeFilters = { all = true }
            else
                frame.activeFilters.all = nil
                if newState then
                    frame.activeFilters[cat] = true
                else
                    frame.activeFilters[cat] = nil
                    -- If no filters active, re-enable All
                    local anyActive = false
                    for _, c in ipairs(filterCats) do
                        if c ~= "all" and frame.activeFilters[c] then anyActive = true; break end
                    end
                    if not anyActive then
                        frame.activeFilters = { all = true }
                    end
                end
            end
            -- Sync all chip visuals to match activeFilters state
            for _, chip in ipairs(frame.filterChips) do
                local shouldBeOn = frame.activeFilters[chip.cat] or frame.activeFilters.all
                chip.checkbox:SetChecked(shouldBeOn)
            end
            if frame.RefreshFeed then frame:RefreshFeed() end
        end

        -- lib:CreateCheckbox returns the checkbox frame; position in feedPanel
        local checkbox = lib:CreateCheckbox(frame.feedPanel, chipX, -6, label, isOn, onToggle)
        frame.filterChips[idx] = { checkbox = checkbox, cat = cat }
        chipX = chipX + (checkbox:GetWidth() or 40) + 4
    end

    -- Search box
    frame.searchBox = CreateFrame("EditBox", nil, frame.feedPanel, "BackdropTemplate")
    frame.searchBox:SetPoint("TOPLEFT", 6, -28)
    frame.searchBox:SetPoint("RIGHT", -6, 0)
    frame.searchBox:SetHeight(18)
    frame.searchBox:SetFont(lib.FONT_MONO, 9, "")
    frame.searchBox:SetTextColor(C.textBright[1], C.textBright[2], C.textBright[3])
    frame.searchBox:SetAutoFocus(false)
    frame.searchBox:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame.searchBox:SetBackdropColor(0, 0, 0, 0.4)
    frame.searchBox:SetBackdropBorderColor(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)
    frame.searchBox:SetTextInsets(4, 4, 0, 0)

    frame.searchBox.placeholder = frame.searchBox:CreateFontString(nil, "ARTWORK")
    frame.searchBox.placeholder:SetFont(lib.FONT_MONO, 9, "")
    frame.searchBox.placeholder:SetPoint("LEFT", 4, 0)
    frame.searchBox.placeholder:SetText("Search...")
    frame.searchBox.placeholder:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])

    frame.searchQuery = ""
    frame.searchBox:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        frame.searchQuery = text and text:lower() or ""
        frame.searchBox.placeholder:SetShown(frame.searchQuery == "")
        if frame.RefreshFeed then frame:RefreshFeed() end
    end)
    frame.searchBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    -- Feed scroll frame
    frame.feedScroll = CreateFrame("ScrollFrame", nil, frame.feedPanel, "UIPanelScrollFrameTemplate")
    frame.feedScroll:SetPoint("TOPLEFT", 4, -48)
    frame.feedScroll:SetPoint("BOTTOMRIGHT", -24, 4)

    frame.feedContent = CreateFrame("Frame", nil, frame.feedScroll)
    frame.feedContent:SetWidth(FEED_PANEL_W - 30)
    frame.feedContent:SetHeight(1)
    frame.feedScroll:SetScrollChild(frame.feedContent)

    frame.feedRows = {}  -- row pool

    -- ===== TRANSPORT BAR (bottom) =====
    frame.transport = CreateFrame("Frame", nil, frame)
    frame.transport:SetPoint("BOTTOMLEFT", 6, 6)
    frame.transport:SetPoint("BOTTOMRIGHT", -6, 6)
    frame.transport:SetHeight(TRANSPORT_H)

    -- Jump to start
    local btnStart = CreateFrame("Button", nil, frame.transport)
    btnStart:SetSize(24, 20)
    btnStart:SetPoint("LEFT", 4, 0)
    btnStart.text = btnStart:CreateFontString(nil, "OVERLAY")
    btnStart.text:SetFont(lib.FONT_MONO, 10, "")
    btnStart.text:SetPoint("CENTER")
    btnStart.text:SetText("|<")
    btnStart.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    btnStart:SetScript("OnClick", function()
        if session then session:SeekTo(0); session.status = "paused" end
    end)

    -- Play/pause
    frame.btnPlay = CreateFrame("Button", nil, frame.transport)
    frame.btnPlay:SetSize(24, 20)
    frame.btnPlay:SetPoint("LEFT", btnStart, "RIGHT", 2, 0)
    frame.btnPlay.text = frame.btnPlay:CreateFontString(nil, "OVERLAY")
    frame.btnPlay.text:SetFont(lib.FONT_MONO, 12, "")
    frame.btnPlay.text:SetPoint("CENTER")
    frame.btnPlay.text:SetText(">")
    frame.btnPlay.text:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
    frame.btnPlay:SetScript("OnClick", function()
        if session then session:TogglePlayPause() end
    end)

    -- Jump to end
    local btnEnd = CreateFrame("Button", nil, frame.transport)
    btnEnd:SetSize(24, 20)
    btnEnd:SetPoint("LEFT", frame.btnPlay, "RIGHT", 2, 0)
    btnEnd.text = btnEnd:CreateFontString(nil, "OVERLAY")
    btnEnd.text:SetFont(lib.FONT_MONO, 10, "")
    btnEnd.text:SetPoint("CENTER")
    btnEnd.text:SetText(">|")
    btnEnd.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    btnEnd:SetScript("OnClick", function()
        if session then
            session:SeekTo(session.matchDuration)
            session.status = "paused"
        end
    end)

    -- Speed button
    frame.btnSpeed = CreateFrame("Button", nil, frame.transport)
    frame.btnSpeed:SetSize(34, 20)
    frame.btnSpeed:SetPoint("LEFT", btnEnd, "RIGHT", 8, 0)
    frame.btnSpeed.text = frame.btnSpeed:CreateFontString(nil, "OVERLAY")
    frame.btnSpeed.text:SetFont(lib.FONT_MONO, 10, "")
    frame.btnSpeed.text:SetPoint("CENTER")
    frame.btnSpeed.text:SetText("1x")
    frame.btnSpeed.text:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])
    frame.btnSpeed:SetScript("OnClick", function()
        speedIndex = (speedIndex % #SPEEDS) + 1
        local speed = SPEEDS[speedIndex]
        if session then session:SetSpeed(speed) end
        frame.btnSpeed.text:SetText(speed .. "x")
    end)

    -- Timeline scrubber track
    frame.scrubTrack = CreateFrame("Button", nil, frame.transport)
    frame.scrubTrack:SetPoint("LEFT", frame.btnSpeed, "RIGHT", 10, 0)
    frame.scrubTrack:SetPoint("RIGHT", frame.transport, "RIGHT", -70, 0)
    frame.scrubTrack:SetHeight(6)

    frame.scrubTrackBg = frame.scrubTrack:CreateTexture(nil, "BACKGROUND")
    frame.scrubTrackBg:SetAllPoints()
    frame.scrubTrackBg:SetColorTexture(C.borderSubtle[1], C.borderSubtle[2], C.borderSubtle[3], 1)

    -- Scrub thumb
    frame.scrubThumb = CreateFrame("Frame", nil, frame.scrubTrack)
    frame.scrubThumb:SetSize(10, 14)
    frame.scrubThumbTex = frame.scrubThumb:CreateTexture(nil, "OVERLAY")
    frame.scrubThumbTex:SetAllPoints()
    frame.scrubThumbTex:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)

    -- Click-to-seek on scrub track
    frame.scrubTrack:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and session then
            local x = self:GetLeft()
            local w = self:GetWidth()
            local cursorX = GetCursorPosition() / self:GetEffectiveScale()
            local frac = math.max(0, math.min(1, (cursorX - x) / w))
            session:SeekTo(frac * session.matchDuration)
            session.status = "paused"
            frame.scrubbing = true
        end
    end)

    frame.scrubTrack:SetScript("OnMouseUp", function()
        frame.scrubbing = false
    end)

    -- Time display
    frame.timeText = frame.transport:CreateFontString(nil, "OVERLAY")
    frame.timeText:SetFont(lib.FONT_MONO, 10, "")
    frame.timeText:SetPoint("RIGHT", -4, 0)
    frame.timeText:SetJustifyH("RIGHT")
    frame.timeText:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    -- ===== ERROR MESSAGE (shown when decompression fails) =====
    frame.errorText = frame:CreateFontString(nil, "OVERLAY")
    frame.errorText:SetFont(lib.FONT_BODY, 12, "")
    frame.errorText:SetPoint("CENTER")
    frame.errorText:SetTextColor(C.statusError[1], C.statusError[2], C.statusError[3])
    frame.errorText:Hide()

    -- ===== TIMELINE MARKERS =====
    frame.markerPool = {}

    -- ===== OnUpdate: advance playback and refresh UI =====
    frame:SetScript("OnUpdate", function(self, dt)
        if not session then return end

        -- Handle scrub dragging
        if frame.scrubbing then
            local x = frame.scrubTrack:GetLeft()
            local w = frame.scrubTrack:GetWidth()
            local cursorX = GetCursorPosition() / frame.scrubTrack:GetEffectiveScale()
            local frac = math.max(0, math.min(1, (cursorX - x) / w))
            session:SeekTo(frac * session.matchDuration)
        end

        -- Advance playback
        session:Advance(dt)

        -- Update play/pause button text
        if session.status == "playing" then
            frame.btnPlay.text:SetText("||")
        else
            frame.btnPlay.text:SetText(">")
        end

        -- Update scrub thumb position
        if session.matchDuration > 0 then
            local frac = session.currentTime / session.matchDuration
            local trackW = frame.scrubTrack:GetWidth()
            frame.scrubThumb:SetPoint("CENTER", frame.scrubTrack, "LEFT", trackW * frac, 0)
        end

        -- Update time display
        frame.timeText:SetText(FormatTime(session.currentTime) .. " / " .. FormatTime(session.matchDuration))

        -- Update unit frames
        frame:RefreshUnitFrames()

        -- Update feed highlight
        frame:RefreshFeedHighlight()
    end)

    -- ===== Refresh unit frame positions and state =====
    function frame:RefreshUnitFrames()
        if not session then return end
        local state = session.state

        -- Sort players into friendly/enemy lists
        local friendly, enemy = {}, {}
        for guid, p in pairs(state.players) do
            if p.team == "friendly" then
                table.insert(friendly, { guid = guid, state = p })
            elseif p.team == "enemy" then
                table.insert(enemy, { guid = guid, state = p })
            end
        end

        -- Position friendly frames
        local friendlyCount = math.min(#friendly, 5)
        for i = 1, 5 do
            if i <= friendlyCount then
                self.friendlyFrames[i]:SetPoint("TOPLEFT", 10, -20 - (i - 1) * (UNIT_FRAME_H + 4))
                UpdateUnitFrame(self.friendlyFrames[i], friendly[i].state,
                    session.currentTime, session.seeking)
            else
                self.friendlyFrames[i]:Hide()
            end
        end

        -- Position divider and enemy label below friendly frames
        local divY = -20 - friendlyCount * (UNIT_FRAME_H + 4) - 4
        self.teamDivider:ClearAllPoints()
        self.teamDivider:SetPoint("TOPLEFT", self.unitPanel, "TOPLEFT", 10, divY)
        self.teamDivider:SetPoint("RIGHT", self.unitPanel, "RIGHT", -10, 0)

        self.enemyLabel:ClearAllPoints()
        self.enemyLabel:SetPoint("TOPLEFT", self.unitPanel, "TOPLEFT", 10, divY - 8)

        local enemyStartY = divY - 24
        local enemyCount = math.min(#enemy, 5)
        for i = 1, 5 do
            if i <= enemyCount then
                self.enemyFrames[i]:SetPoint("TOPLEFT", 10, enemyStartY - (i - 1) * (UNIT_FRAME_H + 4))
                UpdateUnitFrame(self.enemyFrames[i], enemy[i].state,
                    session.currentTime, session.seeking)
            else
                self.enemyFrames[i]:Hide()
            end
        end
    end

    -- ===== Refresh event feed =====
    function frame:RefreshFeed()
        if not session then return end

        -- Hide all rows
        for _, row in ipairs(self.feedRows) do
            row:Hide()
        end

        local feedEvents = session.feedEvents
        local filters = self.activeFilters

        -- Filter events
        local visible = {}
        for _, ev in ipairs(feedEvents) do
            local show = false
            if filters.all then
                show = true
            else
                local cat = ev.cat
                if cat == "cc" and filters.cc then show = true
                elseif cat == "damage" and filters.damage then show = true
                elseif cat == "healing" and filters.healing then show = true
                elseif (cat == "trinket" or cat == "offensive" or cat == "defensive") and filters.cd then show = true
                elseif cat == "death" and filters.death then show = true
                elseif (cat == "aura" or cat == "cast" or cat == "power" or cat == "other") and filters.other then show = true
                end
            end
            -- Apply search filter
            if show and self.searchQuery and self.searchQuery ~= "" then
                local q = self.searchQuery
                local match = false
                if ev.spellName and tostring(ev.spellName):lower():find(q, 1, true) then match = true end
                if not match and ev.srcName and tostring(ev.srcName):lower():find(q, 1, true) then match = true end
                if not match and ev.dstName and tostring(ev.dstName):lower():find(q, 1, true) then match = true end
                if not match and ev.subevent and tostring(ev.subevent):lower():find(q, 1, true) then match = true end
                if not match then show = false end
            end
            if show then
                table.insert(visible, ev)
            end
        end

        self.visibleFeedEvents = visible

        -- Create/update rows
        local contentHeight = 0
        for idx, ev in ipairs(visible) do
            local row = self.feedRows[idx]
            if not row then
                row = CreateFrame("Button", nil, self.feedContent)
                row:SetSize(FEED_PANEL_W - 30, FEED_ROW_H)

                row.bg = row:CreateTexture(nil, "BACKGROUND")
                row.bg:SetAllPoints()
                row.bg:SetColorTexture(0, 0, 0, 0)

                row.text = row:CreateFontString(nil, "OVERLAY")
                row.text:SetFont(lib.FONT_MONO, 9, "")
                row.text:SetPoint("LEFT", 2, 0)
                row.text:SetPoint("RIGHT", -2, 0)
                row.text:SetJustifyH("LEFT")

                self.feedRows[idx] = row
            end

            row:SetPoint("TOPLEFT", 0, -((idx - 1) * FEED_ROW_H))
            row.eventTime = ev.time

            -- Format the row text
            local timeStr = FormatTimeTenths(ev.time)
            local catColor = CAT_COLORS[ev.cat] or { r = 1, g = 1, b = 1 }
            local catHex = string.format("%02x%02x%02x",
                catColor.r * 255, catColor.g * 255, catColor.b * 255)

            local parts = { "|cff" .. catHex .. timeStr .. "|r" }

            if ev.cat == "death" then
                table.insert(parts, " |cffff0000" .. (ev.dstName or "?") .. " died|r")
            else
                local spellStr = ev.spellName or "?"
                -- Annotate aura removed / dispels / interrupts
                if ev.subevent == "SPELL_AURA_REMOVED" then
                    spellStr = spellStr .. " faded"
                elseif ev.subevent == "SPELL_INTERRUPT" then
                    spellStr = spellStr .. " interrupted"
                elseif ev.subevent == "SPELL_DISPEL" then
                    spellStr = spellStr .. " dispelled"
                elseif ev.subevent == "SPELL_STOLEN" then
                    spellStr = spellStr .. " stolen"
                elseif ev.subevent == "SPELL_MISSED" then
                    spellStr = spellStr .. " missed"
                elseif ev.subevent == "SPELL_CAST_START" then
                    spellStr = spellStr .. " casting"
                end
                if ev.srcClass then
                    spellStr = ClassColorStr(ev.srcClass) .. spellStr .. "|r"
                end
                table.insert(parts, "  " .. spellStr)

                if ev.srcName and ev.dstName then
                    local src = ClassColorStr(ev.srcClass) .. ev.srcName .. "|r"
                    local dst = ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
                    table.insert(parts, "  " .. src .. " > " .. dst)
                elseif ev.srcName then
                    table.insert(parts, "  " .. ClassColorStr(ev.srcClass) .. ev.srcName .. "|r")
                end

                if ev.amount and ev.amount ~= 0 then
                    table.insert(parts, "  " .. AbbrevNumber(math.abs(ev.amount)))
                end
                if ev.duration then
                    table.insert(parts, "  " .. ev.duration .. "s")
                end
            end

            row.text:SetText(table.concat(parts))

            -- Click to seek
            row:SetScript("OnClick", function()
                if session then
                    session:SeekTo(ev.time)
                    session.status = "paused"
                end
            end)

            row:Show()
            contentHeight = contentHeight + FEED_ROW_H
        end

        self.feedContent:SetHeight(math.max(contentHeight, 1))
    end

    -- ===== Refresh feed highlight and auto-scroll (called from OnUpdate) =====
    function frame:RefreshFeedHighlight()
        if not session or not self.visibleFeedEvents then return end
        local ct = session.currentTime
        local lastPastIdx = nil
        for idx, row in ipairs(self.feedRows) do
            if row:IsShown() and row.eventTime then
                row.bg:SetColorTexture(0, 0, 0, 0)
                if row.eventTime <= ct then
                    row.text:SetAlpha(1.0)
                    lastPastIdx = idx
                else
                    row.text:SetAlpha(0.3)
                end
            end
        end
        -- Accent highlight on most recent past event
        if lastPastIdx and self.feedRows[lastPastIdx] then
            self.feedRows[lastPastIdx].bg:SetColorTexture(
                C.accent[1], C.accent[2], C.accent[3], 0.1)
        end
        -- Auto-scroll to keep current time visible during playback
        if session.status == "playing" and lastPastIdx then
            local scrollMax = self.feedScroll:GetVerticalScrollRange()
            local targetScroll = math.max(0, (lastPastIdx - 5) * FEED_ROW_H)
            self.feedScroll:SetVerticalScroll(math.min(targetScroll, scrollMax))
        end
    end

    -- ===== Place timeline markers on the scrub track =====
    function frame:RefreshMarkers()
        -- Hide existing
        for _, m in ipairs(self.markerPool) do
            m:Hide()
        end

        if not session then return end

        for i, marker in ipairs(session.markers) do
            local m = self.markerPool[i]
            if not m then
                m = self.scrubTrack:CreateTexture(nil, "OVERLAY")
                m:SetSize(2, 10)
                self.markerPool[i] = m
            end
            local frac = session.matchDuration > 0 and (marker.time / session.matchDuration) or 0
            local trackW = self.scrubTrack:GetWidth()
            m:ClearAllPoints()
            m:SetPoint("CENTER", self.scrubTrack, "LEFT", trackW * frac, 0)

            local cc = CAT_COLORS[marker.cat] or { r = 1, g = 1, b = 1 }
            m:SetColorTexture(cc.r, cc.g, cc.b, 0.8)
            m:Show()
        end
    end

    replayFrame = frame
    return frame
end

---------------------------------------------------------------------------
-- Public API: open replay for a game record
---------------------------------------------------------------------------
function addon:OpenReplay(game)
    local frame = CreateReplayFrame()

    -- Clean up previous session
    if session then
        session:Destroy()
        session = nil
    end

    -- Reset speed
    speedIndex = 2
    frame.btnSpeed.text:SetText("1x")

    -- Hide error text
    frame.errorText:Hide()
    frame.unitPanel:Show()
    frame.feedPanel:Show()
    frame.transport:Show()

    -- Try to load
    if not game.gameLog then
        frame.errorText:SetText("No game log recorded for this match.")
        frame.errorText:Show()
        frame.unitPanel:Hide()
        frame.feedPanel:Hide()
        frame.transport:Hide()
        frame:Show()
        return
    end

    local newSession, err = self:CreateReplaySession(game.gameLog)
    if not newSession then
        frame.errorText:SetText(err or "Failed to load replay data.")
        frame.errorText:Show()
        frame.unitPanel:Hide()
        frame.feedPanel:Hide()
        frame.transport:Hide()
        frame:Show()
        return
    end

    session = newSession

    -- Build title
    local enemyComp = game.enemyComp and table.concat(game.enemyComp, "/") or "?"
    local result = game.result or "?"
    local map = game.map or "Arena"
    frame.titleText:SetText("Replay: " .. result .. " vs " .. enemyComp .. " - " .. map)

    -- Reset filter chips
    frame.activeFilters = { all = true }
    for _, chip in ipairs(frame.filterChips) do
        chip.checkbox:SetChecked(true)
    end

    -- Reset search box
    frame.searchQuery = ""
    frame.searchBox:SetText("")
    frame.searchBox.placeholder:Show()

    -- Build feed and markers
    frame:RefreshFeed()
    frame:RefreshMarkers()

    frame:Show()
end
