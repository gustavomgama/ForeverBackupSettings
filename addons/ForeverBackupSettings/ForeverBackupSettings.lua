local addonName, ns = ...

ns.db = {
    profiles = {},
    defaultProfile = nil,
    lastSavedHash = nil,
    autoSave = true,
}

-- Curated CVar whitelist (extend as needed)
local CVARS = {
    "Sound_MasterVolume", "Sound_MusicVolume", "Sound_AmbienceVolume",
    "Sound_DialogVolume", "Sound_EnableAllSound",
    "cameraDistanceMax", "cameraDistanceMaxFactor", "cameraPitchMoveSpeed",
    "cameraYawMoveSpeed", "cameraSmoothStyle",
    "uiScale", "useUiScale",
    "nameplateShowEnemies", "nameplateShowFriends",
    "autoLootDefault", "autoSelfCast", "autoDismountFlying",
    "showTargetOfTarget", "scriptErrors",
}

local function snapshotCVars()
    local t = {}
    for _, c in ipairs(CVARS) do
        local v = C_CVar.GetCVar(c)
        if v ~= nil then t[c] = v end
    end
    return t
end

local function snapshotKeybinds()
    local t = {}
    -- iterate common actions
    local actions = { "MOVEFORWARD", "MOVEBACKWARD", "STRAFELEFT", "STRAFERIGHT",
        "JUMP", "SITORSTAND", "TOGGLEAUTORUN", "PITCHUP", "PITCHDOWN" }
    for _, a in ipairs(actions) do
        local k1, k2 = GetBindingKey(a)
        if k1 or k2 then t[a] = { k1, k2 } end
    end
    return t
end

local function snapshotActionBars()
    local t = {}
    for slot = 1, 120 do
        local typ, id = GetActionInfo(slot)
        if typ then t[slot] = { type = typ, id = id } end
    end
    return t
end

local function snapshot()
    return { cvars = snapshotCVars(), keybinds = snapshotKeybinds(), actionbars = snapshotActionBars(), time = time() }
end

local function hashSnapshot(s)
    local parts = {}
    for k, v in pairs(s.cvars) do parts[#parts+1] = k .. "=" .. tostring(v) end
    for k, v in pairs(s.keybinds) do
        parts[#parts+1] = k .. "=" .. tostring(v[1]) .. "," .. tostring(v[2])
    end
    for slot, info in pairs(s.actionbars or {}) do
        parts[#parts+1] = "ab" .. slot .. "=" .. tostring(info.type) .. "," .. tostring(info.id)
    end
    table.sort(parts)
    return table.concat(parts, "|")
end

local function applyCVars(prof)
    for k, v in pairs(prof.cvars or {}) do
        C_CVar.SetCVar(k, v)
    end
end

local function applyKeybinds(prof)
    for action, keys in pairs(prof.keybinds or {}) do
        -- clear existing
        local k1, k2 = GetBindingKey(action)
        if k1 then SetBinding(k1) end
        if k2 then SetBinding(k2) end
        if keys[1] then SetBinding(keys[1], action) end
        if keys[2] then SetBinding(keys[2], action) end
    end
    SaveBindings(1) -- account bindings
end

local function applyActionBars(prof)
    -- clear all slots first
    for slot = 1, 120 do
        local typ = GetActionInfo(slot)
        if typ then
            PickupAction(slot)
            ClearCursor()
        end
    end
    -- place saved actions
    for slot, info in pairs(prof.actionbars or {}) do
        local ok = pcall(function()
            if info.type == "spell" then
                PickupSpell(info.id)
            elseif info.type == "macro" then
                PickupMacro(info.id)
            elseif info.type == "item" then
                PickupItem(info.id)
            end
            PlaceAction(slot)
            ClearCursor()
        end)
        if not ok then ClearCursor() end
    end
end

local function applyProfile(name)
    local prof = ns.db.profiles[name]
    if not prof then print("Profile not found: " .. name); return end
    applyCVars(prof)
    applyKeybinds(prof)
    applyActionBars(prof)
    print("Applied profile: " .. name)
end

local function saveProfile(name)
    name = name or ns.db.lastProfile or (UnitName("player") .. "-" .. GetRealmName())
    ns.db.profiles[name] = snapshot()
    ns.db.lastProfile = name
    ns.db.lastSavedHash = hashSnapshot(ns.db.profiles[name])
    print("Saved profile: " .. name)
end

-- dirty detection
local function isDirty()
    local cur = hashSnapshot(snapshot())
    return cur ~= ns.db.lastSavedHash
end

-- slash commands
SLASH_FOREVERBACKUPSETTINGS1 = "/fbs"
SLASH_FOREVERBACKUPSETTINGS2 = "/foreverbackupsettings"
SlashCmdList["FOREVERBACKUPSETTINGS"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" or msg == "save" then
        saveProfile()
    elseif msg:sub(1, 5) == "save " then
        saveProfile(msg:sub(6))
    elseif msg:sub(1, 6) == "apply " then
        applyProfile(msg:sub(7))
    elseif msg == "dirty" then
        print("Dirty: " .. tostring(isDirty()))
    else
        print("Usage: /fbs save [name] | /fbs apply <name> | /fbs dirty")
    end
end

-- auto save ticker
local ticker
local function startTicker()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(300, function()
        if not ns.db.autoSave then return end
        if isDirty() then
            local charKey = UnitName("player") .. "-" .. GetRealmName()
            saveProfile(ns.db.lastProfile or charKey)
        end
    end)
end

-- logout save
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        ForeverBackupSettingsDB = ForeverBackupSettingsDB or ns.db
        ns.db = ForeverBackupSettingsDB
        ns.db.profiles = ns.db.profiles or {}
        ns.db.autoSave = (ns.db.autoSave ~= false)
        ns.db.chars = ns.db.chars or {}
        startTicker()
        print("ForeverBackupSettings loaded")
        if Settings and Settings.RegisterCanvasLayoutCategory then
            local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
            Settings.RegisterAddOnCategory(cat)
            ns.category = cat
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
            ns.category = panel
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- new character detection: if no char profile, offer default
        local charKey = UnitName("player") .. "-" .. GetRealmName()
        if not ns.db.chars[charKey] and ns.db.defaultProfile and ns.db.profiles[ns.db.defaultProfile] then
            ns.db.chars[charKey] = true
            applyProfile(ns.db.defaultProfile)
            print("Applied default profile to new character")
        end
    elseif event == "PLAYER_LOGOUT" then
        if ns.db and ns.db.autoSave then saveProfile() end
    end
end)

-- settings panel (minimal)
local panel = CreateFrame("Frame")
panel.name = "Forever Backup Settings"
local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Forever Backup Settings")

local profileLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
profileLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
profileLabel:SetText("Profile name:")

local profileEdit = CreateFrame("EditBox", addonName .. "ProfileEdit", panel, "InputBoxTemplate")
profileEdit:SetPoint("LEFT", profileLabel, "RIGHT", 8, 0)
profileEdit:SetSize(160, 20)
profileEdit:SetAutoFocus(false)
profileEdit:SetText(UnitName("player"))

local saveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
saveBtn:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -12)
saveBtn:SetSize(100, 24)
saveBtn:SetText("Save")
saveBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" then name = nil end
    saveProfile(name)
end)

local applyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
applyBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
applyBtn:SetSize(100, 24)
applyBtn:SetText("Apply")
applyBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" then print("Enter profile name"); return end
    applyProfile(name)
end)

local defaultBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
defaultBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
defaultBtn:SetSize(120, 24)
defaultBtn:SetText("Set Default")
defaultBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" or not ns.db.profiles[name] then print("Profile not found"); return end
    ns.db.defaultProfile = name
    print("Default profile set: " .. name)
end)

local statusText = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
statusText:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -12)
statusText:SetText("Ready")

-- panel registration handled in ADDON_LOADED above
