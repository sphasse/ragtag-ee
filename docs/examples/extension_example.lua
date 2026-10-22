-- docs/examples/extension_example.lua
-- A complete universe extension. To try it, copy it into ee/ragtag/verse/extensions/
-- and run `python tools/check.py --fix`. Every scenario then gets this content,
-- with no scenario changes needed.

VERSE.extend({
    id = "juniper_waystation",
    title = "Juniper Waystation and the Cinder Reach smugglers' run",

    stations = {
        {cs = "Juniper Waystation", tmpl = "Small Station", fac = "Independent", x = -72, y = 64,
         shop = {"missile_racks", "engine_tune"},
         flavor = "Juniper Waystation. Hot coffee, cold storage, no manifests.",
         desc = "A smugglers' rest stop in the dark behind the red sun Cinder."},
    },
    regions = {
        {name = "Juniper Reach", x = -72, y = 64, r = 10, danger = 0,
         desc = "Juniper Reach: a quiet back road behind Cinder that smugglers use to skip the Arbiter Line."},
    },
    nebula_fields = {
        {x = -80, y = 70, r = 8, count = 4},
    },
    salvage = {
        {x = -66, y = 72, tier = 0},
    },
    -- Border freighters now call at Juniper too.
    route_stops = {border = {"Juniper Waystation"}},
    rumors = {
        "There's a waystation out behind Cinder. Juniper. They don't check manifests and they don't ask questions.",
    },
    lore = {
        "Juniper Waystation, behind the red sun Cinder, is where Border smugglers wait out Concord sweeps.",
    },
})
