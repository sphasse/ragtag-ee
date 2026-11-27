#!/usr/bin/env python3
"""Portraits for the Science DB People entries, from tools/portraits/portraits.json.

Every prompt is the file's shared `prefix` + `style` + "Subject: " + the character's `look`, so the
set matches; the image is generated at `generate_size` (square) and saved at `out_px` x `out_px` PNG
in `out_dir` (ee/ragtag/img/people/<who>.png).

  python3 tools/make_portraits.py --print            # the full prompts, to paste into ChatGPT / DALL-E
  python3 tools/make_portraits.py                    # generate all eight (needs OPENAI_API_KEY)
  python3 tools/make_portraits.py --who quill kael   # just these
  python3 tools/make_portraits.py --model gpt-image-1

Made by hand instead (ChatGPT): ask for a square 1024x1024 image with the printed prompt, download
it, then `python3 tools/make_portraits.py --import <who> <file.png>` resizes and saves it.

The full-size originals and the model's revised prompt (DALL-E 3 rewrites prompts) go to
tools/portraits/originals/ (not committed), so a face you like can be traced. Resizing uses macOS
`sips`; without it the original size is kept. Stdlib only.
"""
import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tools", "portraits", "portraits.json")
ORIGINALS = os.path.join(ROOT, "tools", "portraits", "originals")
API = "https://api.openai.com/v1/images/generations"


def load():
    with open(DATA, encoding="utf-8") as f:
        return json.load(f)


def prompt_for(cfg, ch):
    return "%s %s Subject: %s" % (cfg["prefix"], cfg["style"], ch["look"])


def pick(cfg, names):
    chars = cfg["characters"]
    if not names:
        return chars
    known = {c["who"]: c for c in chars}
    missing = [n for n in names if n not in known]
    if missing:
        sys.exit("unknown: %s (known: %s)" % (", ".join(missing), ", ".join(known)))
    return [known[n] for n in names]


def save_scaled(cfg, src, who):
    out_dir = os.path.join(ROOT, cfg["out_dir"])
    os.makedirs(out_dir, exist_ok=True)
    dst = os.path.join(out_dir, who + ".png")
    px = str(cfg["out_px"])
    if shutil.which("sips"):
        subprocess.run(["sips", "-s", "format", "png", "-z", px, px, src, "--out", dst],
                       check=True, stdout=subprocess.DEVNULL)
    else:
        print("  (no sips: saved at the original size; resize to %sx%s by hand)" % (px, px))
        shutil.copyfile(src, dst)
    print("  -> " + os.path.relpath(dst, ROOT))


def generate(cfg, ch, model):
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        sys.exit("OPENAI_API_KEY is not set (or use --print and make them in ChatGPT, then --import)")
    body = {"model": model, "prompt": prompt_for(cfg, ch), "n": 1, "size": cfg["generate_size"]}
    if model == "dall-e-3":
        body.update(quality=cfg["quality"], style=cfg["dalle_style"], response_format="b64_json")
    else:   # gpt-image-1 returns base64 already and has its own quality names
        body.update(quality="high")
    req = urllib.request.Request(API, data=json.dumps(body).encode("utf-8"), method="POST", headers={
        "Authorization": "Bearer " + key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            res = json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit("%s: HTTP %d: %s" % (ch["who"], e.code, e.read().decode("utf-8", "replace")))
    item = res["data"][0]
    os.makedirs(ORIGINALS, exist_ok=True)
    src = os.path.join(ORIGINALS, ch["who"] + ".png")
    with open(src, "wb") as f:
        f.write(base64.b64decode(item["b64_json"]))
    with open(os.path.join(ORIGINALS, ch["who"] + ".prompt.txt"), "w", encoding="utf-8") as f:
        f.write("model: %s\n\nprompt:\n%s\n" % (model, body["prompt"]))
        if item.get("revised_prompt"):
            f.write("\nrevised by the model:\n%s\n" % item["revised_prompt"])
    save_scaled(cfg, src, ch["who"])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--who", nargs="*", help="only these characters (default: all)")
    ap.add_argument("--print", action="store_true", help="print the prompts, generate nothing")
    ap.add_argument("--model", help="dall-e-3 (default, from the file) or gpt-image-1")
    ap.add_argument("--import", dest="imp", nargs=2, metavar=("WHO", "FILE"),
                    help="resize and save an image made by hand for WHO")
    args = ap.parse_args()
    cfg = load()

    if args.imp:
        who, path = args.imp
        pick(cfg, [who])
        save_scaled(cfg, os.path.abspath(path), who)
        return
    chars = pick(cfg, args.who)
    if args.print:
        for ch in chars:
            print("=== %s (%s): square %s, save as %s/%s.png ===" % (
                ch["name"], ch["role"], cfg["generate_size"], cfg["out_dir"], ch["who"]))
            print(prompt_for(cfg, ch))
            print()
        return
    model = args.model or cfg["model"]
    for ch in chars:
        print("%s: generating with %s ..." % (ch["name"], model))
        generate(cfg, ch, model)


if __name__ == "__main__":
    main()
