# Portraits

Faces for the Science database's **People** entries (`SCIDB.PROFILES`, `ee/ragtag/world/sciencedb.lua`).
EmptyEpsilon shows one image per database entry; comms windows can't show pictures.

- `portraits.json` holds the prompts: one shared `style` (framing, light, background, palette) and one
  `look` per character. The looks are the canon for how these people appear.
- `python3 tools/make_portraits.py --print` prints the eight full prompts.
- `OPENAI_API_KEY=... python3 tools/make_portraits.py [--who quill]` generates them with DALL-E 3
  (square 1024x1024, HD, "natural" style) and saves 512x512 PNGs as `ee/ragtag/img/people/<who>.png`.
- Made in ChatGPT instead: paste a printed prompt, ask for a square 1024x1024 image, download it, then
  `python3 tools/make_portraits.py --import <who> <file.png>`.

Keeping the set consistent: change only a character's `look`, never the `style`, when redoing one face;
if the style changes, redo all eight. DALL-E 3 rewrites prompts a little, so a re-run gives a new face:
the original and the model's revised prompt are kept in `originals/` (not committed) for the one you keep.
