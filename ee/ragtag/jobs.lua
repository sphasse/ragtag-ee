-- ee/ragtag/jobs.lua
-- Job board: load the engine then all type modules.
-- To add a type: create ee/ragtag/jobs/<type>.lua and add one line below.
-- To remove a type: comment out that line.

require("ragtag/jobs/_engine.lua")
require("ragtag/jobs/delivery.lua")
require("ragtag/jobs/salvage.lua")
require("ragtag/jobs/hacking.lua")
require("ragtag/jobs/tailing.lua")
require("ragtag/jobs/destroy.lua")
require("ragtag/jobs/boarding.lua")
require("ragtag/jobs/escort.lua")
