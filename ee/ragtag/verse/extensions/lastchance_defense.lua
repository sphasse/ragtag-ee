-- Last Chance Outpost defense platforms
-- Adds laser defense stations between Last Chance Outpost and the Maw
-- to protect the last inhabited outpost from Hollow incursions.

VERSE.extend({
    id = "lastchance_defense",
    title = "Last Chance Outpost defense perimeter",

    -- Defense platforms protecting the approach from the Maw
    garrisons = {
        {fac = "Independent", x = 140, y = 75, ships = {"Defense platform"}},
        {fac = "Independent", x = 145, y = 90, ships = {"Defense platform"}},
        {fac = "Independent", x = 148, y = 105, ships = {"Defense platform"}},
    },

    lore = {
        "Last Chance Outpost maintains a perimeter of automated defense platforms. They keep the Hollow at bay. Mostly.",
    },

    rumors = {
        "Three defense platforms guard the route to Lastchance. If they're not shooting at you, you're doing something right.",
        "The platforms around Lastchance are old Concord hardware. Still got teeth, though.",
    },
})
