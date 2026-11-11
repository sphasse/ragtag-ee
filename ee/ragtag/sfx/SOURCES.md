# Sound cues

Cue files for `RT.sound(id)` (see `ee/ragtag/core.lua`, table `RT.SOUNDS`).
This folder installs to `scripts/ragtag/sfx/`, which EmptyEpsilon resolves as a
resource root, so a file here is referenced as `"ragtag/sfx/<name>.ogg"`.

## How cues play

- **Server only (default).** `playSoundFile` plays on the server machine's
  speakers and nowhere else. No volume, pitch, stop or loop: keep files short
  (2–8 s), master them to one consistent loudness, and let the queue in
  `RT.updateSounds` pace them. Beds are re-fired by `RT.soundLoop`.
- **Client positional (opt-in).** With `RT.sound_client_enabled = true` a cue
  given `{x, y}` also spawns an `sfx` entity that every client plays — but only
  screens with a 3D view (the main screen) hear positional sound. Clients then
  need the file too: put it under `~/.emptyepsilon/resources/ragtag/sfx/` on
  each client, or run the main screen on the server machine.
- Formats: `.ogg` preferred (`.wav`, `.flac` also work). Positional files must
  be mono; server-only cues may be stereo.

## Cue ids and what they mark

| id | Moment | Length target | Current file |
|---|---|---|---|
| `concord_hail` | Patrol stop: the ship is halted and the hail opens | 3–4 s comms chirp + low drone | stock `sfx/shield_up.wav` (placeholder) |
| `concord_warning` | 10 s left on the compliance clock | ≤1 s alert tone | stock `audio/scenario/58/sa_58_goBeep.ogg` (placeholder) |
| `concord_hostile` | Patrol goes hostile (refused, timed out, bad standing) | 1–3 s klaxon / "warrant issued" | stock `audio/scenario/34/sa_34_HostileShips.ogg` (placeholder) |
| `jammer_engage` | Warp jammer deploys (Concord stop, Boneyard) | 2–4 s power surge / crackle | stock `sfx/emp_explosion.wav` (placeholder) |
| `jammer_bed` | Re-fired every 10 s while jammed | 8–10 s interference hum | stock `sfx/engine_fighter.wav` (placeholder, CC-BY-NC) |
| `jammer_release` | Jammer clears / crew is free to go | 2–3 s release tone | stock `sfx/laser.wav` (placeholder) |

To replace a placeholder: drop the file in this folder, change `file` in
`RT.SOUNDS` to `"ragtag/sfx/<name>.ogg"`, and set `seconds` to the clip length
(`afinfo <file>` on macOS, `soxi -D` elsewhere). Add it to the table below.

## Licences

Prefer CC0 (freesound.org, opengameart.org). CC-BY is fine with attribution
here. Avoid NC licences for anything we might publish.

| File | Source | Licence | Author |
|---|---|---|---|
| (none yet) | | | |

Stock EmptyEpsilon files used as placeholders are credited in the engine's
`resources/sfx/source.txt`; the `audio/scenario/*` voice clips ship with the
engine without a separate credits file.
