-- give_credits: Pay or fine the crew.
-- args: amount (-300..300), reason
DIR.ACTIONS.give_credits = function(a)
    local h = DIR._h
    local amt = math.floor(h.num(a.amount, -DIR.config.credit_cap_per_action, DIR.config.credit_cap_per_action, 0))
    if amt == 0 then return false, "amount required" end
    if amt > 0 and DIR.credits_given + amt > DIR.config.credit_cap_per_session then
        return false, "session credit cap reached"
    end
    if amt > 0 then DIR.credits_given = DIR.credits_given + amt end
    RT.addCredits(amt, h.str(a.reason, 60, "director"))
    return true, "credits " .. amt
end
