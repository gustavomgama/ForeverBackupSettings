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

local function snapshot()
    return { cvars = snapshotCVars(), keybinds = snapshotKeybinds(), time = time() }
end

local function hashSnapshot(s)
    local parts = {}
    for k, v in pairs(s.cvars) do parts[#parts+1] = k .. "=" .. tostring(v) end
    for k, v in pairs(s.keybinds) do
        parts[#parts+1] = k .. "=" .. tostring(v[1]) .. "," .. tostring(v[2])
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

local function applyProfile(name)
    local prof = ns.db.profiles[name]
    if not prof then print("Profile not found: " .. name); return end
    applyCVars(prof)
    applyKeybinds(prof)
    print("Applied profile: " .. name)
end

local function saveProfile(name)
    name = name or (UnitName("player") .. "-" .. GetRealmName())
    ns.db.profiles[name] = snapshot()
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
        if isDirty() then saveProfile() end
    end)
end

-- logout save
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        ForeverBackupSettingsDB = ForeverBackupSettingsDB or ns.db
        ns.db = ForeverBackupSettingsDB
        ns.db.profiles = ns.db.profiles or {}
        ns.db.autoSave = (ns.db.autoSave ~= false)
        startTicker()
        print("ForeverBackupSettings loaded")
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

local saveBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
saveBtn:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
saveBtn:SetSize(100, 24)
saveBtn:SetText("Save Profile")
saveBtn:SetScript("OnClick", function() saveProfile() end)

frame:RegisterEvent("ADDON_LOADED")
-- register panel after load (reuse same event above by adding here not possible; do in ADDON_LOADED via hook)
-- We'll register in the existing handler by adding code below via a second frame
local regFrame = CreateFrame("Frame")
regFrame:RegisterEvent("ADDON_LOADED")
regFrame:SetScript("OnEvent", function(self, e, name)
    if name ~= addonName then return end
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local cat = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(cat)
        ns.category = cat
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        ns.category = panel
    end
end)