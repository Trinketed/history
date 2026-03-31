---------------------------------------------------------------------------
-- TrinketedHistory: ReplayUI.lua
-- Replay viewer window: unit frames, event feed, timeline, transport
---------------------------------------------------------------------------
TrinketedHistory = TrinketedHistory or {}
local addon = TrinketedHistory

local lib = LibStub("TrinketedLib-1.0")
local C = lib.C
local replayFrame = nil
local session = nil

-- Layout constants
local FRAME_W, FRAME_H = 1100, 560
local UNIT_PANEL_W = 580
local FEED_PANEL_W = 500
local TRANSPORT_H = 52
local UNIT_FRAME_W = 200
local UNIT_FRAME_H = 34
local HP_BAR_H = 10
local POWER_BAR_H = 5
local ICON_SIZE = 16
local ICON_GAP = 1
local CD_ICON_SIZE = 20
local CD_ICON_GAP = 1
local FEED_ROW_H = 20
local FEED_ICON_SIZE = 14

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
    damage       = { r = 1.0, g = 0.3, b = 0.3 },
    healing      = { r = 0.3, g = 1.0, b = 0.3 },
    death        = { r = 1.0, g = 0.1, b = 0.1 },
    offensive_cd = { r = 1.0, g = 0.5, b = 0.1 },
    defensive_cd = { r = 0.91, g = 0.73, b = 0.14 },
    interrupt    = { r = 1.0, g = 0.3, b = 0.2 },
    trinket      = { r = 1.0, g = 0.2, b = 0.8 },
    racial       = { r = 0.91, g = 0.73, b = 0.14 },
    cc_break     = { r = 0.91, g = 0.73, b = 0.14 },
    healing_cd   = { r = 0.3, g = 1.0, b = 0.3 },
    mobility     = { r = 0.3, g = 0.6, b = 1.0 },
    dispel       = { r = 0.66, g = 0.33, b = 0.97 },
    utility      = { r = 0.5, g = 0.5, b = 0.5 },
    aura         = { r = 0.6, g = 0.4, b = 0.8 },
    cast         = { r = 0.7, g = 0.7, b = 0.7 },
    miss         = { r = 0.5, g = 0.5, b = 0.5 },
    power        = { r = 0.3, g = 0.5, b = 0.8 },
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

    f.icons = {}   -- pool of CD icon frames (positioned externally)

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

    -- Cooldown tracker: show all class CDs to the right of the unit frame
    local hiddenCDs = TrinketedHistoryDB and TrinketedHistoryDB.settings and TrinketedHistoryDB.settings.hiddenReplayCDs or {}
    local classCDs = playerState.class and addon.CLASS_COOLDOWNS and addon.CLASS_COOLDOWNS[playerState.class]
    local visIdx = 0
    if classCDs then
        for idx, spellID in ipairs(classCDs) do
            -- Skip hidden spells
            if hiddenCDs[spellID] then
                -- ensure pooled icon is hidden
                if uf.icons[idx] then uf.icons[idx]:Hide() end
            else
                visIdx = visIdx + 1
                local icon = uf.icons[idx]
                if not icon then
                    icon = CreateFrame("Frame", nil, uf:GetParent())
                    icon:SetSize(CD_ICON_SIZE, CD_ICON_SIZE)
                    icon.bgTex = icon:CreateTexture(nil, "BACKGROUND")
                    icon.bgTex:SetPoint("TOPLEFT", -1, 1)
                    icon.bgTex:SetPoint("BOTTOMRIGHT", 1, -1)
                    icon.bgTex:SetColorTexture(0.04, 0.04, 0.05, 1)
                    icon.bdrT = icon:CreateTexture(nil, "BORDER")
                    icon.bdrT:SetPoint("TOPLEFT", -1, 1); icon.bdrT:SetPoint("TOPRIGHT", 1, 1); icon.bdrT:SetHeight(1)
                    icon.bdrB = icon:CreateTexture(nil, "BORDER")
                    icon.bdrB:SetPoint("BOTTOMLEFT", -1, -1); icon.bdrB:SetPoint("BOTTOMRIGHT", 1, -1); icon.bdrB:SetHeight(1)
                    icon.bdrL = icon:CreateTexture(nil, "BORDER")
                    icon.bdrL:SetPoint("TOPLEFT", -1, 1); icon.bdrL:SetPoint("BOTTOMLEFT", -1, -1); icon.bdrL:SetWidth(1)
                    icon.bdrR = icon:CreateTexture(nil, "BORDER")
                    icon.bdrR:SetPoint("TOPRIGHT", 1, 1); icon.bdrR:SetPoint("BOTTOMRIGHT", 1, -1); icon.bdrR:SetWidth(1)
                    icon.tex = icon:CreateTexture(nil, "ARTWORK")
                    icon.tex:SetAllPoints()
                    icon.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
                    icon.cooldown:SetAllPoints()
                    icon.cooldown:SetDrawEdge(true)
                    icon.cooldown:SetDrawBling(false)
                    icon.cooldown:SetSwipeColor(0, 0, 0, 0.5)
                    icon.cooldown:SetHideCountdownNumbers(false)
                    icon.tipBtn = CreateFrame("Button", nil, icon)
                    icon.tipBtn:SetAllPoints()
                    icon.tipBtn:SetFrameLevel(icon.cooldown:GetFrameLevel() + 1)
                    icon.tipBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    uf.icons[idx] = icon
                end

                -- Position using visible index
                local col = (visIdx - 1) % 11
                local row = math.floor((visIdx - 1) / 11)
                icon:ClearAllPoints()
                icon:SetPoint("TOPLEFT", uf, "TOPRIGHT", 4 + col * (CD_ICON_SIZE + CD_ICON_GAP), -(row * (CD_ICON_SIZE + CD_ICON_GAP)))

                -- Spell texture — faction-specific for PvP Trinket, fallback via name
                if spellID == 42292 then
                    local faction = UnitFactionGroup(playerState.team == "friendly" and "player" or "arena1")
                    if faction == "Alliance" then
                        icon.tex:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_01")
                    else
                        icon.tex:SetTexture("Interface\\Icons\\INV_Jewelry_TrinketPVP_02")
                    end
                else
                    local texID = GetSpellTexture(spellID)
                    if not texID then
                        -- Fallback: try via spell name from SPELL_DB
                        local dbEntry = SPELL_DB and SPELL_DB[spellID]
                        if dbEntry and dbEntry.name then
                            texID = GetSpellTexture(dbEntry.name)
                        end
                    end
                    if texID then
                        icon.tex:SetTexture(texID)
                    else
                        icon.tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    end
                end

                -- Tooltip on hover + right-click to hide
                local thisSpellID = spellID
                local dbEntry = SPELL_DB and SPELL_DB[spellID]
                local spellName = dbEntry and dbEntry.name or ""
                icon.tipBtn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetSpellByID(thisSpellID)
                    GameTooltip:AddLine("|cff888888Right-click to hide|r")
                    GameTooltip:Show()
                end)
                icon.tipBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                icon.tipBtn:SetScript("OnClick", function(self, button)
                    if button == "RightButton" then
                        if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                            TrinketedHistoryDB.settings.hiddenReplayCDs[thisSpellID] = true
                        end
                        print("|cff00ccff" .. "Trinketed" .. ":|r Hidden " .. (spellName ~= "" and spellName or ("spell " .. thisSpellID)) .. " from replay CD tracker. Use the gear menu to re-enable.")
                    end
                end)

                -- Category border color
                local cat = dbEntry and dbEntry.cat or ""
                local br, bg, bb
                if cat == "trinket" or cat == "racial" or cat == "cc_break" then
                    br, bg, bb = 0.91, 0.73, 0.14
                elseif cat == "offensive_cd" then
                    br, bg, bb = 1.0, 0.2, 0.2
                elseif cat == "defensive_cd" then
                    br, bg, bb = 0.2, 0.8, 0.2
                elseif cat == "interrupt" then
                    br, bg, bb = 1.0, 0.5, 0.0
                elseif cat == "healing_cd" then
                    br, bg, bb = 0.2, 0.8, 0.2
                else
                    br, bg, bb = 0.3, 0.3, 0.3
                end

                -- Check if on cooldown
                local cd = playerState.cooldowns and playerState.cooldowns[spellID]
                if cd then
                    local elapsed = currentTime - cd.castTime
                    if elapsed < cd.cd then
                        icon.tex:SetDesaturated(true)
                        icon.cooldown:SetCooldown(GetTime() - elapsed, cd.cd)
                        icon.cooldown:Show()
                        icon.bdrT:SetColorTexture(br, bg, bb, 0.3)
                        icon.bdrB:SetColorTexture(br, bg, bb, 0.3)
                        icon.bdrL:SetColorTexture(br, bg, bb, 0.3)
                        icon.bdrR:SetColorTexture(br, bg, bb, 0.3)
                    else
                        icon.tex:SetDesaturated(false)
                        icon.cooldown:Hide()
                        icon.bdrT:SetColorTexture(br, bg, bb, 1)
                        icon.bdrB:SetColorTexture(br, bg, bb, 1)
                        icon.bdrL:SetColorTexture(br, bg, bb, 1)
                        icon.bdrR:SetColorTexture(br, bg, bb, 1)
                    end
                else
                    icon.tex:SetDesaturated(false)
                    icon.cooldown:Hide()
                    icon.bdrT:SetColorTexture(br, bg, bb, 1)
                    icon.bdrB:SetColorTexture(br, bg, bb, 1)
                    icon.bdrL:SetColorTexture(br, bg, bb, 1)
                    icon.bdrR:SetColorTexture(br, bg, bb, 1)
                end

                icon:Show()
            end
        end
        -- Hide excess pool entries
        for i = #classCDs + 1, #uf.icons do
            if uf.icons[i] then uf.icons[i]:Hide() end
        end
    else
        for i = 1, #uf.icons do
            if uf.icons[i] then uf.icons[i]:Hide() end
        end
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
        title = "|cffE8B923T|r|cffF4F4F5RINKETED|r Replay",
        onClose = function()
            if session then
                session:Destroy()
                session = nil
            end
        end,
    })
    frame:SetScript("OnDragStart", nil)
    frame:SetScript("OnDragStop", nil)
    frame:RegisterForDrag()

    -- ===== GEAR MENU (tracked spells config) =====
    local gearBtn = CreateFrame("Button", nil, frame)
    gearBtn:SetSize(20, 20)
    gearBtn:SetPoint("TOPRIGHT", -28, -6)
    gearBtn.icon = gearBtn:CreateFontString(nil, "OVERLAY")
    gearBtn.icon:SetFont(lib.FONT_MONO, 14, "")
    gearBtn.icon:SetPoint("CENTER")
    gearBtn.icon:SetText("*")
    gearBtn.icon:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
    gearBtn:SetScript("OnEnter", function(self)
        self.icon:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Tracked Spells")
        GameTooltip:AddLine("Configure which cooldowns to show", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function(self)
        self.icon:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        GameTooltip:Hide()
    end)

    -- Dropdown menu for tracked spells
    local menuFrame = CreateFrame("Frame", "TrinketedReplayCDMenu", UIParent, "UIDropDownMenuTemplate")

    local CLASS_ORDER = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest",
        "Mage", "Warlock", "Shaman", "Druid" }

    local function InitCDMenu(self, level, menuList)
        local info = UIDropDownMenu_CreateInfo()
        local hiddenCDs = TrinketedHistoryDB and TrinketedHistoryDB.settings and TrinketedHistoryDB.settings.hiddenReplayCDs or {}

        if level == 1 then
            -- Show All / Reset option
            info.text = "|cff00ff00Show All (Reset)|r"
            info.notCheckable = true
            info.func = function()
                if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                    wipe(TrinketedHistoryDB.settings.hiddenReplayCDs)
                end
                print("|cff00ccffTrinketed:|r All replay CD tracker spells restored.")
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)

            -- Separator
            info = UIDropDownMenu_CreateInfo()
            info.text = ""
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)

            -- Class submenus
            for _, className in ipairs(CLASS_ORDER) do
                local spells = addon.CLASS_COOLDOWNS[className]
                if spells then
                    info = UIDropDownMenu_CreateInfo()
                    info.text = className
                    info.notCheckable = true
                    info.hasArrow = true
                    info.menuList = className
                    UIDropDownMenu_AddButton(info, level)
                end
            end

        elseif level == 2 then
            -- Spells for the selected class
            local className = menuList
            local spells = addon.CLASS_COOLDOWNS[className]
            if spells then
                for _, spellID in ipairs(spells) do
                    info = UIDropDownMenu_CreateInfo()
                    local dbEntry = SPELL_DB and SPELL_DB[spellID]
                    local spellName = dbEntry and dbEntry.name or (GetSpellInfo(spellID) or ("Spell " .. spellID))
                    local texID = GetSpellTexture(spellID)
                    if texID then
                        info.text = "|T" .. texID .. ":14:14:0:0:64:64:4:60:4:60|t " .. spellName
                    else
                        info.text = spellName
                    end
                    info.checked = not hiddenCDs[spellID]
                    info.isNotRadio = true
                    info.keepShownOnClick = true
                    local sid = spellID
                    info.func = function(self, _, _, checked)
                        if TrinketedHistoryDB and TrinketedHistoryDB.settings then
                            if checked then
                                TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = nil
                            else
                                TrinketedHistoryDB.settings.hiddenReplayCDs[sid] = true
                            end
                        end
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end
    end

    gearBtn:SetScript("OnClick", function(self)
        UIDropDownMenu_Initialize(menuFrame, InitCDMenu, "MENU")
        ToggleDropDownMenu(1, nil, menuFrame, self, 0, 0)
    end)

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
        frame.friendlyFrames[i] = CreateUnitFrame(frame.unitPanel, -20 - (i - 1) * (UNIT_FRAME_H + 12))
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
    local filterNames = { "All", "Dmg", "Heal", "CD", "CC", "Die" }
    local filterCats = { "all", "damage", "healing", "cd", "cc", "death" }
    frame.activeFilters = { all = true }

    local CHIP_W = 42
    local CHIP_H = 18
    local chipX = 4
    for idx, label in ipairs(filterNames) do
        local cat = filterCats[idx]
        local isOn = (cat == "all")

        local btn = CreateFrame("Button", nil, frame.feedPanel)
        btn:SetSize(CHIP_W, CHIP_H)
        btn:SetPoint("TOPLEFT", chipX, -4)

        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()

        btn.label = btn:CreateFontString(nil, "OVERLAY")
        btn.label:SetFont(lib.FONT_BODY, 9, "")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(label)

        btn.cat = cat
        btn.isOn = isOn

        local function UpdateChipVisual(b)
            if b.isOn then
                b.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
                b.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            else
                b.bg:SetColorTexture(C.bgRaised[1], C.bgRaised[2], C.bgRaised[3], 1)
                b.label:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
            end
        end
        UpdateChipVisual(btn)

        btn:SetScript("OnClick", function()
            if cat == "all" then
                frame.activeFilters = { all = true }
            else
                frame.activeFilters.all = nil
                if not frame.activeFilters[cat] then
                    frame.activeFilters[cat] = true
                else
                    frame.activeFilters[cat] = nil
                    local anyActive = false
                    for _, c in ipairs(filterCats) do
                        if c ~= "all" and frame.activeFilters[c] then anyActive = true; break end
                    end
                    if not anyActive then
                        frame.activeFilters = { all = true }
                    end
                end
            end
            for _, chip in ipairs(frame.filterChips) do
                chip.isOn = frame.activeFilters[chip.cat] or frame.activeFilters.all
                UpdateChipVisual(chip)
            end
            if frame.RefreshFeed then frame:RefreshFeed() end
        end)

        btn:SetScript("OnEnter", function(self)
            if self.isOn then
                self.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.25)
            else
                self.bg:SetColorTexture(C.bgElevated[1], C.bgElevated[2], C.bgElevated[3], 1)
            end
        end)
        btn:SetScript("OnLeave", function(self) UpdateChipVisual(self) end)

        frame.filterChips[idx] = btn
        chipX = chipX + CHIP_W + 2
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
    btnStart:SetPoint("LEFT", 4, 6)
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
    frame.scrubTrack:SetPoint("RIGHT", frame.transport, "RIGHT", -100, 0)
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
    frame.timeText:SetPoint("RIGHT", -4, 6)
    frame.timeText:SetJustifyH("RIGHT")
    frame.timeText:SetTextColor(C.textNormal[1], C.textNormal[2], C.textNormal[3])

    -- ===== TIMELINE LEGEND =====
    local legendItems = {
        { color = CAT_COLORS.death,        label = "Death" },
        { color = CAT_COLORS.trinket,      label = "Trinket" },
        { color = CAT_COLORS.offensive_cd, label = "Offensive" },
        { color = CAT_COLORS.defensive_cd, label = "Defensive" },
        { color = CAT_COLORS.interrupt,    label = "Interrupt" },
    }
    local legendX = 4
    for _, item in ipairs(legendItems) do
        local swatch = frame.transport:CreateTexture(nil, "ARTWORK")
        swatch:SetSize(8, 8)
        swatch:SetPoint("BOTTOMLEFT", legendX, 4)
        swatch:SetColorTexture(item.color.r, item.color.g, item.color.b, 1)
        local lbl = frame.transport:CreateFontString(nil, "OVERLAY")
        lbl:SetFont(lib.FONT_BODY, 8, "")
        lbl:SetPoint("LEFT", swatch, "RIGHT", 3, 0)
        lbl:SetText(item.label)
        lbl:SetTextColor(C.textDim[1], C.textDim[2], C.textDim[3])
        legendX = legendX + 8 + 3 + lbl:GetStringWidth() + 10
    end

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
                self.friendlyFrames[i]:SetPoint("TOPLEFT", 10, -20 - (i - 1) * (UNIT_FRAME_H + 12))
                UpdateUnitFrame(self.friendlyFrames[i], friendly[i].state,
                    session.currentTime, session.seeking)
            else
                self.friendlyFrames[i]:Hide()
            end
        end

        -- Position divider and enemy label below friendly frames
        local divY = -20 - friendlyCount * (UNIT_FRAME_H + 12) - 4
        self.teamDivider:ClearAllPoints()
        self.teamDivider:SetPoint("TOPLEFT", self.unitPanel, "TOPLEFT", 10, divY)
        self.teamDivider:SetPoint("RIGHT", self.unitPanel, "RIGHT", -10, 0)

        self.enemyLabel:ClearAllPoints()
        self.enemyLabel:SetPoint("TOPLEFT", self.unitPanel, "TOPLEFT", 10, divY - 8)

        local enemyStartY = divY - 24
        local enemyCount = math.min(#enemy, 5)
        for i = 1, 5 do
            if i <= enemyCount then
                self.enemyFrames[i]:SetPoint("TOPLEFT", 10, enemyStartY - (i - 1) * (UNIT_FRAME_H + 12))
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
                if cat == "death" and filters.death then show = true
                elseif cat == "damage" and filters.damage then show = true
                elseif (cat == "healing" or cat == "healing_cd") and filters.healing then show = true
                elseif (cat == "offensive_cd" or cat == "defensive_cd" or cat == "trinket"
                    or cat == "racial" or cat == "cc_break" or cat == "mobility" or cat == "utility") and filters.cd then show = true
                elseif (cat == "interrupt" or cat == "dispel" or cat == "aura") and filters.cc then show = true
                elseif (cat == "cast" or cat == "miss" or cat == "power") and filters.damage then show = true
                end
            end
            -- Apply search filter
            if show and self.searchQuery and self.searchQuery ~= "" then
                local q = self.searchQuery
                local match = false
                if ev.spellName and tostring(ev.spellName):lower():find(q, 1, true) then match = true end
                if not match and ev.srcName and tostring(ev.srcName):lower():find(q, 1, true) then match = true end
                if not match and ev.dstName and tostring(ev.dstName):lower():find(q, 1, true) then match = true end
                if not match and ev.type and tostring(ev.type):lower():find(q, 1, true) then match = true end
                if not match and ev.extraSpell and tostring(ev.extraSpell):lower():find(q, 1, true) then match = true end
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

                -- Time label
                row.timeText = row:CreateFontString(nil, "OVERLAY")
                row.timeText:SetFont(lib.FONT_MONO, 9, "")
                row.timeText:SetPoint("LEFT", 2, 0)
                row.timeText:SetWidth(38)
                row.timeText:SetJustifyH("LEFT")

                -- Source name
                row.srcText = row:CreateFontString(nil, "OVERLAY")
                row.srcText:SetFont(lib.FONT_MONO, 9, "")
                row.srcText:SetPoint("LEFT", 42, 0)
                row.srcText:SetWidth(80)
                row.srcText:SetJustifyH("RIGHT")
                row.srcText:SetWordWrap(false)

                -- Spell icon button (separate frame for isolated tooltip)
                row.iconBtn = CreateFrame("Button", nil, row)
                row.iconBtn:SetSize(FEED_ICON_SIZE, FEED_ICON_SIZE)
                row.iconBtn:SetPoint("LEFT", 126, 0)
                row.icon = row.iconBtn:CreateTexture(nil, "ARTWORK")
                row.icon:SetAllPoints()

                -- Spell name
                row.spellText = row:CreateFontString(nil, "OVERLAY")
                row.spellText:SetFont(lib.FONT_MONO, 9, "")
                row.spellText:SetPoint("LEFT", 144, 0)
                row.spellText:SetWidth(120)
                row.spellText:SetJustifyH("LEFT")
                row.spellText:SetWordWrap(false)

                -- Arrow + target + amount
                row.detailText = row:CreateFontString(nil, "OVERLAY")
                row.detailText:SetFont(lib.FONT_MONO, 9, "")
                row.detailText:SetPoint("LEFT", 268, 0)
                row.detailText:SetPoint("RIGHT", -2, 0)
                row.detailText:SetJustifyH("LEFT")
                row.detailText:SetWordWrap(false)

                self.feedRows[idx] = row
            end

            row:SetPoint("TOPLEFT", 0, -((idx - 1) * FEED_ROW_H))
            row.eventTime = ev.time

            -- Time
            row.timeText:SetText(FormatTimeTenths(ev.time))
            row.timeText:SetTextColor(0.53, 0.53, 0.53)

            -- Spell icon + tooltip only on icon hover
            local spellID = ev.spellID
            local texID = spellID and GetSpellTexture(spellID)
            if texID then
                row.icon:SetTexture(texID)
                row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                row.iconBtn:Show()
                row.iconBtn:SetScript("OnEnter", function(self)
                    if spellID then
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetSpellByID(spellID)
                        GameTooltip:Show()
                    end
                end)
                row.iconBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
                -- Icon click also seeks
                row.iconBtn:SetScript("OnClick", function()
                    if session then
                        session:SeekTo(ev.time)
                        session.status = "paused"
                    end
                end)
            else
                row.iconBtn:Hide()
            end

            -- Format source, detail text
            local catColor = CAT_COLORS[ev.cat] or { r = 0.7, g = 0.7, b = 0.7 }
            local catHex = string.format("%02x%02x%02x",
                catColor.r * 255, catColor.g * 255, catColor.b * 255)

            if ev.cat == "death" then
                row.srcText:SetText("")
                row.spellText:SetText("|cffff0000DEATH|r")
                row.iconBtn:Hide()
                row.detailText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r")

            elseif ev.type == "damage" then
                row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
                row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
                local detail = "> " .. ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r"
                if ev.amount then
                    local amtStr = AbbrevNumber(ev.amount)
                    if ev.critical then amtStr = amtStr .. "*" end
                    detail = detail .. "  |cffff4444-" .. amtStr .. "|r"
                end
                row.detailText:SetText(detail)

            elseif ev.type == "heal" or ev.type == "absorb" then
                row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
                row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
                local detail = ""
                if ev.dstName and ev.dstName ~= ev.srcName then
                    detail = "> " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
                end
                if ev.amount then
                    local amtStr = AbbrevNumber(ev.amount)
                    if ev.critical then amtStr = amtStr .. "*" end
                    if ev.type == "absorb" then
                        detail = detail .. "  |cffffff00" .. amtStr .. " abs|r"
                    else
                        detail = detail .. "  |cff44ff44+" .. amtStr .. "|r"
                    end
                end
                row.detailText:SetText(detail)

            elseif ev.type == "interrupt" then
                row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
                row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
                local detail = ""
                if ev.dstName then
                    detail = "> " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
                end
                if ev.extraSpell then
                    detail = detail .. " |cff888888(" .. ev.extraSpell .. ")|r"
                end
                row.detailText:SetText(detail)

            elseif ev.type == "dispel" or ev.type == "steal" then
                row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
                local verb = ev.type == "steal" and "stole" or "dispelled"
                row.spellText:SetText("|cff" .. catHex .. verb .. "|r")
                local detail = ""
                if ev.extraSpell then
                    detail = "|cffffff00" .. ev.extraSpell .. "|r"
                end
                if ev.dstName then
                    detail = detail .. " > " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
                end
                row.detailText:SetText(detail)

            elseif ev.type == "aura_applied" then
                row.srcText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r")
                local prefix = (ev.auraType == "DEBUFF") and "|cffff6666+" or "|cff66ff66+"
                row.spellText:SetText(prefix .. (ev.spellName or "?") .. "|r")
                row.detailText:SetText("")

            elseif ev.type == "aura_removed" then
                row.srcText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r")
                local prefix = (ev.auraType == "DEBUFF") and "|cffff6666-" or "|cff66ff66-"
                row.spellText:SetText(prefix .. (ev.spellName or "?") .. "|r")
                row.detailText:SetText("")

            elseif ev.type == "aura_break" then
                row.srcText:SetText(ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r")
                row.spellText:SetText("|cffff8800" .. (ev.spellName or "?") .. "|r")
                local detail = "|cffff8800broken|r"
                if ev.extraSpell then
                    detail = detail .. " |cff888888(by " .. ev.extraSpell .. ")|r"
                end
                row.detailText:SetText(detail)

            elseif ev.type == "miss" then
                row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
                row.spellText:SetText("|cff888888" .. (ev.spellName or "?") .. "|r")
                row.detailText:SetText("> " .. ClassColorStr(ev.dstClass) .. (ev.dstName or "?") .. "|r" ..
                    "  |cff888888" .. (ev.missType or "MISS") .. "|r")

            else
                -- cast_success, cast_start, summon, energize, drain, etc.
                row.srcText:SetText(ClassColorStr(ev.srcClass) .. (ev.srcName or "?") .. "|r")
                row.spellText:SetText("|cff" .. catHex .. (ev.spellName or "?") .. "|r")
                local detail = ""
                if ev.dstName and ev.dstName ~= ev.srcName then
                    detail = "> " .. ClassColorStr(ev.dstClass) .. ev.dstName .. "|r"
                end
                if ev.amount and ev.amount ~= 0 then
                    detail = detail .. "  " .. AbbrevNumber(math.abs(ev.amount))
                end
                row.detailText:SetText(detail)
            end

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
                    row.timeText:SetAlpha(1.0)
                    row.srcText:SetAlpha(1.0)
                    row.iconBtn:SetAlpha(1.0)
                    row.spellText:SetAlpha(1.0)
                    row.detailText:SetAlpha(1.0)
                    lastPastIdx = idx
                else
                    row.timeText:SetAlpha(0.3)
                    row.srcText:SetAlpha(0.3)
                    row.iconBtn:SetAlpha(0.3)
                    row.spellText:SetAlpha(0.3)
                    row.detailText:SetAlpha(0.3)
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
                m = CreateFrame("Button", nil, self.scrubTrack)
                m:SetSize(6, 14)
                m:SetFrameLevel(self.scrubTrack:GetFrameLevel() + 2)
                m.tex = m:CreateTexture(nil, "OVERLAY")
                m.tex:SetSize(2, 10)
                m.tex:SetPoint("CENTER")
                self.markerPool[i] = m
            end
            local frac = session.matchDuration > 0 and (marker.time / session.matchDuration) or 0
            local trackW = self.scrubTrack:GetWidth()
            m:ClearAllPoints()
            m:SetPoint("CENTER", self.scrubTrack, "LEFT", trackW * frac, 0)

            local cc = CAT_COLORS[marker.cat] or { r = 1, g = 1, b = 1 }
            m.tex:SetColorTexture(cc.r, cc.g, cc.b, 0.8)

            -- Tooltip on hover
            local label = marker.label or "?"
            local playerName = marker.player or ""
            local timeStr = FormatTime(marker.time)
            m:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(label, cc.r, cc.g, cc.b)
                if playerName ~= "" then
                    GameTooltip:AddLine(playerName, 1, 1, 1)
                end
                GameTooltip:AddLine(timeStr, 0.6, 0.6, 0.6)
                GameTooltip:Show()
            end)
            m:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            -- Click to seek
            m:SetScript("OnClick", function()
                if session then
                    session:SeekTo(marker.time)
                    session.status = "paused"
                end
            end)
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
    frame:SetFrameStrata("DIALOG")
    frame:Raise()

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
    if not game.eventLog then
        frame.errorText:SetText("No game log recorded for this match.")
        frame.errorText:Show()
        frame.unitPanel:Hide()
        frame.feedPanel:Hide()
        frame.transport:Hide()
        frame:Show()
        return
    end

    local newSession, err = self:CreateReplaySession(game.eventLog)
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
        chip.isOn = chip.cat == "all" or true
        if chip.bg and chip.label then
            if chip.isOn then
                chip.bg:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 0.15)
                chip.label:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
            end
        end
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
