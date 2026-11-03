-- ee/ragtag/world.lua
-- Loader for the world plugin system.
-- Add one require() line per plugin below.
-- To migrate proximity spawns: add require("ragtag/world/proximity.lua")
-- and call WORLD.update(delta) in place of PROX.update(delta).

require("ragtag/world/_engine.lua")
require("ragtag/world/defenders.lua")
