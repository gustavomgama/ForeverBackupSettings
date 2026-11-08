local addonName, ns = ...
local panel, statusText

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
    "graphicsQuality", "graphicsShadowQuality", "graphicsTextureResolution",
    "graphicsParticleDensity", "graphicsGroundClutter", "graphicsViewDistance",
    "graphicsEnvironmentDetail", "graphicsSpellDensity",
    "Sound_EnableSoundWhenGameIsInBG", "Sound_EnableMusic",
    "Sound_NumChannels", "Sound_OutputDriverIndex",
    "nameplateShowAll", "nameplateShowEnemyUnits", "nameplateShowFriendlyUnits",
    "nameplateMotion", "nameplateMaxDistance",
    "cameraIndirectVisibility",
    "autoInteract", "autoPushToPass", "autoTrackQuests",
    "showVKeyCastbar", "showCastBar", "showPartyFrames",
    "combatTextFloatMode", "combatTextMessagePetDamage",
    "chatBubbleScale", "chatBubbleName",
    "secureAbilityToggle", "ActionButtonUseKeyDown",
}

local function deepCopy(v, seen)
    if type(v) ~= "table" then return v end
    seen = seen or {}
    if seen[v] then return seen[v] end
    local t = {}
    seen[v] = t
    for k, val in pairs(v) do t[deepCopy(k, seen)] = deepCopy(val, seen) end
    return t
end

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
    for i = 1, GetNumBindings() do
        local command, _, k1, k2 = GetBinding(i)
        if command and (k1 or k2) then t[command] = { k1, k2 } end
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

local function snapshotAddons()
    local t = { list = {}, settings = {} }
    local n = C_AddOns.GetNumAddOns()
    for i = 1, n do
        local name = C_AddOns.GetAddOnName(i)
        if name then
            local title = C_AddOns.GetAddOnTitle(name)
            local state = C_AddOns.GetAddOnEnableState(name)
            t.list[name] = { title = title, enabled = state }
            local isUserAddon = name:sub(1, 9) ~= "Blizzard_"
            if isUserAddon and state ~= 0 and _G[name .. "DB"] ~= nil then
                t.settings[name] = { var = name .. "DB", value = deepCopy(_G[name .. "DB"]) }
            end
        end
    end
    return t
end

local function snapshot()
    return { cvars = snapshotCVars(), keybinds = snapshotKeybinds(), actionbars = snapshotActionBars(), addons = snapshotAddons(), time = time() }
end

local function hashSnapshot(s)
    local parts = {}
    for k, v in pairs(s.cvars or {}) do parts[#parts+1] = k .. "=" .. tostring(v) end
    for k, v in pairs(s.keybinds or {}) do
        parts[#parts+1] = k .. "=" .. tostring(v[1]) .. "," .. tostring(v[2])
    end
    for slot, info in pairs(s.actionbars or {}) do
        parts[#parts+1] = "ab" .. slot .. "=" .. tostring(info.type) .. "," .. tostring(info.id)
    end
    for name, _ in pairs((s.addons or {}).list or {}) do
        parts[#parts+1] = "addon:" .. name
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
    local saved = prof.keybinds or {}
    -- clear bindings not present in the profile
    for i = 1, GetNumBindings() do
        local command, _, k1, k2 = GetBinding(i)
        if command and (k1 or k2) and not saved[command] then
            if k1 then SetBinding(k1) end
            if k2 then SetBinding(k2) end
        end
    end
    -- apply saved bindings
    for action, keys in pairs(saved) do
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
                if C_Spell and C_Spell.PickupSpell then C_Spell.PickupSpell(info.id) else PickupSpell(info.id) end
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

local function applyAddons(prof)
    local restored = 0
    for name, info in pairs((prof.addons or {}).settings or {}) do
        if not C_AddOns.DoesAddOnExist(name) then
            print("Addon not installed, skipping: " .. name)
        else
            _G[info.var] = info.value
            restored = restored + 1
            print("Restored settings for: " .. name)
        end
    end
    if restored > 0 then print("Reload UI to fully apply addon settings") end
    -- restore enabled state or warn if not installed
    for name, info in pairs((prof.addons or {}).list or {}) do
        if not C_AddOns.DoesAddOnExist(name) then
            print("Addon not installed: " .. name .. " (install to restore its settings)")
        elseif info.enabled ~= nil then
            local state = C_AddOns.GetAddOnEnableState(name)
            if state ~= nil and state ~= info.enabled then
                pcall(function()
                    if info.enabled ~= 0 then
                        C_AddOns.EnableAddOn(name)
                    else
                        C_AddOns.DisableAddOn(name)
                    end
                end)
            end
        end
    end
end

local pendingApply = nil
local function applyProfile(name)
    local prof = ns.db.profiles[name]
    if type(prof) ~= "table" then print("Profile not found: " .. tostring(name)); return end
    if InCombatLockdown() then
        pendingApply = name
        print("In combat - apply queued: " .. name)
        return
    end
    applyCVars(prof)
    applyKeybinds(prof)
    applyActionBars(prof)
    applyAddons(prof)
    print("Applied profile: " .. name)
    if statusText then statusText:SetText("Applied: " .. name) end
    if ns.RefreshPanel then ns.RefreshPanel() end
end

local function saveProfile(name)
    name = name or ns.db.lastProfile or ((UnitName("player") or "char") .. "-" .. (GetRealmName() or "realm"))
    ns.db.profiles[name] = snapshot()
    ns.db.lastProfile = name
    ns.db.lastSavedAt = time()
    ns.db.lastSavedHash = hashSnapshot(ns.db.profiles[name])
    print("Saved profile: " .. name)
    if statusText then statusText:SetText("Saved: " .. name) end
    if ns.RefreshPanel then ns.RefreshPanel() end
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
    local cmd, rest = msg:match("^(%S*)%s*(.*)$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "save" then
        saveProfile(rest ~= "" and rest or nil)
    elseif cmd == "apply" then
        if rest == "" then print("Usage: /fbs apply <name>") else applyProfile(rest) end
    elseif cmd == "list" then
        print("Profiles:")
        for name, _ in pairs(ns.db.profiles or {}) do print(" - " .. name) end
        if ns.db.defaultProfile then print("Default: " .. ns.db.defaultProfile) end
    elseif cmd == "default" then
        if ns.db.profiles[rest] then ns.db.defaultProfile = rest; print("Default set: " .. rest) else print("Not found") end
    elseif cmd == "dirty" then
        print("Dirty: " .. tostring(isDirty()))
    else
        print("Usage: /fbs save [name] | /fbs apply <name> | /fbs list | /fbs default <name> | /fbs dirty")
    end
end

-- auto save ticker
local ticker
local function startTicker()
    if ticker then ticker:Cancel() end
    ticker = C_Timer.NewTicker(300, function()
        if statusText then
            statusText:SetText(isDirty() and "Unsaved changes" or "Up to date")
        end
        if not ns.db.autoSave then return end
        if isDirty() then
            local charKey = ((UnitName("player") or "char") .. "-" .. (GetRealmName() or "realm"))
            saveProfile(charKey)
        end
    end)
end

-- logout save
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGOUT")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
            ns.categoryID = cat.GetID and cat:GetID() or cat.ID
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
            ns.category = panel
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- new character detection: if no char profile, offer default
        local charKey = ((UnitName("player") or "char") .. "-" .. (GetRealmName() or "realm"))
        if not ns.db.chars[charKey] then
            ns.db.chars[charKey] = true
            if ns.db.defaultProfile and ns.db.profiles[ns.db.defaultProfile] then
                applyProfile(ns.db.defaultProfile)
                print("Applied default profile to new character")
            end
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then
            local n = pendingApply
            pendingApply = nil
            applyProfile(n)
        end
    elseif event == "PLAYER_LOGOUT" then
        if ns.db and ns.db.autoSave then
            saveProfile(((UnitName("player") or "char") .. "-" .. (GetRealmName() or "realm")))
        end
    end
end)

-- settings panel (minimal)
panel = CreateFrame("Frame")
panel.name = "Forever Backup Settings"
local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 0, -4)
scroll:SetPoint("BOTTOMRIGHT", -28, 4)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(600, 760)
scroll:SetScrollChild(content)
local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("Forever Backup Settings")

local desc = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
desc:SetWidth(520)
desc:SetJustifyH("LEFT")
desc:SetText("Saves CVars, all keybinds, action bars, and addon settings into named profiles. Auto-saves every 5 minutes and on logout.")

local profileLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
profileLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
profileLabel:SetText("Profile name:")

local profileEdit = CreateFrame("EditBox", addonName .. "ProfileEdit", content, "InputBoxTemplate")
profileEdit:SetPoint("LEFT", profileLabel, "RIGHT", 8, 0)
profileEdit:SetSize(160, 20)
profileEdit:SetAutoFocus(false)
profileEdit:SetText(UnitName("player") or "")

local saveBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
saveBtn:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", 0, -12)
saveBtn:SetSize(100, 24)
saveBtn:SetText("Save")
saveBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" then name = nil end
    saveProfile(name)
end)

local applyBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
applyBtn:SetPoint("LEFT", saveBtn, "RIGHT", 8, 0)
applyBtn:SetSize(100, 24)
applyBtn:SetText("Apply")
applyBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" then print("Enter profile name"); return end
    applyProfile(name)
end)

local defaultBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
defaultBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
defaultBtn:SetSize(120, 24)
defaultBtn:SetText("Set Default")
defaultBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" or not ns.db.profiles[name] then print("Profile not found"); return end
    ns.db.defaultProfile = name
    print("Default profile set: " .. name)
    if ns.RefreshPanel then ns.RefreshPanel() end
end)

local deleteBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
deleteBtn:SetPoint("LEFT", defaultBtn, "RIGHT", 8, 0)
deleteBtn:SetSize(100, 24)
deleteBtn:SetText("Delete")
deleteBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" or not ns.db.profiles[name] then print("Profile not found"); return end
    StaticPopup_Show("FBS_CONFIRM_DELETE", name, nil, name)
end)

StaticPopupDialogs["FBS_CONFIRM_DELETE"] = {
    text = "Delete profile %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(self, name)
        ns.db.profiles[name] = nil
        if ns.db.defaultProfile == name then ns.db.defaultProfile = nil end
        print("Deleted profile: " .. name)
        if ns.RefreshPanel then ns.RefreshPanel() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function AddTip(btn, text)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
end
AddTip(saveBtn, "Save current settings under the profile name.")
AddTip(applyBtn, "Apply the named profile to this character.")
AddTip(defaultBtn, "Use this profile for new characters.")
AddTip(deleteBtn, "Delete the named profile.")

local dupBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
dupBtn:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -40)
dupBtn:SetSize(120, 24)
dupBtn:SetText("Duplicate")
dupBtn:SetScript("OnClick", function()
    local name = profileEdit:GetText()
    if name == "" or not ns.db.profiles[name] then print("Profile not found"); return end
    local newName = name .. "-copy"
    local i = 2
    while ns.db.profiles[newName] do newName = name .. "-copy" .. i; i = i + 1 end
    ns.db.profiles[newName] = deepCopy(ns.db.profiles[name])
    print("Duplicated to: " .. newName)
    if ns.RefreshPanel then ns.RefreshPanel() end
end)
AddTip(dupBtn, "Copy the named profile to <name>-copy.")

local refreshBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
refreshBtn:SetPoint("LEFT", dupBtn, "RIGHT", 8, 0)
refreshBtn:SetSize(100, 24)
refreshBtn:SetText("Refresh")
refreshBtn:SetScript("OnClick", function()
    if ns.RefreshPanel then ns.RefreshPanel() end
end)
AddTip(refreshBtn, "Refresh the profile list and preview.")

statusText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
statusText:SetPoint("TOPLEFT", saveBtn, "BOTTOMLEFT", 0, -12)
statusText:SetText("Ready")

local autoCb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
autoCb:SetPoint("TOPLEFT", dupBtn, "BOTTOMLEFT", 0, -16)
autoCb.text = autoCb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
autoCb.text:SetPoint("LEFT", autoCb, "RIGHT", 2, 0)
autoCb.text:SetText("Auto-save every 5 minutes and on logout")
autoCb:SetScript("OnClick", function(self)
    ns.db.autoSave = self:GetChecked() and true or false
end)

local listTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
listTitle:SetPoint("TOPLEFT", autoCb, "BOTTOMLEFT", 4, -16)
listTitle:SetText("Saved profiles")

local profileList = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
profileList:SetPoint("TOPLEFT", listTitle, "BOTTOMLEFT", 0, -6)
profileList:SetWidth(520)
profileList:SetJustifyH("LEFT")

local info = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
info:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -600)
info:SetWidth(520)
info:SetJustifyH("LEFT")
info:SetText("Saved data: CVars (whitelist), all keybinds, action bar slots, addon list, and addon SavedVariables. Disabled addons require the Lua exporter (tools/export_savedvars.lua).")

local footer = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
footer:SetPoint("TOPLEFT", content, "TOPLEFT", 16, -730)
footer:SetWidth(520)
footer:SetJustifyH("LEFT")
footer:SetText("v0.1.0  |  Commands: /fbs save [name]  /fbs apply <name>  /fbs list  /fbs default <name>  /fbs dirty")

local preview = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
preview:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -12)
preview:SetWidth(520)
preview:SetJustifyH("LEFT")

local function RefreshPanel()
    autoCb:SetChecked(ns.db.autoSave)
    local names = {}
    for n in pairs(ns.db.profiles or {}) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then
        profileList:SetText("None yet. Type a name above and press Save.")
    else
        local lines = {}
        for i, n in ipairs(names) do
            if i > 12 then lines[#lines + 1] = "  ... " .. (#names - 12) .. " more"; break end
            lines[#lines + 1] = (n == ns.db.defaultProfile and "* " or "  ") .. n
        end
        profileList:SetText(table.concat(lines, "\n"))
    end
    local st = {}
    if ns.db.defaultProfile then st[#st + 1] = "Default: " .. ns.db.defaultProfile end
    if ns.db.lastSavedAt then st[#st + 1] = "Last save: " .. date("%Y-%m-%d %H:%M", ns.db.lastSavedAt) end
    if ns.db.lastProfile then st[#st + 1] = "Last profile: " .. ns.db.lastProfile end
    local ex = ns.db.profiles["exported"]
    if type(ex) == "table" and ex.time then st[#st + 1] = "Exported: " .. date("%Y-%m-%d %H:%M", ex.time) end
    statusText:SetText(#st > 0 and table.concat(st, "   |   ") or "Ready")
    local prof = ns.db.profiles[profileEdit:GetText()]
    if type(prof) == "table" then
        local cv, kb, ab, ad = 0, 0, 0, 0
        for _ in pairs(prof.cvars or {}) do cv = cv + 1 end
        for _ in pairs(prof.keybinds or {}) do kb = kb + 1 end
        for _ in pairs(prof.actionbars or {}) do ab = ab + 1 end
        for _ in pairs((prof.addons or {}).settings or {}) do ad = ad + 1 end
        preview:SetText(string.format("Profile contents: %d CVars, %d keybinds, %d action slots, %d addon setting sets.", cv, kb, ab, ad))
    else
        preview:SetText("")
    end
end
ns.RefreshPanel = RefreshPanel
panel:SetScript("OnShow", RefreshPanel)
profileEdit:SetScript("OnTextChanged", RefreshPanel)
profileEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
profileEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- panel registration handled in ADDON_LOADED above

function ForeverBackupSettings_OnAddonCompartmentClick()
    if Settings and Settings.OpenToCategory and ns.categoryID then
        Settings.OpenToCategory(ns.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    end
end

function ForeverBackupSettings_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Forever Backup Settings")
    GameTooltip:AddLine("Click to open settings", 1, 1, 1)
    GameTooltip:Show()
end

function ForeverBackupSettings_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
