# EmptyEpsilon Lua API signatures

Generated from the EmptyEpsilon source (scripts/api/ and src/) for the ECS-era engine, build 20261019. Use this to check a function exists and its argument order before writing scenario code. Entity methods are callable on any entity, but many only work if the entity has the relevant component (see api_notes.md).

## Contents
- Global functions
- Object constructors
- Entity methods (by file)


## Global functions

- `ScriptObject Script()` — Creates a new independent Lua script environment as a child of the current one.
- `void _(...)` — Define a string for internationalization. The string is added to the lists of those that can be translated for a given language.
- `void addCommsReply(string message, ScriptSimpleCallback callback)` — Adds a selectable reply option to a communications dialogue as a button with the given text.
- `void addEntryToShipsLog(entity ship, string entry, table color)` — Appends an entry to ship's relay log with the given color, which is an RGBA table {r, g, b, a} with component values from 0 to 255.
- `void addGMFunction(string name, ScriptSimpleCallback callback)` — Defines a function to call from a button on the GM console.
- `void addGMMessage(string message)` — Displays a dismissable message on the GM console.
- `void applyDamageToEntity(entity target, number amount, table damage_info)` — Applies amount of damage to the target entity using the parameters in damage_info.
- `bool areBeamShieldFrequenciesUsed()` — Returns whether the "Beam/Shield Frequencies" setting is enabled in the running scenario.
- `number beamVsShieldFrequencyDamageFactor(integer beam_frequency, integer shield_frequency)` — Returns a damage multiplier for a beam at beam_frequency striking a shield at shield_frequency.
- `void clearGMFunctions()` — Removes all functions from the GM console.
- `void commandAbortDock(entity ship)` — Aborts an in-progress docking approach for the given ship.
- `void commandAbortJump(entity ship)` — Aborts an active jump.
- `void commandActivateSelfDestruct(entity ship)` — Activates the self-destruct sequence for the given ship.
- `void commandAddWaypoint(entity ship, number x, number y)` — Adds a new navigation waypoint at the given coordinates for the given ship.
- `void commandAnswerCommHail(entity ship, boolean answer)` — Accepts or declines an incoming communications hail for the given ship.
- `void commandCancelSelfDestruct(entity ship)` — Cancels an active self-destruct sequence for the given ship before the countdown begins. Has no effect once the countdown has started.
- `void commandClearScienceLink(entity ship)` — Clears the science station's link to a scan probe for the given ship.
- `void commandCloseTextComm(entity ship)` — Closes any active text communications for the given ship.
- `void commandCombatManeuverBoost(entity ship, number amount)` — Triggers a combat maneuver boost for the given ship.
- `void commandCombatManeuverStrafe(entity ship, number amount)` — Triggers a combat maneuver strafe for the given ship.
- `void commandConfirmDestructCode(entity ship, integer code_index, integer code)` — Submits a confirmation code for the self-destruct sequence on the given ship.
- `void commandDock(entity ship, entity station)` — Initiates docking the given ship with the given target, if the ship is within docking range.
- `void commandFireTube(entity ship, integer tube_index, number missile_target_angle)` — Fires the missile loaded in the given tube at the given angle, in degrees.
- `void commandFireTubeAtTarget(entity ship, integer tube_index, entity target)` — Fires the missile loaded in the given tube, calculating the optimal intercept angle for the given target.
- `void commandImpulse(entity ship, number request)` — Sets the impulse engine throttle for the given ship.
- `void commandJump(entity ship, number distance)` — Initiates a jump drive jump of the given distance in world units (1000 = 1U).
- `void commandLaunchProbe(entity ship, number x, number y)` — Launches a scan probe from the given ship toward the given coordinates.
- `void commandLoadTube(entity ship, integer tube_index, string missile_type)` — Loads a missile of the given type into the given tube.
- `void commandMainScreenOverlay(entity ship, string overlay)` — Sets the overlay displayed on top of the main screen view for the given ship.
- `void commandMainScreenSetting(entity ship, string setting)` — Sets the main screen view mode for the given ship.
- `void commandMoveWaypoint(entity ship, integer index, number x, number y)` — Moves the waypoint at the given 0-based index (waypoint 1 = index 0) to the given coordinates for the given ship.
- `void commandOpenTextComm(entity ship, entity target)` — Opens text communications from the given ship to the given entity.
- `void commandRemoveWaypoint(entity ship, integer index)` — Removes the waypoint at the given 0-based index (waypoint 1 = index 0) for the given ship.
- `void commandScan(entity ship, entity target)` — Initiates a science scan of the given target by the given ship and resets the scanning delay timer to maximum.
- `void commandSendComm(entity ship, integer index)` — Selects a reply option by index in an active script-based communications dialogue for the given ship. If the ship has no active scripted comms, this does nothin
- `void commandSendCommPlayer(entity ship, string message)` — Sends a free-form text message in an active player-to-player communications dialogue for the given ship. If the ship has no active chat comms, this does nothing
- `void commandSetAlertLevel(entity ship, string level)` — Sets the alert level for the given ship. See EAlertLevel for valid values.
- `void commandSetAutoRepair(entity ship, boolean enabled)` — Enables or disables automatic repair crew assignment for the given ship.
- `void commandSetBeamFrequency(entity ship, integer frequency)` — Sets the beam weapon frequency for the given ship.
- `void commandSetBeamSystemTarget(entity ship, string system)` — Sets the enemy ship system that beam weapons will preferentially target for the given ship. See ESystem for valid system values.
- `void commandSetScienceLink(entity ship, entity probe)` — Links the science station of the given ship to the given scan probe for extended radar range.
- `void commandSetShieldFrequency(entity ship, integer frequency)` — Sets the shield frequency for the given ship and begins shield recalibration.
- `void commandSetShields(entity ship, boolean active)` — Activates or deactivates the shields on the given ship.
- `void commandSetSystemCoolantRequest(entity ship, string system, number coolant_level)` — Sets the requested coolant level for the given system on the given ship.
- `void commandSetSystemPowerRequest(entity ship, string system, number power_level)` — Sets the requested power level for the given system on the given ship.
- `void commandSetTarget(entity ship, entity target)` — Sets the combat target for the given ship.
- `void commandTargetRotation(entity ship, number rotation)` — Sets the target heading for the given ship's maneuvering thrusters, in degrees of rotation. (Rotation is heading + 90; 0 is east.)
- `void commandUndock(entity ship)` — Requests the given ship to undock from its current docking target.
- `void commandUnloadTube(entity ship, integer tube_index)` — Unloads the missile from the given tube.
- `void commandWarp(entity ship, integer request)` — Sets the warp drive level for the given ship.
- `void commsSwitchToGM()` — Switches a PlayerSpaceship communications dialogue from a comms script/function to interactive chat with the GM.
- `table createClass()` — Returns a class table onto which you can define methods. The table can be called as a function to instantiate a new object of that class.
- `entity createEntity()` — Creates an entity with no components.
- `table/value fromJSON(data)` — Returns a table/value converted from a json string
- `PVector<PlayerSpaceship> getActivePlayerShips()` — Returns a 1-indexed list of active PlayerSpaceships.
- `std::vector<sp::ecs::Entity> getAllObjects()` — Returns a list of all objects that have a position in the world.
- `integer getEEVersion()` — Returns the running EmptyEpsilon build version as an integer.
- `PVector<SpaceObject> getEnemiesInRadiusFor(sp::ecs::Entity entity, float radius)` — Returns a list of all entities within the given radius that are enemies of the given entity
- `table getEntitiesWithComponent(string component_name)` — Returns a table of entities that have the given component type.
- `PVector<SpaceObject> getGMSelection()` — Returns a list of SpaceObjects selected on the GM console.
- `string getGameLanguage()` — Returns the language as the string value of the language key in game preferences.
- `int getHackingDifficulty()` — Returns the running scenario's hacking difficulty setting.
- `EHackingGames getHackingGames()` — Returns the running scenario's hacking difficulty setting.
- `table getLuaEntityFunctionTable()` — Returns a table containing Lua entity functions.
- `PVector<SpaceObject> getObjectsInRadius(float x, float y, float radius)` — Returns a list of all SpaceObjects within the given radius of the given x/y coordinates.
- `P<PlayerSpaceship> getPlayerShip(int index)` — Returns the PlayerSpaceship with the given index.
- `table getPlayersInfo(entity source)` — Returns a table of connected player clients for source. Each entry has a "name" string and a
- `EScanningComplexity getScanningComplexity()` — Returns the running scenario's scanning complexity setting.
- `string getScenarioSetting(string key)` — Returns the given scenario setting's value, or an empty string if the setting is not found.
- `float getScenarioTime()` — Returns the elapsed time of the scenario, in seconds.
- `string getScenarioVariation()` — [DEPRECATED]
- `string getSectorName(float x, float y)` — Returns the name of the sector containing the given x/y coordinates.
- `void globalMessage(string message, std::optional<float> timeout)` — Displays a message on the main screens of all active player ships.
- `boolean hasPlayerCrewAtPosition(entity source, string station)` — Returns true if any connected player client is currently manning the given crew position on source.
- `bool isGamePaused()` — Returns true if the game is paused.
- `bool isInsideZone(x, y, zone_entity)` — Checks whether the given x/y coordinates are within the specified zone.
- `bool isLongRangeRadarAllowed()` — Returns whether the "Long Range Radar" setting for main screens is enabled in the running scenario.
- `bool isPerSystemDamageUsed()` — Returns whether the "Per-System Damage" setting is enabled in the running scenario.
- `boolean isRadarBlockedFrom(table source, entity target, number short_range)` — Returns true if target is hidden from radar at the source coordinates due to the effect of a radar-blocking entity, such as a nebula.
- `bool isStrategicMapAllowed()` — Returns whether the "Strategic Map" setting for main screens is enabled in the running scenario.
- `bool isTacticalRadarAllowed()` — Returns whether the "Tactical Radar" setting for main screens is enabled in the running scenario.
- `void log(...)` — Log values to EmptyEpsilon.log or STDOUT, depending on your configuration.
- `void onGMClick(ScriptSimpleCallback callback, string icon)` — Defines a function to call when the GM clicks on the background of their console.
- `void pauseGame()` — Pauses the game.
- `void playSoundFile(string filename)` — Plays the given audio file on the server.
- `void print(..)` — Print values to the Lua console. Also writes them to EmptyEpsilon.log or STDOUT, depending on your configuration.
- `void removeGMFunction(string name)` — Removes a function from the GM console.
- `void removePlayerShipCustomFunction(entity ship, string name)` — Removes the custom function with the given name from ship's crew screens. Has no effect if a function with the given name doesn't exist.
- `require(...)`
- `glm::vec2 sectorToXY(string sector_name)` — Returns the top-left ("northwest") x/y coordinates for the given sector mame.
- `void setBanner(string banner)` — Displays a scrolling banner containing the given text on the cinematic and top-down views.
- `void setCommsMessage(string message)` — Sets the content of an accepted hail, or in a comms reply.
- `void setDefaultSkybox(string skybox)` — Sets the default skybox image set to use in 3D viewports. Each image set is a directory in resources/skybox containing top.png, right.png, left.png, front.png, 
- `void setPlayerShipCustomFunction(entity ship, string type, string name, string caption, string|table positions, function callback, integer order)` — Adds or updates a custom function visible on crew screens for ship.
- `void setScenario(string script_name, std::optional<string> variation_name)` — Launches the given scenario, even if another scenario is running.
- `void shutdownGame()` — Shuts down the server.
- `void startThread(function callback)` — Starts a background thread and runs the given callback function in it.
- `string toJSON(data)` — Returns a json string with the input data converted to json.
- `void transferPlayersFromShipToShip(entity source, entity target [, string station])` — Moves all connected player clients from source to target entities.
- `void unpauseGame()` — Unpauses the game.
- `void victory(string faction_name)` — Sets the given faction as the scenario's victor and ends the scenario.
- `yield(...)`

## Object constructors

- `Artifact()`
- `Asteroid()`
- `BeamEffect()`
- `BlackHole()`
- `CpuShip()`
- `ElectricExplosionEffect()`
- `ExplosionEffect()`
- `FactionInfo()`
- `Mine()`
- `Nebula()`
- `Planet()`
- `PlayerSpaceship()`
- `ScanProbe()`
- `ScienceDatabase()`
- `SpaceStation()`
- `SupplyDrop()`
- `VisualAsteroid()`
- `WarpJammer()`
- `WormHole()`
- `Zone()`

## Entity methods (by file)


### artifact.lua

- `setModel(model_name)` — Sets the 3D model used for this entity, by its ModelData name.
- `explode()` — Immediately destroys this entity with a visual ExplosionEffect.
- `allowPickup(allow)` — Defines whether this entity can be picked up via collision.
- `onCollision(callback)` — Defines a function to call every tick when an entity is colliding with the entity.
- `onPlayerCollision(callback)` — Defines a function to call every tick when a player ship is colliding with the entity.
- `onPickUp(callback)` — Defines a function to call once when a player ship collides with the entity and allowPickup is enabled.
- `onPickup(callback)` — Alias of Entity:onPickUp().
- `setSpin(spin)` — Defines whether the entity rotates, and if so at what rotational velocity in degrees/second.
- `setRadarTraceIcon(icon)` — Sets the radar trace image for this entity.
- `setRadarTraceScale(scale)` — Scales the radar trace for this entity.
- `setRadarTraceColor(r, g, b)` — Sets the color of this entity's radar trace.

### beameffect.lua

- `setSource(source, x, y, z)` — Sets the BeamEffect's origin entity.
- `setTexture(texture)` — Sets the BeamEffect's texture.
- `setBeamFireSound()` — [NOT YET IMPLEMENTED]
- `setBeamFireSoundPower(level)` — [NOT YET IMPLEMENTED]
- `setDuration(duration)` — Sets the BeamEffect's duration, in seconds.
- `setRing(enabled)` — Defines whether the BeamEffect generates an impact ring on the target end.

### blackhole.lua

- `setTargetPosition(x, y)` — Sets the target teleportation coordinates for entities that pass through the center of this wormhole.
- `getTargetPosition()` — Returns the target teleportation coordinates for entities that pass through the center of this wormhole.
- `onTeleportation(callback)` — Defines a function to call when this WormHole teleports an entity.

### cpuship.lua

- `setAI(ai_name)` — Sets the default combat AI state for this ship.
- `orderIdle()` — Orders this AI-controlled ship to stay at its current position and do nothing.
- `orderRoaming()` — Orders this AI-controlled ship to roam and engage at will, without a specific target.
- `orderRoamingAt(x, y)`
- `orderRetreat(target)` — Orders this AI-controlled ship to move toward the given entity and dock, restock weapons, and repair its hull.
- `orderStandGround()` — Orders this AI-controlled ship to stay at its current position and attack nearby hostiles.
- `orderDefendLocation(x, y)` — Orders this AI-controlled ship to move to the given coordinates, patrol within a 1.5U radius, and attack any hostiles that move within 2U of
- `orderDefendTarget(target)` — Orders this AI-controlled ship to maintain a 2U escort distance from the given entity and attack nearby hostiles.
- `orderFlyFormation(target, offset_x, offset_y)` — Orders this AI-controlled ship to fly toward the given entity and follow it from the given offset distance.
- `orderFlyTowards(x, y)` — Orders this AI-controlled ship to move toward the given coordinates, and to attack hostiles that approach within its short-range radar range
- `orderFlyTowardsBlind(x, y)` — Orders this AI-controlled ship to move toward the given coordinates, ignoring all hostiles on the way.
- `orderAttack(target)` — Orders this AI-controlled ship to attack the given entity.
- `orderDock(target)` — Orders this AI-controlled ship to Fly Toward and dock with the given entity, if possible.
- `getOrder()` — Returns this AI-controlled ship's current orders.
- `getOrderTargetLocation()` — Returns the coordinates for this AI-controlled ship's orders.
- `getOrderTarget()` — Returns the target entity for this AI-controlled ship's orders.

### explosioneffect.lua

- `setOnRadar(is_on_radar)` — Defines whether to draw the ExplosionEffect on short-range radar.

### factioninfo.lua

- `setLocaleName(name)` — Sets this faction's name as presented in the user interface.
- `setGMColor(r, g, b)` — Sets the RGB color used for entities of this faction as seen on the GM and Spectator views.
- `setEnemy(other_faction)` — Sets the given faction to appear as hostile to entities of this faction.
- `setFriendly(other_faction)` — Sets the given faction to appear as friendly to entities of this faction.
- `setNeutral(other_faction)` — Sets the given faction to appear as neutral to entities of this faction.
- `__setFactionRelation(other_faction, relation)`

### multiuse.lua

- `setName(name)` — Sets this faction's internal string name, used to reference this faction regardless of EmptyEpsilon's language setting.
- `setDescription(description)` — For factions, sets this faction's longform description as shown in its ScienceDatabase child entry.
- `setSize(radius)` — Sets this entity's radius.
- `getSize()` — Returns this entity's radius.
- `setEnergy(amount)` — Sets this ship's energy level.
- `getTarget()` — Returns this ship's weapons target.
- `getOwner()` — Returns this ScanProbe's owner entity.
- `setTarget(a, b, c, d)` — Sets this ScanProbe's target coordinates.

### planet.lua

- `setPlanetAtmosphereColor(r, g, b)` — Sets this Planet's atmospheric effect color.
- `setPlanetAtmosphereTexture(texture)` — Sets this Planet's atmospheric effect texture.
- `setPlanetSurfaceTexture(texture)` — Sets this Planet's surface texture.
- `setPlanetCloudTexture(texture)` — Sets this Planet's cloud layer effect texture, which rotates independently of the planet.
- `getPlanetRadius()` — Returns this Planet's radius.
- `setPlanetRadius(size)` — Sets this Planet's radius, which also sets:
- `getCollisionSize()` — Returns this Planet's collision radius.
- `setPlanetCloudRadius(radius)` — Sets this Planet's cloud radius, overriding Planet:setPlanetRadius().
- `setDistanceFromMovementPlane(z)` — Sets the z-position of this Planet, the distance by which it's offset above (positive) or below (negative) the movement plane.
- `setAxialRotationTime(rotation_time)` — Sets this entity's axial rotation time, in seconds per full rotation.
- `setOrbit(target, time)` — Sets an entity around which this entity orbits, as well as its orbital period in seconds. Setting time to 0 will stop movement, while still 

### playerspaceship.lua

- `getWaypoint(index)` — Returns the coordinates of a waypoint with the given index that's been set by this player ship.
- `getWaypointID(index)` — Returns the numeric label for the given waypoint index.
- `getWaypointCount()` — Returns the total number of active waypoints owned by this player ship.
- `getAlertLevel()` — Returns this player ship's EAlertLevel.
- `setShieldsActive(active)` — Defines whether this ship's shields are raised (true) or lowered (false).
- `addToShipLog(message, color)` — Adds a message to this player ship's log.
- `transferPlayersToShip(other_ship)` — Moves all players connected to this ship to the same crew positions on another player ship.
- `transferPlayersAtPositionToShip(station, other_ship)` — Transfers only the crew members on a specific crew position to another player ship.
- `hasPlayerAtPosition(station)` — Returns whether a player occupies the given crew position on this ship.
- `isCommsInactive()` — Returns whether this ship's comms are not in use.
- `isCommsOpening()` — Returns whether this ship is opening comms with another entity.
- `isCommsBeingHailed()` — Returns whether this ship is being hailed by another entity.
- `isCommsBeingHailedByGM()` — Returns whether this ship is being hailed by the GM.
- `isCommsFailed()` — Returns whether comms to this ship have failed to open.
- `isCommsBroken()` — Returns whether comms to this ship were broken off by the other entity.
- `isCommsClosed()` — Returns whether comms between this ship and an entity were intentionally closed.
- `isCommsChatOpen()` — Returns whether this ship is engaged in text chat with either the GM or another player ship.
- `isCommsChatOpenToGM()` — Returns whether this player ship is engaged in text chat with the GM.
- `isCommsChatOpenToPlayer()` — Returns whether this player ship is engaged in text chat with another player ship.
- `isCommsScriptOpen()` — Returns whether this player ship is engaged in comms with a scripted entity.
- `setEnergyLevel(amount)` — Sets this ship's energy level.
- `setEnergyLevelMax(amount)` — Sets this ship's energy capacity.
- `getEnergyLevel()` — Returns this ship's energy level.
- `getEnergyLevelMax()` — Returns this ship's energy capacity.
- `getEnergyShieldUsePerSecond()` — Returns how much energy is consumed per second by this ship's shields while active.
- `setEnergyShieldUsePerSecond(amount)` — Sets how much energy is consumed per second by this ship's shields while active.
- `getEnergyWarpPerSecond()` — Returns how much energy is consumed per second by this ship's warp drive while in use.
- `setEnergyWarpPerSecond(amount)` — Sets how much energy is consumed per second by this player ship's warp drive while in use.
- `setMaxCoolant(amount)` — Sets the maximum amount of coolant available to engineering on this player ship.
- `getMaxCoolant()` — Returns the maximum amount of coolant available to engineering on this player ship.
- `setScanProbeCount(amount)` — Sets the number of scan probes stocked by this ship.
- `getScanProbeCount()` — Returns the number of scan probes stocked by this ship.
- `setMaxScanProbeCount(amount)` — Sets this ship's capacity for scan probes.
- `getMaxScanProbeCount()` — Returns this ship's capacity for scan probes.
- `addCustomButton(station, key, label, callback, order)` — Adds a custom interactive button with the given reference name to the given crew position screen.
- `addCustomInfo(station, key, label, order)` — Adds a custom non-interactive info label with the given reference name to the given crew position screen.
- `addCustomMessage(station, key, message)` — Displays a dismissable message with the given reference name on the given crew position screen.
- `addCustomMessageWithCallback(station, key, message, callback)` — As addCustomMessage(), but calls the given function when dismissed.
- `removeCustom(key)` — Removes the custom function, info, or message with the given reference name.
- `getBeamSystemTarget()` — Returns the index of the ESystem targeted by this player ship's weapons.
- `getBeamSystemTargetName()` — Returns the name of the ESystem targeted by this player ship's weapons.
- `commandTargetRotation(target)` — Commands this player ship to set a new target rotation.
- `commandImpulse(target)` — Commands this player ship to request a new impulse speed.
- `commandWarp(target)` — Commands this player ship to request a new warp level.
- `commandJump(target)` — Commands this player ship to request a jump of the given distance.
- `commandAbortJump()` — Commands this player ship to abort a jump in progress.
- `commandSetTarget(target)` — Commands this player ship to set its weapons target to the given entity.
- `commandLoadTube(index, missile_type)` — Commands this player ship to load the WeaponTube with the given index with the given weapon type.
- `commandUnloadTube(index)` — Commands this player ship to unload the WeaponTube with the given index.
- `commandFireTube(index)` — Commands this player ship to fire the WeaponTube with the given index.
- `commandFireTubeAtTarget(index, target)` — Commands this player ship to fire the given weapons tube with the given entity as its target.
- `commandSetShields(enabled)` — Commands this player ship to raise (true) or lower (false) its shields.
- `commandMainScreenSetting(setting)` — Commands this player ship to change its Main Screen view to the given setting.
- `commandMainScreenOverlay(setting)` — Commands this player ship to change its Main Screen comms overlay to the given setting.
- `commandScan(target)` — Commands this player ship to initiate a scan of the given entity.
- `commandSetSystemPowerRequest(system, request)` — Commands this player ship to set the power level of the given system.
- `commandSetSystemCoolantRequest(system, request)` — Commands this player ship to set the coolant level of the given system.
- `commandDock(target)` — Commands this player ship to initiate docking with the given entity.
- `commandUndock()` — Commands this player ship to undock from any entity it's docked with.
- `commandAbortDock()` — Commands this player ship to abort an in-progress docking operation.
- `commandOpenTextComm(target)` — Commands this player ship to hail the given entity.
- `commandCloseTextComm()` — Commands this player ship to close comms.
- `commandAnswerCommHail(response)` — Commands whether this player ship answers (true) or rejects (false) an incoming hail.
- `commandSendComm(index)` — Commands this player ship to select the reply with the given index during a comms dialogue.
- `commandSendCommPlayer(message)` — Commands this player ship to send the given message to the active text comms chat.
- `commandSetAutoRepair(enabled)` — Commands whether repair crews on this player ship automatically move to rooms of damaged systems.
- `commandSetBeamFrequency(index)` — Commands this player ship to set its beam frequency to the given value.
- `commandSetBeamSystemTarget(target)` — Commands this player ship to target the given ship system with its beam weapons.
- `commandSetShieldFrequency(index)` — Commands this player ship to calibrate its shield frequency to the given index.
- `commandAddWaypoint(x, y)` — Commands this player ship to add a waypoint at the given coordinates.
- `commandRemoveWaypoint(index)` — Commands this player ship to remove the waypoint with the given index.
- `commandMoveWaypoint(index, x, y)` — Commands this player ship to move the waypoint with the given index to the given coordinates.
- `commandActivateSelfDestruct()` — Commands this player ship to activate its self-destruct sequence.
- `commandCancelSelfDestruct()` — Commands this player ship to cancel its self-destruct sequence.
- `commandConfirmDestructCode(index, code)` — Commands this player ship to submit the given self-destruct authorization code for the code request with the given index.
- `commandCombatManeuverBoost(amount)` — Commands this player ship to set its forward combat maneuver to the given value.
- `commandLaunchProbe(x, y)` — Commands this player ship to launch a ScanProbe to the given coordinates.
- `commandSetScienceLink(target)` — Commands this player ship to link the science screen to the given ScanProbe.
- `commandClearScienceLink()` — Commands this player ship to unlink the science screen from any ScanProbe.
- `commandSetAlertLevel(level)` — Commands this player ship to set the given alert level.
- `getRepairCrew()` — Returns a 1-indexed table of internal_crew entities that are assigned to this entity.
- `getRepairCrewCount()` — Returns the number of repair crews on this entity.
- `setRepairCrewCount(amount)` — Sets the total number of repair crews on this entity.
- `isValidCrewPosition(pos)` — Returns true if the given table of {x,y} coordinates is within one of this entity's internal rooms. or false otherwise.
- `getInternalRoomForSystem(system)` — Returns the internal room that contains a given ship system.
- `getCoordinatesForInternalRoom(room)` — Returns a table containing tables of all valid {x,y} coordinates for a given internal room.
- `moveRepairCrewToPosition(crew_index, pos)` — Sets the target coordinates of a repair crew within this entity's internal rooms.
- `moveRepairCrewToRoom(crew_index, room)` — Sets the target room of a repair crew within this entity's internal rooms, selected by passing a room.
- `setAutoCoolant(enabled)` — Defines whether automatic coolant distribution is enabled on this entity.
- `setControlCode(code)` — Sets a control code password required for a player to join this player ship.
- `onProbeLaunch(callback)` — Defines a function to call when this player ship launches a probe.
- `onProbeLink(callback)` — Defines a function to call when this player ship links a probe to the science screen.
- `onProbeUnlink(callback)` — Defines a function to call when this player ship unlinks a probe from the science screen.
- `getLongRangeRadarRange()` — Returns this ships's long-range radar range.
- `getShortRangeRadarRange()` — Returns this player ship's short-range radar range.
- `setLongRangeRadarRange(range)` — Sets this player ship's long-range radar range.
- `setShortRangeRadarRange(range)` — Sets this player ship's short-range radar range.
- `setCanScan(enabled)` — Defines whether scanning features appear on related crew screens in this player ship.
- `getCanScan()` — Returns whether scanning features appear on related crew screens in this player ship.
- `setCanHack(enabled)` — Defines whether hacking features appear on related crew screens in this player ship.
- `getCanHack()` — Returns whether hacking features appear on related crew screens in this player ship.
- `setCanDock(enabled)` — Defines whether the "Request Docking" button appears on related crew screens in this player ship.
- `getCanDock()` — Returns whether the "Request Docking" button appears on related crew screens in this player ship.
- `setCanCombatManeuver(enabled)` — Defines whether combat maneuver controls appear on related crew screens in this player ship.
- `getCanCombatManeuver()` — Returns whether combat maneuver controls appear on related crew screens in this player ship.
- `setCanLaunchProbe(enabled)` — Defines whether ScanProbe-launching controls appear on related crew screens in this player ship.
- `getCanLaunchProbe()` — Returns whether ScanProbe-launching controls appear on related crew screens in this player ship.
- `setCanSelfDestruct(enabled)` — Defines whether self-destruct controls appear on related crew screens in this player ship.
- `getCanSelfDestruct()` — Returns whether self-destruct controls appear on related crew screens in this player ship.
- `setSelfDestructDamage(amount)` — Sets the amount of damage done to nearby entities when this player ship self-destructs.
- `getSelfDestructDamage()` — Returns the amount of base damage done to nearby entities when this player ship self-destructs.
- `setSelfDestructSize(size)` — Sets the radius of the explosion created when this player ship self-destructs.
- `getSelfDestructSize()` — Returns the radius of the explosion created when this player ship self-destructs.

### scanprobe.lua

- `setSpeed(speed)` — Sets this ScanProbe's speed.
- `getSpeed()` — Returns this ScanProbe's speed.
- `setLifetime(lifetime)` — Sets this ScanProbe's remaining lifetime, in seconds.
- `getLifetime()` — Returns this ScanProbe's remaining lifetime.
- `setOwner(owner)` — Sets this ScanProbe's owner entity.
- `onArrival(callback)` — Defines a function to call when this ScanProbe arrives to its target coordinates.
- `onExpiration(callback)` — Defines a function to call when this ScanProbe's lifetime expires.

### sciencedatabase.lua

- `getName()` — Returns this ScienceDatabase entry's displayed name.
- `getId()` — Returns this ScienceDatabase entry's unique entity.
- `getParentId()` — Return this ScienceDatabase entry's parent entry's entity.
- `addEntry(name)` — Creates a ScienceDatabase entry with the given name as a child of this ScienceDatabase entry.
- `getEntryByName(name)` — Returns the first child ScienceDatabase entry of this ScienceDatabase entry found with the given name.
- `getEntries()` — Returns a 1-indexed table of all child entries in this ScienceDatabase entry, in arbitrary order.
- `hasEntries()` — Returns true if this ScienceDatabase entry has child entries.
- `addKeyValue(key, value)` — Adds a key/value pair to this ScienceDatabase entry's key/value data.
- `setKeyValue(key, value)` — Sets the value of the first key/value pair matching the given key in this ScienceDatabase entry's key/value data.
- `getKeyValue(key)` — Returns the value of the first matching key found in this ScienceDatabase entry's key/value data. Key matching is case-sensitive.
- `getKeyValues()` — Returns a table containing all key/value pairs in this ScienceDatabase entry.
- `removeKey(key)` — Removes all key/value pairs matching the given key in this ScienceDatabase entry's key/value data. Key matching is case-sensitive.
- `setLongDescription(description)` — Sets this ScienceDatabase entry's longform description to the given string.
- `getLongDescription()` — Returns this ScienceDatabase entry's longform description.
- `setImage(image)` — Sets this ScienceDatabase entry's image file to the given filename.
- `getImage()` — Returns this ScienceDatabase entry's image filename.
- `setModelDataName(model_data_name)` — Sets the 3D appearance, by ModelData name, used for this ScienceDatabase entry.

### shiptemplatebasedobject.lua

- `setTemplate(template_name)` — Sets this ShipTemplate that defines this entity's traits, and then applies them to this entity.
- `setShipTemplate(template_name)` — [DEPRECATED]
- `setTypeName(type_name)` — Sets this entity's vessel classification name, such as "Starfighter" or "Cruiser".
- `getTypeName()` — Returns this entity's vessel classification name.
- `getHull()` — Returns this entity's hull points.
- `getHullMax()` — Returns this entity's maximum limit of hull points.
- `setHull(amount)` — Sets this entity's hull points.
- `setHullMax(amount)` — Sets this entity's maximum limit of hull points.
- `setCanBeDestroyed(allow_destroy)` — Defines whether this entity can be destroyed by damage.
- `getCanBeDestroyed()` — Returns whether the entity can be destroyed by damage.
- `getShieldLevel(index)` — Returns the shield points for this entity's shield segment with the given index.
- `getShieldCount()` — Returns this entity's number of shield segments.
- `getShieldMax(index)` — Returns the maximum shield points for the entity's shield segment with the given index.
- `setShields(...)` — Sets this entity's shield points.
- `setShieldsMax(...)` — Sets this entity's maximum shield points per segment, and can also create new segments.
- `setRadarTrace(filename)` — Sets the radar trace image for this entity.
- `setImpulseSoundFile(filename)` — Sets this entity's impulse engine sound effect.
- `getShieldsActive()` — Returns whether this entity's shields are activated.
- `getSharesEnergyWithDocked()` — Returns whether this entity supplies energy to docked player ships.
- `setSharesEnergyWithDocked(allow_energy_share)` — Defines whether this entity supplies energy to docked player ships.
- `getRepairDocked()` — Returns whether this entity repairs docked ships.
- `setRepairDocked(allow_repair)` — Defines whether this entity repairs docked ships.
- `getRestocksScanProbes()` — Returns whether the entity restocks scan probes for docked player ships.
- `setRestocksScanProbes(allow_restock)` — Defines whether the entity restocks scan probes for docked player ships.
- `getRestocksMissilesDocked()` — Returns whether this entity restocks missiles for docked CPU ships.
- `setRestocksMissilesDocked(allow_restock)` — Defines whether this entity restocks missiles for docked CPU ships.
- `getFrontShield()` — [DEPRECATED]
- `getFrontShieldMax()` — [DEPRECATED]
- `setFrontShield(amount)` — [DEPRECATED]
- `setFrontShieldMax(amount)` — [DEPRECATED]
- `getRearShield()` — [DEPRECATED]
- `getRearShieldMax()` — [DEPRECATED]
- `setRearShield(amount)` — [DEPRECATED]
- `setRearShieldMax(amount)` — [DEPRECATED]
- `onTakingDamage(callback)` — Defines a function to call when this entity takes damage.
- `onTakingShieldDamage(callback)` — Defines a function to call when this entity takes damage to its shields.
- `onDestruction(callback)` — Defines a function to call when this entity is destroyed by taking damage.

### spaceobject.lua

- `setPosition(x, y)` — Sets this entity's position on the map, in game units from the origin.
- `getPosition()` — Returns this entity's position on the map, as X/Y coordinates in game units from the origin.
- `setRotation(rotation)` — Sets this entity's absolute rotation, in degrees.
- `getRotation()` — Returns this entity's absolute rotation, in degrees.
- `setHeading(heading)` — Sets this entity's heading, in degrees ranging from 0 to 360.
- `getHeading()` — Returns this entity's heading, in degrees ranging from 0 to 360.
- `getVelocity()` — Returns this entity's directional velocity within 2D space as an x/y vector.
- `getAngularVelocity()` — Returns this entity's rotational velocity within 2D space, in degrees per second.
- `setFaction(faction_name)` — Sets the faction to which this entity belongs, by faction name.
- `getFaction()` — Returns the name of the faction to which this entity belongs.
- `getLocaleFaction()` — Returns the localized name of the faction to which this entity belongs.
- `setFactionId(faction_id)` — Sets the faction to which this entity belongs, by a faction entity reference.
- `getFactionId()` — Returns the faction list index for the faction to which this entity belongs.
- `isEnemy(target)` — Returns the friend-or-foe status of the given faction relative to this entity's faction.
- `isFriendly(target)` — Returns the friend-or-foe status of the given faction relative to this entity's faction.
- `setCommsScript(script_name)` — Sets the communications script used when this entity is hailed.
- `setCommsFunction(callback)` — Defines a function to call when this entity is hailed, in lieu of any current or default comms script.
- `setCallSign(callsign)` — Sets this entity's callsign.
- `sendCommsMessage(target, message)` — Hails a player ship from this entity.
- `sendCommsMessageNoLog(target, message)` — As sendCommsMessage(), but does not log a failed hail to the target ship's comms log.
- `openCommsTo(target)` — As sendCommsMessage(), but sends an empty string as the message.
- `getCallSign()` — Returns this entity's callsign.
- `areEnemiesInRange(range)` — Returns whether any entity from a hostile faction are within a given radius of this entity, in (unit?).
- `getObjectsInRange(range)` — Returns any entity within a specific radius, in (unit?), of this entity.
- `getReputationPoints()` — Returns this entity's faction reputation points.
- `setReputationPoints(amount)` — Sets this entity's faction reputation points to the given amount.
- `takeReputationPoints(amount)` — Deducts a given number of faction reputation points from this entity.
- `addReputationPoints(amount)` — Adds a given number of faction reputation points to this entity.
- `getSectorName()` — Returns the name of the map sector, such as "A4", where this entity is located.
- `takeDamage(amount, type, originx, originy)` — Deals a specific amount of a specific type of damage to this entity.
- `setDescriptions(unscanned_description, scanned_description)` — Sets this entity's description in unscanned and scanned states.
- `setDescriptionForScanState(state, description)` — Sets a description for a given EScannedState on this entity.
- `getDescription(state)` — Returns this entity's description for the given EScannedState.
- `setRadarSignatureInfo(gravity, electrical, biological)` — Sets this entity's radar signature, which creates noise on the science screen's raw radar signal ring.
- `getRadarSignatureGravity()` — Returns this entity's gravitational radar signature value.
- `getRadarSignatureElectrical()` — Returns this entity's electrical radar signature value.
- `getRadarSignatureBiological()` — Returns this entity's biological radar signature value.
- `setScanningParameters(complexity, depth)` — Sets this entity's scanning complexity (number of bars in the scanning minigame) and depth (number of scanning minigames to complete until f
- `scanningComplexity()` — Returns the scanning complexity for this entity.
- `scanningChannelDepth()` — Returns the maximum scanning depth for this entity.
- `setScanned(is_scanned)` — Defines whether all factions consider this entity as having been scanned.
- `isScanned()` — [DEPRECATED]
- `isScannedBy(other)` — Returns whether the given entity has successfully scanned this entity.
- `setScannedByFaction(faction_name, is_scanned)` — Defines whether a given faction considers this entity as having been scanned.
- `isScannedByFaction(faction_name)` — Returns whether the given faction has successfully scanned this entity.
- `onDestroyed(callback)` — Defines a function to call when this entity is destroyed by any means.
- `onScanInitiated(callback)` — Defines a function to call when a scan is initiated against this entity.
- `onScanCompleted(callback)` — Defines a function to call when a scan is completed against this entity.
- `onScanCancelled(callback)` — Defines a function to call when a scan is cancelled against this entity.

### spaceship.lua

- `isFriendOrFoeIdentified()` — [DEPRECATED]
- `isFullyScanned()` — [DEPRECATED]
- `isFriendOrFoeIdentifiedBy(enemy)` — Returns whether this ship has been identified by the given entity as either hostile or friendly.
- `isFullyScannedBy(enemy)` — Returns whether this ship has been fully scanned by the given entity.
- `isFriendOrFoeIdentifiedByFaction(faction)` — Returns whether this ship has been identified by the given faction as either hostile or friendly.
- `isFullyScannedByFaction(faction)` — Returns whether this ship has been fully scanned by the given faction.
- `isDocked(target)` — Returns whether this ship is docked with the given entity.
- `getDockedWith()` — Returns the entity with which this ship is docked.
- `getDockingState()` — Returns the EDockingState value of this ship.
- `getWeaponStorage(weapon_type)` — Returns the number of the given weapon type stocked by this ship.
- `getWeaponStorageMax(weapon_type)` — Returns this ship's capacity for the given weapon type.
- `setWeaponStorage(weapon_type, amount)` — Sets the number of the given weapon type stocked by this entity.
- `setWeaponStorageMax(weapon_type, amount)` — Sets this entity's capacity for the given weapon type.
- `getShieldsFrequency()` — Returns this ship's shield frequency index.
- `setShieldsFrequency(frequency)` — Sets this ship's shield frequency index.
- `getBeamFrequency()` — Returns this ship's beam weapon frequency.
- `getMaxEnergy()` — Returns this ship's energy capacity.
- `setMaxEnergy(amount)` — Sets this ship's energy capacity.
- `getEnergy()` — Returns this ship's energy level.
- `hasSystem(system_name)` — Returns whether this ship has the given system.
- `getSystemHackedLevel(system_name)` — Returns the hacked level for the given system on this ship.
- `setSystemHackedLevel(system_name, level)` — Sets the hacked level for the given system on this ship.
- `getSystemHealth(system_name)` — Returns the given system's health on this ship.
- `setSystemHealth(system_name, amount)` — Sets the given system's health on this ship.
- `getSystemHealthMax(system_name)` — Returns the given system's maximum health on this ship.
- `setSystemHealthMax(system_name, amount)` — Sets the given system's maximum health on this ship.
- `getSystemHeat(system_name)` — Returns the given system's heat level on this ship.
- `setSystemHeat(system_name, amount)` — Sets the given system's heat level on this ship.
- `getSystemHeatRate(system_name)` — Returns the given system's rate of heating or cooling, in percent (0.01 = 1%) per second?, on this ship.
- `setSystemHeatRate(system_name, amount)` — Sets the given system's rate of heating or cooling, in percent (0.01 = 1%) per second?, on this ship.
- `getSystemPower(system_name)` — Returns the given system's power level on this ship.
- `setSystemPower(system_name, amount)` — Sets the given system's power level.
- `getSystemPowerRate(system_name)` — Returns the given system's rate of consuming power, in points per second?, in this ship.
- `setSystemPowerRate(system_name, amount)` — Sets the given system's rate of consuming power, in points per second?, in this ship.
- `getSystemPowerFactor(system_name)` — Returns the relative power drain factor for the given system.
- `setSystemPowerFactor(system_name, amount)` — Sets the relative power drain factor? for the given system in this ship.
- `getSystemCoolant(system_name)` — Returns the coolant distribution for the given system in this ship.
- `setSystemCoolant(system_name, amount)` — Sets the coolant quantity for the given system in this ship.
- `getSystemCoolantRate(system_name)` — Returns the rate at which the given system in this ship takes coolant, in points per second?
- `setSystemCoolantRate(system_name, amount)` — Sets the rate at which the given system in this ship takes coolant, in points per second?
- `getImpulseMaxSpeed()` — Returns this ship's forward and reverse impulse speed limits.
- `setImpulseMaxSpeed(forward, reverse)` — Sets this ship's maximum forward and reverse impulse speeds.
- `getRotationMaxSpeed()` — Returns this ship's maximum rotational speed, in degrees per second?
- `setRotationMaxSpeed(speed)` — Sets this ship's maximum rotational speed, in degrees per second?
- `getAcceleration()` — Returns the ship's forward impulse acceleration value, in (unit?)
- `setAcceleration(forward, reverse)` — Sets the ship's forward and reverse impulse acceleration values, in (unit?)
- `setCombatManeuver(boost, strafe)` — Sets the ship's combat maneuvering capacities.
- `hasJumpDrive()` — Returns whether the ship has a jump drive.
- `setJumpDrive(enabled)` — Defines whether the ship has a jump drive.
- `setJumpDriveRange(min_range, max_range)` — Sets the minimum and maximum jump distances for this ship.
- `setJumpDriveCharge(charge)` — Sets this ship's current jump drive charge.
- `getJumpDriveCharge()` — Returns this ship's current jump drive charge.
- `getJumpDelay()` — Returns the time required by this ship to complete a jump once initiated.
- `hasWarpDrive()` — Returns whether this ship has a warp drive.
- `setWarpDrive(enabled)` — Defines whether this ship has a warp drive.
- `setWarpSpeed(speed)` — Sets this ship's warp speed factor.
- `getWarpSpeed()` — Returns this ship's warp speed factor.
- `getBeamWeaponArc(index)` — Returns the arc, in degrees, for the BeamWeapon with the given index on this ship.
- `getBeamWeaponDirection(index)` — Returns the direction, in degrees relative to the ship's forward bearing, for the arc's center of the BeamWeapon with the given index on thi
- `getBeamWeaponRange(index)` — Returns the range for the BeamWeapon with the given index on this ship.
- `getBeamWeaponTurretArc(index)` — Returns the turret arc, in degrees, for the BeamWeapon with the given index on this ship.
- `getBeamWeaponTurretDirection(index)` — Returns the direction, in degrees relative to the ship's forward bearing, for the turret arc's center for the BeamWeapon with the given inde
- `getBeamWeaponTurretRotationRate(index)` — Returns the turret's rotation rate, in degrees per tick, for the BeamWeapon with the given index on this ship.
- `getBeamWeaponCycleTime(index)` — Returns the base firing delay, in seconds, for the BeamWeapon with the given index on this ship.
- `getBeamWeaponDamage(index)` — Returns the base damage dealt by the BeamWeapon with the given index on this ship.
- `getBeamWeaponEnergyPerFire(index)` — Returns how much of this ship's energy is drained each time the BeamWeapon with the given index is fired.
- `getBeamWeaponHeatPerFire(index)` — Returns the heat generated by each firing of the BeamWeapon with the given index on this ship.
- `setBeamWeapon(index, arc, direction, range, cycle_time, damage)` — Defines the traits of a BeamWeapon with the given index on this ship.
- `setBeamWeaponTurret(index, arc, direction, rotation_rate)` — Converts a BeamWeapon with the given index on this ship into a turret and defines its traits.
- `setBeamWeaponTexture(index, texture)` — Sets the BeamEffect texture, by filename, for the BeamWeapon with the given index on this ship.
- `setBeamWeaponEnergyPerFire(index, energy)` — Sets how much energy is drained each time the BeamWeapon with the given index is fired on this ship.
- `setBeamWeaponHeatPerFire(index, heat)` — Sets how much "beamweapon" system heat is generated, in percentage of total system heat capacity, each time the BeamWeapon with the given in
- `setBeamWeaponArcColor(index, idle_r, idle_g, idle_b, fire_r, fire_g, fire_b)` — Sets the colors used to draw the radar arc for the BeamWeapon with the given index on this ship.
- `setBeamWeaponDamageType(index, damage_type)` — Sets the damage type dealt by the BeamWeapon with the given index on this ship.
- `setWeaponTubeCount(amount)` — Sets the number of WeaponTubes for this ship.
- `getWeaponTubeCount()` — Returns the number of WeaponTube on this ship.
- `getWeaponTubeLoadType(index)` — Returns the weapon type loaded into the WeaponTube with the given index on this ship.
- `weaponTubeAllowMissle(index, weapon_type)` — Sets which weapon types the WeaponTube with the given index on this ship can load.
- `weaponTubeDisallowMissle(index, weapon_type)` — Sets which weapon types the WeaponTube with the given index can't load on this ship.
- `setWeaponTubeExclusiveFor(index, weapon_type)` — Sets a weapon tube with the given index on this ship to allow loading only the given weapon type.
- `setWeaponTubeDirection(index, direction)` — Sets the angle, relative to this ship's forward bearing, toward which the WeaponTube with the given index on this ship points.
- `setTubeSize(index, size)` — Sets the weapon size launched from the WeaponTube with the given index on this ship.
- `getTubeSize(index)` — Returns the size of the weapon tube with the given index on this ship.
- `getTubeLoadTime(index)` — Returns the delay, in seconds, for loading and unloading the WeaponTube with the given index on this ship.
- `setTubeLoadTime(index, load_time)` — Sets the time, in seconds, required to load the weapon tube with the given index on this ship.
- `getDynamicRadarSignatureGravity()` — Returns the dynamic gravitational radar signature value emitted by this ship.
- `getDynamicRadarSignatureElectrical()` — Returns the dynamic electrical radar signature value emitted by this ship.
- `getDynamicRadarSignatureBiological()` — Returns the dynamic biological radar signature value emitted by this ship.
- `addBroadcast(target, message)` — Broadcasts a message from this ship to the comms of all other ships matching the threshold.
- `setScanState(state)` — Sets the scan state of this ship for every faction.
- `setScanStateByFaction(faction, state)` — Sets the scan state of this ship for a given faction.

### warpjammer.lua

- `getRange()` — Returns this WarpJammer's jamming range, represented on radar as a circle with jammer in the middle.
- `setRange(range)` — Sets this WarpJammer's jamming radius.

### zone.lua

- `setPoints(...)` — Sets the corners of this Zone n-gon to x_1, y_1, x_2, y_2, ... x_n, y_n.
- `setColor(r, g, b)` — Sets this Zone's color when drawn on radar.
- `setLabel(label)` — Sets this Zone's text label, rendered at the zone's center point.
- `getLabel()` — Returns this Zone's text label.
- `setLocalSkybox(skybox, transition)` — Sets this Zone's local skybox. Optionally also sets this zone's skybox fade transition distance, which defaults to 0.
- `isInside(obj)` — Returns whether the given entity is inside this Zone.
