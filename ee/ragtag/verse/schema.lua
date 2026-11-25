-- ee/ragtag/verse/schema.lua
-- How universe data is declared and merged. Pure Lua with no engine calls, so
-- the game (via require) and the offline tools (tools/dump_verse.lua) run the
-- exact same code.
--
-- Every universe file calls VERSE.extend{...} once. Lists are appended in load
-- order: verse/drift.lua first, then verse/extensions/*.lua alphabetically.
--
--   VERSE.extend({
--       id = "my_extension",            -- required, unique
--       title = "What this adds",
--       stations = { {cs = "New Station", tmpl = "Small Station", fac = "Independent", x = 10, y = 20, ...} },
--                  -- optional: desc (one line, the station's scan text), lore (paragraphs for the
--                  -- Science database's Ports section; "\n\n" between paragraphs), shop (the upgrade lines its
--                  -- shipwright is a base for: "hull", "shields", "beams", ... see RT.UPGRADE_LINES), flavor
--       regions = { ... }, planets = { ... }, stars = { ... },
--       nebula_fields = { ... }, asteroid_fields = { ... }, garrisons = { ... },
--                  -- asteroid_fields kinds: "blob" (x, y, r), "belt" (x1, y1, x2, y2, width), "ring"
--                  -- (x, y, r1, r2, period: rocks orbiting the point, `period` s per turn at r1)
--       minefields = { ... }, hazards = { ... }, wreck_fields = { ... },
--       salvage = { ... }, routes = { ... }, rumors = { "..." },
--       gun_platforms = { {kind = "lance", fac = "Relic", x = 12, y = -95, max_range = 7} },
--                  -- PLATFORMS (ragtag/platforms.lua): "barrage" or "lance"; x, y and max_range in U
--       lore = { "A paragraph the AI director should know about this part of the universe." },
--       route_stops = { border = {"New Station"} },   -- add stops to existing routes
--   })
--
-- Field reference: see the entries in verse/drift.lua; every field used there
-- is supported in extensions too.

VERSE = VERSE or {}

VERSE.LISTS = {
    stars = "STARS", planets = "PLANETS", stations = "STATIONS", regions = "REGIONS",
    nebula_fields = "NEBULA_FIELDS", asteroid_fields = "ASTEROID_FIELDS", garrisons = "GARRISONS",
    minefields = "MINEFIELDS", hazards = "HAZARDS", wreck_fields = "WRECK_FIELDS",
    salvage = "SALVAGE", routes = "ROUTES", rumors = "RUMORS", lore = "LORE",
    gun_platforms = "GUN_PLATFORMS",
}
for _, T in pairs(VERSE.LISTS) do VERSE[T] = VERSE[T] or {} end
VERSE.extensions = VERSE.extensions or {}

function VERSE.extend(spec)
    assert(type(spec) == "table" and type(spec.id) == "string", "VERSE.extend needs a table with a string id")
    for _, e in ipairs(VERSE.extensions) do
        if e.id == spec.id then return end   -- already loaded
    end
    table.insert(VERSE.extensions, {id = spec.id, title = spec.title or spec.id})
    for key, T in pairs(VERSE.LISTS) do
        if spec[key] ~= nil then
            assert(type(spec[key]) == "table", spec.id .. ": " .. key .. " must be a list")
            for _, entry in ipairs(spec[key]) do
                if type(entry) == "table" then entry.source = spec.id end
                table.insert(VERSE[T], entry)
            end
        end
    end
    if spec.route_stops then
        for route_id, stops in pairs(spec.route_stops) do
            local found = false
            for _, r in ipairs(VERSE.ROUTES) do
                if r.id == route_id then
                    found = true
                    for _, s in ipairs(stops) do table.insert(r.stations, s) end
                end
            end
            assert(found, spec.id .. ": route_stops names unknown route '" .. tostring(route_id) .. "'")
        end
    end
end

-- Returns a list of problem strings (empty when the data is consistent).
function VERSE.validate()
    local problems = {}
    local function bad(fmt, ...) table.insert(problems, string.format(fmt, ...)) end
    local function needNum(kind, e, ...)
        for _, f in ipairs({...}) do
            if type(e[f]) ~= "number" then bad("%s %s (from %s): field '%s' must be a number", kind, tostring(e.name or e.cs or "?"), tostring(e.source), f) end
        end
    end

    local places = {}
    local function addPlace(name, kind, src)
        if name == nil then bad("%s from %s has no name", kind, tostring(src)); return end
        if places[name] then bad("duplicate place name '%s' (%s from %s, already a %s)", name, kind, tostring(src), places[name]) end
        places[name] = kind
    end
    for _, s in ipairs(VERSE.STARS) do addPlace(s.name, "star", s.source); needNum("star", s, "x", "y", "r") end
    for _, p in ipairs(VERSE.PLANETS) do addPlace(p.name, "planet", p.source); needNum("planet", p, "x", "y", "r") end
    for _, s in ipairs(VERSE.STATIONS) do
        addPlace(s.cs, "station", s.source)
        needNum("station", s, "x", "y")
        if type(s.tmpl) ~= "string" or type(s.fac) ~= "string" then bad("station %s needs tmpl and fac", tostring(s.cs)) end
    end
    local region_names = {}
    for _, r in ipairs(VERSE.REGIONS) do
        needNum("region", r, "x", "y", "r", "danger")
        if region_names[r.name] then bad("duplicate region '%s'", tostring(r.name)) end
        region_names[r.name] = true
        if type(r.danger) == "number" and (r.danger < 0 or r.danger > 3) then bad("region %s: danger must be 0-3", r.name) end
    end
    for _, r in ipairs(VERSE.ROUTES) do
        for _, cs in ipairs(r.stations or {}) do
            if places[cs] ~= "station" then bad("route %s stops at unknown station '%s'", tostring(r.id), cs) end
        end
        if #(r.names or {}) < (r.count or 0) then bad("route %s has fewer names than ships", tostring(r.id)) end
    end
    for _, s in ipairs(VERSE.SALVAGE) do
        needNum("salvage", s, "x", "y", "tier")
    end
    for _, f in ipairs(VERSE.ASTEROID_FIELDS) do
        if f.kind == "ring" then
            needNum("asteroid ring", f, "x", "y", "r1", "r2")
            if type(f.r1) == "number" and type(f.r2) == "number" and not (f.r1 > 0 and f.r2 >= f.r1) then
                bad("asteroid ring at (%s, %s) from %s: needs 0 < r1 <= r2", tostring(f.x), tostring(f.y), tostring(f.source))
            end
        end
    end
    for _, g in ipairs(VERSE.GUN_PLATFORMS) do
        needNum("gun platform", g, "x", "y")
        if g.kind ~= nil and g.kind ~= "barrage" and g.kind ~= "lance" then
            bad("gun platform at (%s, %s) from %s: kind must be \"barrage\" or \"lance\"", tostring(g.x), tostring(g.y), tostring(g.source))
        end
        if type(g.fac) ~= "string" then bad("gun platform at (%s, %s) from %s needs fac", tostring(g.x), tostring(g.y), tostring(g.source)) end
    end
    return problems, places
end
