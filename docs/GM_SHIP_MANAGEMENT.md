# GM Ship Management

How the GM looks at and changes what each player ship owns: credits, standing, and upgrades.
Everything here is on the EmptyEpsilon GM screen while the sandbox campaign ("The Drift") runs.

## One record per ship

Every player ship has its own record: **credits**, **standing** with each faction, and
**upgrades**. Nothing is shared between ships.

- The **primary ship** (the first one, normally the *Magpie*) is the ship the story arcs follow.
  Its record is the top level of the campaign save.
- **Every other ship** (joined from the "Create player ship" screen, or spawned by a scenario)
  has a record saved under its callsign. A crew that rejoins next session under the same ship
  name gets its credits, standing and upgrades back; a name never seen before starts at zero
  with a stock ship.
- A ship that buys an upgrade pays for it and is the only ship that gets it. Each ship's job
  tier (which contract types it is offered) follows its own upgrade spend: under 500 cr tier 0,
  500–999 cr tier 1, 1000 cr and up tier 2.
- Renaming a ship in mid-session does not lose its record; it is saved under the new name.

## Looking

### Campaign Status
The primary ship's credits, upgrades (each with its price, the total invested, the job tier
and the next tier's threshold) and standing with every faction. Below that, one line for every
other player ship in the game: credits, upgrade spend and tier, Concord and Independent
standing. Then the campaign's statistics, story arcs and achievements.

### Ship Upgrades... → *ship* → Ship Status
A status sheet for the ship you picked: every upgrade by group (owned ■, available □, locked ×
with what it needs), and the ship's live numbers (hull, shields, beams, tubes and missiles,
impulse, warp, energy, repair crew, sensor range, probe speed).

## Changing

### Credits: Jobs... → Credits +50 / −50
Adds or removes 50 credits. With one ship in play the buttons read **Credits +50 / −50**; with
several there is a pair per ship, named after it (**Kestrel Credits +50**). A balance never goes below zero. The ship's
log shows the change and its Relay and Operations screens show the new `Credits: N` line.

### Standing: Reputation...
A ship's standing with each faction. With several ships the menu first lists them: pick one, and
everything after applies to **that ship only** (with one ship the list is skipped). **Rep Status** explains what each level means
(how Concord inspections go, how often Corsairs patrol, how many jobs that faction's stations
offer). Pick a faction to adjust it by +50 or −50. Raising Concord standing does not call off a patrol
that is already hostile: switch **World Plugins... → Proximity Spawns** off and on again to
remove every patrol.

### Upgrades: Ship Upgrades... → *ship*
The menu lists every player ship in the game. Pick one; everything on the next screen applies to
**that ship only**.

- A button per upgrade, labelled with its state: ■ owned, □ not owned, × locked (its
  prerequisite is missing).
- Press □ to **grant** the upgrade free of charge. It is added to the ship's record and applied
  at once; the ship's log says "Upgrade installed".
- Press ■ to **revoke** it. The ship is rebuilt from its template and its remaining upgrades are
  re-applied, because an upgrade's effect cannot be undone piece by piece. The ship keeps its
  position, heading, name and faction; its hull, shields, energy and missiles are reset to the
  template's (plus what the remaining upgrades add).
- Repair-crew upgrades are special: pressing one the ship already owns re-applies it (to restore
  crew that died), up to 8 crew.

To let a crew re-spend its money, revoke the upgrades and give the credits back with
that ship's Credits +50 — there is no automatic refund.

## Saving and restoring

- The campaign **autosaves** every minute and on every credit, standing, flag and job event.
  There is no manual save button.
- **Backup campaign**: copies the whole campaign (every ship's record, flags, statistics) into
  one of six numbered slots. A slot's label shows play time and the primary ship's credits.
  Pressing a used slot saves over it.
- **Restore campaign**: pick a slot and confirm. The slot replaces the live save, and saving is
  paused until you restart the scenario and choose **Continue** (otherwise the running game
  would write its own state over the restored one). The save you replaced is kept under
  `<campaign key>.before_restore`.

Use a backup before experimenting with upgrades or standing: restoring it is the only undo.

## What is saved, and where

In the server's `scriptstorage.json`, key `ragtag.campaign.sandbox`:

| Field | What |
|---|---|
| `ship_name`, `credits`, `reputation`, `upgrades` | The primary ship's record |
| `extra_ships` | One record per other ship: `name`, `credits`, `reputation`, `upgrades` |
| `flags` | Story flags (arc progress, stations visited) |
| `stats`, `achievements`, `sessions`, `notes`, `discovered` | Campaign-wide history |

Upgrades are stored as a list of ids in purchase order and re-applied to a fresh ship at the
start of every session, so hull damage, missiles spent and crew lost do **not** carry over, but
the upgrades do.

## Troubleshooting

**A second ship has no credits or upgrades this session.** Its record is found by callsign. If
the ship was given a different name this time, it has a new, empty record. The old one is still
in the save under the old name; rename the ship back (or copy the values over with the buttons
above).

**A second ship bought an upgrade and the first ship does not have it.** Correct: upgrades
belong to the ship that bought them.

**The stock "Reputation" number on the consoles reads 0.** Expected. EmptyEpsilon keeps that
number per faction, so every Independent ship would share it; the campaign keeps credits itself
and shows them as the `Credits: N` line on Relay and Operations.

**A crew's credits halved.** Their ship was destroyed: losing a ship costs that ship's crew half
their credits (upgrades and standing are kept). The rebuilt ship's log says what it cost. To
forgive it, give the credits back with **Jobs... → Credits +50**. The amount is `RT.DEATH_PENALTY`
in `core.lua` (0.5). A player ship the GM deletes counts as lost too.

**Credits or upgrades reset to the defaults.** The scenario was started with **Fresh start**,
which wipes the campaign. Restore a backup slot.
