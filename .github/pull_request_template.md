## What this changes
<!-- Universe extension? New scenario? Framework change? One or two sentences. -->

## Checklist
- [ ] `python tools/check.py` passes (run `--fix` to regenerate generated files)
- [ ] Played or smoke-tested in EmptyEpsilon (`tools/ci_headless.sh` or a real server)
- [ ] Universe changes: no place a scenario depends on was renamed or removed
- [ ] New scenario: number not used by stock EmptyEpsilon or another scenario here; places declared with `VERSE.requirePlaces`
- [ ] Framework changes: Lua action list and `director/actions.py` still match
