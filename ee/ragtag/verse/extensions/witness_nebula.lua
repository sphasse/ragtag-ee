-- Nebula fields for the Witness arc escape route
-- Adds cover between Port Vesper and Dustmote Salvage for evading Concord patrols

VERSE.extend({
    id = "witness_nebula",
    title = "Nebula cover along the Dustmote run",

    -- Nebula patches southeast of the Port Vesper → Dustmote route
    -- Provides cover for ships running from Concord checkpoint
    nebula_fields = {
        {x = 65, y = -30, r = 8, count = 12},   -- Southeast of midpoint
        {x = 80, y = -45, r = 10, count = 15},  -- Deeper southeast, near Dustmote
        {x = 50, y = -35, r = 6, count = 8},    -- South of route
    },

    lore = {
        "The nebula patches between Port Vesper and Dustmote aren't dense enough to hide in forever, but they'll buy you time.",
    },

    rumors = {
        "If Concord's chasing you toward Dustmote, there's nebula to the southeast. Might give you an edge.",
    },
})
