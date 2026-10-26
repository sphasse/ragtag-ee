-- GM-only actions (the director refuses to send these from the model).

DIR.ACTIONS.set_objective = function(a)
    RT.setObjective(DIR._h.str(a.text, 160, ""))
    return true, "objective set"
end

DIR.ACTIONS.restore_campaign = function(a, cmd)
    if cmd.source ~= "gm" then return false, "GM only" end
    if type(a.campaign) ~= "table" then return false, "campaign table required" end
    getScriptStorage():set(RT.CAMPAIGN_KEY, toJSON(a.campaign))
    RT.loadCampaign()
    return true, "campaign restored; restart the scenario to apply upgrades"
end

DIR.ACTIONS.rename_ship = function(a, cmd)
    if cmd.source ~= "gm" then return false, "GM only" end
    local name = DIR._h.str(a.name, 24, nil)
    if name == nil or name == "" then return false, "name required" end
    RT.campaign.ship_name = name
    if RT.valid(RT.player) then RT.player:setCallSign(name); RT.named[name] = RT.player end
    RT.saveCampaign()
    return true, "ship renamed " .. name
end
