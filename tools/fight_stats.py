#!/usr/bin/env python3
"""Read the fight log (BOUT, ee/ragtag/bout.lua) out of EmptyEpsilon's scriptstorage.json.

Where the file is: in the EmptyEpsilon folder on Windows (next to EmptyEpsilon.exe), and
~/.emptyepsilon/scriptstorage.json on macOS and Linux. Copy it from each server machine and pass them all:
rows are merged (a row is its run's session id + sequence number), so the same file twice counts once.

  python3 tools/fight_stats.py scriptstorage.json                 # who fought how much, by crew
  python3 tools/fight_stats.py a.json b.json --crew 3             # one crew only (repeat --crew for more)
  python3 tools/fight_stats.py scriptstorage.json --csv fights.csv
  python3 tools/fight_stats.py scriptstorage.json --correlate     # which stats track the crews' rating

--correlate ranks every numeric stat by its rank correlation (Spearman) with the crews' rating
(1 far too easy ... 3 good fight ... 5 far too hard; rows from before the 1-5 scale, rated 1-3, are read
as 2 / 3 / 4) over the rated rows: the stats near +1 or -1 say most about how
a fight felt. A first reading needs about 30 rated fights; under 10 it says so. Stdlib only.
"""
import argparse
import csv
import json
import math
import sys

KEY = "ragtag.fightlog"
RATING = {1: "far too easy", 2: "easy", 3: "good fight", 4: "hard", 5: "far too hard"}
# Not stats: identity and context. Everything else numeric is correlated.
NOT_STATS = {"v", "seq", "crew", "rating", "ships", "enemies", "skill_r", "skill_before", "skill_after"}
FIRST = ["session", "seq", "source", "crew", "ship", "outcome", "rating", "rated_by", "slot", "predicted_r",
         "skill_r", "skill_before", "skill_after",
         "secs", "contact_secs", "hull_lost", "hull_lost_pct", "shield_damage", "system_damage", "min_hull_pct",
         "min_shield_pct", "shield_down_secs", "heat_max", "hot_secs", "energy_min_pct", "missiles_fired",
         "damage_dealt", "kills", "enemies", "enemy_types", "enemy_strength", "ship_strength", "ships"]


def load(paths, key):
    rows, seen = [], set()
    for p in paths:
        with open(p, encoding="utf-8") as f:
            store = json.load(f)
        raw = store.get(key)
        if raw is None:
            print(f"{p}: no '{key}' in it (no fights recorded there yet)", file=sys.stderr)
            continue
        log = json.loads(raw) if isinstance(raw, str) else raw
        for r in log.get("rows") or []:
            ident = (r.get("session"), r.get("seq"), r.get("ship"))
            if ident in seen:
                continue
            seen.add(ident)
            if r.get("rating") is not None and (r.get("v") or 1) < 2:
                r["rating"] = r["rating"] + 1   # the old 1-3 scale onto 1-5
            rows.append(r)
    return rows


def ranks(xs):
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    out = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        for k in range(i, j + 1):
            out[order[k]] = (i + j) / 2 + 1
        i = j + 1
    return out


def spearman(xs, ys):
    rx, ry = ranks(xs), ranks(ys)
    n = len(xs)
    mx, my = sum(rx) / n, sum(ry) / n
    num = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    den = math.sqrt(sum((a - mx) ** 2 for a in rx) * sum((b - my) ** 2 for b in ry))
    return num / den if den else 0.0


def summary(rows):
    by = {}
    for r in rows:
        k = r.get("crew") or 0
        e = by.setdefault(k, {"fights": 0, "rated": 0, "won": 0, "ratings": {n: 0 for n in RATING}})
        e["fights"] += 1
        e["won"] += 1 if r.get("outcome") == "won" else 0
        if r.get("rating") in RATING:
            e["rated"] += 1
            e["ratings"][r["rating"]] += 1
    print(f"{len(rows)} fight rows, {len({r.get('session') for r in rows})} session(s)")
    for k in sorted(by):
        e = by[k]
        name = f"crew {k}" if k else "unassigned"
        rt = ", ".join(f"{RATING[n]} {c}" for n, c in e["ratings"].items() if c)
        print(f"  {name}: {e['fights']} fights, {e['won']} won, {e['rated']} rated" + (f" ({rt})" if rt else ""))
    if 0 in by:
        print("  (unassigned rows: give each ship a crew number on the arena's Crews... screen)")


def correlate(rows):
    rated = [r for r in rows if r.get("rating") in RATING]
    print(f"{len(rated)} rated fights")
    if len(rated) < 10:
        print("Too few to say much: about 30 rated fights give a first reading.")
        if len(rated) < 3:
            return
    keys = sorted({k for r in rated for k, v in r.items()
                   if isinstance(v, (int, float)) and not isinstance(v, bool) and k not in NOT_STATS})
    ys = [r["rating"] for r in rated]
    out = []
    for k in keys:
        xs = [float(r.get(k) or 0) for r in rated]
        if len(set(xs)) < 2:
            continue
        out.append((spearman(xs, ys), k))
    out.sort(key=lambda t: -abs(t[0]))
    print("Rank correlation with the rating, 1-5 (+ : higher means it felt harder; - : easier):")
    for rho, k in out:
        bar = "#" * int(round(abs(rho) * 20))
        print(f"  {k:18s} {rho:+.2f} {bar}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="scriptstorage.json file(s)")
    ap.add_argument("--key", default=KEY, help=f"the storage key (default {KEY})")
    ap.add_argument("--crew", type=int, action="append", help="only these crew numbers (0: unassigned)")
    ap.add_argument("--source", help="only rows from this source (arena, pit, ...)")
    ap.add_argument("--csv", help="write the rows to this CSV file")
    ap.add_argument("--correlate", action="store_true", help="rank the stats by correlation with the rating")
    args = ap.parse_args()

    rows = load(args.files, args.key)
    if args.crew is not None:
        rows = [r for r in rows if (r.get("crew") or 0) in args.crew]
    if args.source:
        rows = [r for r in rows if r.get("source") == args.source]
    summary(rows)
    if args.csv:
        cols = FIRST + sorted({k for r in rows for k in r} - set(FIRST))
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            for r in rows:
                w.writerow({c: r.get(c, "") for c in cols})
        print(f"wrote {len(rows)} rows to {args.csv}")
    if args.correlate:
        correlate(rows)


if __name__ == "__main__":
    main()
