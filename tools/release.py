#!/usr/bin/env python3
"""Make a numbered GitHub release: build the player zip, tag the commit, publish the release.

    python3 tools/release.py --dry-run     # build the zip and the notes, show them; change nothing
    python3 tools/release.py               # release N+1 (N = the highest numbered tag, e.g. "1")
    python3 tools/release.py --radar-icons --notes extra.md --draft

Releases are plain numbers: tag "2", title "Release 2", asset ragtag-2.zip (tools/package.py).
The notes are the install steps plus the subject line of every player-facing commit since the
previous numbered tag (docs/test/tools/chore/refactor commits are left out; the compare link
lists everything); --notes adds a file's text at the top.

Before anything is tagged it checks: a clean working tree, on main, main pushed (HEAD is
origin/main), the GitHub CLI (gh) installed and signed in. Tagging and publishing are separate
steps: if publishing fails after the tag was pushed, run it again; a tag that already points at
HEAD is reused.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "dist"
REPO_URL = "https://github.com/sphasse/ragtag-ee"


def git(*args: str, check: bool = True) -> str:
    r = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed:\n{r.stderr.strip()}")
    return r.stdout.strip()


def numbered_tags() -> list[int]:
    return sorted(int(t) for t in git("tag", "--list").split() if t.isdigit())


# Commit subjects that are not player-facing (conventional-commit prefixes); the compare link
# in the notes still has every commit.
SKIP_PREFIXES = ("docs", "test", "tests", "tools", "chore", "refactor", "ci", "build", "style")


def player_facing(subject: str) -> bool:
    head = subject.split(":", 1)[0].lower() if ":" in subject else ""
    kind = head.split("(", 1)[0].strip()
    return kind not in SKIP_PREFIXES


def notes_for(number: int, previous: int | None, extra: str) -> str:
    since = f"{previous}..HEAD" if previous is not None else "HEAD"
    subjects = [s for s in git("log", "--no-merges", "--format=%s", since).splitlines()
                if s.strip() and player_facing(s)]
    lines = []
    if extra.strip():
        lines += [extra.strip(), ""]
    lines += [
        "## Install",
        "",
        f"1. Download **ragtag-{number}.zip** below.",
        "2. Find your EmptyEpsilon folder: on Windows / Linux the folder with `EmptyEpsilon.exe` / "
        "`EmptyEpsilon` in it; on macOS right-click EmptyEpsilon.app → Show Package Contents → `Contents/Resources`.",
        "3. Upgrading? Delete the old `scripts/ragtag` folder first (your campaign save is not in it).",
        "4. Unzip into that folder, merging its `scripts/` with the one already there.",
        "5. Start EmptyEpsilon and pick the scenario **The Drift** on the server.",
        "",
        f"## Changes since release {previous}" if previous is not None else "## Changes",
        "",
    ]
    lines += [f"- {s}" for s in subjects] or ["- (no commits)"]
    if previous is not None:
        lines += ["", f"Full list: {REPO_URL}/compare/{previous}...{number}"]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--number", type=int, help="release number (default: one more than the highest numbered tag)")
    ap.add_argument("--radar-icons", action="store_true", help="include the sharper station radar icons")
    ap.add_argument("--notes", help="a file whose text goes at the top of the release notes")
    ap.add_argument("--draft", action="store_true", help="publish as a draft (finish it on GitHub)")
    ap.add_argument("--dry-run", action="store_true", help="build the zip and notes only; no tag, no release")
    args = ap.parse_args()

    tags = numbered_tags()
    number = args.number or ((tags[-1] + 1) if tags else 1)
    previous = max((t for t in tags if t < number), default=None)
    tag = str(number)

    # ── Checks (all before anything is changed) ──
    if not args.dry_run:
        if git("status", "--porcelain", "--untracked-files=no"):
            sys.exit("The working tree has uncommitted changes: commit or stash them first.")
        if git("rev-parse", "--abbrev-ref", "HEAD") != "main":
            sys.exit("Releases are made from main.")
        git("fetch", "--quiet", "origin")
        if git("rev-parse", "HEAD") != git("rev-parse", "origin/main"):
            sys.exit("main is not the same as origin/main: push (or pull) first.")
        if not shutil.which("gh"):
            sys.exit("The GitHub CLI is not installed. Install it (brew install gh), then: gh auth login")
        if subprocess.run(["gh", "auth", "status"], cwd=ROOT, capture_output=True).returncode != 0:
            sys.exit("The GitHub CLI is not signed in: run  gh auth login")
        if subprocess.run(["gh", "release", "view", tag], cwd=ROOT, capture_output=True).returncode == 0:
            sys.exit(f"Release {tag} already exists on GitHub.")
        existing = git("rev-parse", "--verify", "--quiet", f"refs/tags/{tag}^{{commit}}", check=False)
        if existing and existing != git("rev-parse", "HEAD"):
            sys.exit(f"Tag {tag} already exists on another commit ({existing[:7]}).")

    # ── Build ──
    pkg = [sys.executable, str(ROOT / "tools" / "package.py"), "--version", tag, "--out", str(DIST)]
    if args.radar_icons:
        pkg.append("--radar-icons")
    if subprocess.run(pkg, cwd=ROOT).returncode != 0:
        return 1
    zpath = DIST / f"ragtag-{tag}.zip"
    extra = Path(args.notes).read_text(encoding="utf-8") if args.notes else ""
    notes_path = DIST / f"release-{tag}-notes.md"
    notes_path.write_text(notes_for(number, previous, extra), encoding="utf-8")

    if args.dry_run:
        print(f"\nDry run: release {tag} (previous: {previous}).\n  zip:   {zpath}\n  notes: {notes_path}\n")
        print(notes_path.read_text(encoding="utf-8"))
        return 0
    if git("status", "--porcelain", "--untracked-files=no"):
        sys.exit("check.py --fix changed tracked files: commit them, push, and run again.")

    # ── Tag and publish ──
    if not git("rev-parse", "--verify", "--quiet", f"refs/tags/{tag}", check=False):
        git("tag", "-a", tag, "-m", f"Release {tag}")
    git("push", "origin", f"refs/tags/{tag}")
    cmd = ["gh", "release", "create", tag, str(zpath), "--title", f"Release {tag}",
           "--notes-file", str(notes_path), "--verify-tag"]
    if args.draft:
        cmd.append("--draft")
    if subprocess.run(cmd, cwd=ROOT).returncode != 0:
        print(f"Publishing failed; the tag {tag} is pushed. Fix the problem and run this again.")
        return 1
    print(f"Release {tag} published: {REPO_URL}/releases/tag/{tag}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
