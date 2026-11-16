-- ee/ragtag/core/gm_tools.lua
-- GM tools every campaign scenario gets: campaign backup and restore slots.
-- Part of core (RT). Loaded by ee/ragtag/core.lua; do not require directly.

--------------------------------------------------------------------------------
-- Common GM tools
--------------------------------------------------------------------------------

function RT.addCampaignGMFunctions()
    -- Campaign status / stats / achievements live in the scenario's "Campaign Status" popup.
    -- Credit adjustment buttons removed: scenarios provide their own granular controls

    -- (No "Save campaign" button: the campaign autosaves every 60 s and on every flag,
    -- reputation, credit and job event. Use a backup slot to keep a restore point.)
    addGMFunction("Backup campaign", function() RT.showBackupMenu() end)
    addGMFunction("Restore campaign", function() RT.showRestoreMenu() end)
    addGMFunction("Sounds...", function() RT.showSoundMenu() end)
end

--------------------------------------------------------------------------------
-- Campaign backups: numbered slots in script storage (the GM console has no text input).
-- A slot is a copy of the campaign JSON under "<campaign key>.backup.<n>". Restoring writes the
-- slot over the live save and freezes saving, because the running game would otherwise
-- overwrite it from memory: restart the scenario and choose Continue to load it.
--------------------------------------------------------------------------------

RT.BACKUP_SLOTS = 6

function RT.backupKey(n) return RT.CAMPAIGN_KEY .. ".backup." .. n end

local function _fmtHM(seconds)
    seconds = math.floor(tonumber(seconds) or 0)
    return string.format("%dh%02d", seconds // 3600, (seconds % 3600) // 60)
end

-- Button label for a slot: "2: 1h25 4200cr" or "2: empty". Max ~18 characters.
function RT.backupLabel(n)
    local raw = getScriptStorage():get(RT.backupKey(n))
    if type(raw) ~= "string" or raw == "" then return n .. ": empty" end
    local ok, c = pcall(fromJSON, raw)
    if not ok or type(c) ~= "table" then return n .. ": unreadable" end
    local secs = type(c.stats) == "table" and c.stats.play_seconds or 0
    return string.format("%d: %s %dcr", n, _fmtHM(secs), math.floor(tonumber(c.credits) or 0))
end

function RT.backupCampaign(n)
    if RT.campaign == nil then return false end
    if RT._saves_frozen then return false end
    RT.saveCampaign()   -- sync credits and extra ships from the live ships first
    getScriptStorage():set(RT.backupKey(n), toJSON(RT.campaign))
    return true
end

function RT.restoreCampaign(n)
    local raw = getScriptStorage():get(RT.backupKey(n))
    if type(raw) ~= "string" or raw == "" then return false end
    -- Keep what we are about to overwrite, in case the restore was a mistake.
    local live = getScriptStorage():get(RT.CAMPAIGN_KEY)
    if type(live) == "string" and live ~= "" then
        getScriptStorage():set(RT.CAMPAIGN_KEY .. ".before_restore", live)
    end
    getScriptStorage():set(RT.CAMPAIGN_KEY, raw)
    RT._saves_frozen = true
    return true
end

local function _backToMainGM()
    clearGMFunctions()
    if addSessionGMFunctions then addSessionGMFunctions() else RT.addCampaignGMFunctions() end
end

function RT.showBackupMenu()
    clearGMFunctions()
    addGMFunction("← Back to Main", _backToMainGM)
    if RT._saves_frozen then
        addGMFunction("Restart to unfreeze", function()
            addGMMessage("A backup was restored. Restart the scenario and choose Continue; saving is paused until then.")
        end)
        return
    end
    for n = 1, RT.BACKUP_SLOTS do
        addGMFunction(RT.backupLabel(n), function()
            local ok = RT.backupCampaign(n)
            addGMMessage(ok and ("Campaign backed up to slot " .. n .. ".") or "Backup failed: no campaign loaded.")
            RT.showBackupMenu()   -- redraw with the updated label
        end)
    end
end

function RT.showRestoreMenu()
    clearGMFunctions()
    addGMFunction("← Back to Main", _backToMainGM)
    for n = 1, RT.BACKUP_SLOTS do
        local label = RT.backupLabel(n)
        local empty = label:find("empty", 1, true) ~= nil
        addGMFunction(label, function()
            if empty then
                addGMMessage("Slot " .. n .. " is empty.")
                return
            end
            -- Confirmation step: restoring replaces the whole saved campaign.
            clearGMFunctions()
            addGMFunction("Cancel", function() RT.showRestoreMenu() end)
            addGMFunction("Restore slot " .. n, function()
                if RT.restoreCampaign(n) then
                    addGMMessage("Slot " .. n .. " restored. Restart the scenario and choose Continue to load it. "
                        .. "Saving is paused until you restart. (Your previous save is kept under '.before_restore'.)")
                else
                    addGMMessage("Restore failed: slot " .. n .. " is empty or unreadable.")
                end
                RT.showRestoreMenu()
            end)
        end)
    end
end
