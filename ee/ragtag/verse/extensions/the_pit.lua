-- The Pit: an unsanctioned fighting ring south of the Deep Shroud (nearer it than the Maw). The pit boss's
-- station sits just outside the ring's one opening, on the west side; the ring itself (15U across, dense
-- asteroids) and the bouts are the world plugin's (ee/ragtag/world/pit.lua, PIT.CX / PIT.CY match the region).

VERSE.extend({
    id = "the_pit",
    title = "The Pit: an unsanctioned fighting ring south of the Deep Shroud",

    stations = {
        -- no_defender: no station fighter (world/defenders.lua): it would fly through the ring and join the
        -- bouts, and nobody could tell whose side it was on.
        {cs = "The Pit", tmpl = "Small Station", fac = "Independent", x = 149, y = 32, no_defender = true,
         flavor = "The Pit. You fight, you get paid. You run, you don't.",
         desc = "A fight promoter's station beside a ring of asteroids. Bouts for money, no questions asked.",
         lore = "Nobody admits to owning the Pit. A pit boss with a gravel voice takes the sign-ups, books the "
             .. "fights and pays the purses in clean credits, and the crews who fight there come for the money "
             .. "and stay for the reputation.\n\n"
             .. "The ring is a fifteen-unit loop of rock with one way in. The rules are short: get inside before "
             .. "the clock runs out, don't leave until it's over, and whatever dies in the ring stays a private "
             .. "matter. The Concord would close it if it could find anyone to arrest."},
    },
    regions = {
        {name = "the Pit", x = 158, y = 32, r = 12, danger = 1,
         desc = "The Pit. A ring of rock south of the Deep Shroud, and crews who fight in it for money."},
    },
})
