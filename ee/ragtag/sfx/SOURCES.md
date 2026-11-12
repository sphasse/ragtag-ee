# Sound cues

Cue files for `RT.sound(id)` (see `ee/ragtag/core.lua`, table `RT.SOUNDS`).
This folder installs to `scripts/ragtag/sfx/`, which EmptyEpsilon resolves as a
resource root, so a file here is referenced as `"ragtag/sfx/<name>.wav"`.

## Where the files come from

The current cues are **synthesized** by `tools/gen_sfx.py` (stdlib-only,
deterministic: tones, sweeps, seeded noise). Edit a recipe there and rerun
`python tools/gen_sfx.py`; `--check` prints lengths/levels without writing.
If a length changes, update `seconds` for that id in `RT.SOUNDS`.
They are ours: no third-party licence applies. Format is mono 44.1 kHz 16-bit
WAV (no OGG encoder on the dev machine; `brew install vorbis-tools` and
`oggenc` convert if you want OGG).

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
- Formats: `.wav`, `.ogg`, `.flac` all work. Positional files must be mono
  (the generated cues are).

## Cue ids and what they mark

| id | Moment | Length | Sound |
|---|---|---|---|
| `concord_hail` | Patrol stop: ship halted, hail opens | 3.4 s | two rising comms chirps over a 55 Hz drone |
| `concord_warning` | 10 s left on the compliance clock | 0.5 s | two sharp 1 kHz pulses |
| `concord_hostile` | Patrol goes hostile | 1.8 s | descending buzzy two-tone klaxon, twice |
| `jammer_engage` | Warp jammer deploys (Concord stop) | 3.1 s | rising surge sweep into a sub thud and crackle |
| `jammer_bed` | Re-fired every 10 s while jammed | 8.0 s | detuned 62 Hz hum, band-limited hiss, wobbling whine; quieter (peak 0.275) |
| `jammer_release` | Jammer clears / crew is free to go | 1.5 s | falling tone and a soft click |

## Replacing a cue with a sourced file

Drop the file in this folder, set `file` and `seconds` in `RT.SOUNDS`
(`afinfo <file>` on macOS, `soxi -D` elsewhere), and add a row below. Remove
its recipe from `gen_sfx.py` so a rerun doesn't overwrite it. Prefer CC0
(freesound.org, opengameart.org); CC-BY is fine with attribution; avoid NC.

| File | Source | Licence | Author |
|---|---|---|---|
| (none sourced; all cues generated) | | | |
