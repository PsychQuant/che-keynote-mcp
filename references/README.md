# references/ — curated reference repos (clone-on-demand)

Only this README is tracked; the clones themselves are gitignored
(`references/*` in .gitignore). Reproduce with the commands below.
Selection rationale: deep-search report attached to
[PsychQuant/macdoc#140](https://github.com/PsychQuant/macdoc/issues/140)
(snapshot 2026-07-18).

## Clone these

```bash
cd references

# .key round-trip implementation (Python, MIT). Study its Protobuf-schema
# extraction methodology (schemas pulled from the local Keynote.app rather
# than hardcoded) and its Keynote-version-drift handling — the reference
# for any future .key direct-parsing work (v2+ evaluation).
git clone https://github.com/psobot/keynote-parser

# AppleScript capability-boundary risk register (Python CLI, 1★ but the
# honest limitation list is the value — transcribed into
# docs/applescript-boundary.md). Also demonstrates batched AppleScript
# (20 slides per batch) and the System Events UI-scripting escalation.
git clone https://github.com/josephyooo/keynote-cli

# iWork '13+ file-format reverse-engineering documentation (zip + Snappy
# compressed Protobuf "IWA"). The first-hand format reference.
git clone https://github.com/obriensp/iWorkFileFormat
```

## Read-only — do NOT clone into this repo

- [`6over3/WorkKit`](https://github.com/6over3/WorkKit) — the only
  Swift-native iWork parser (visitor-pattern API worth reading). **License
  is AGPL-3.0**, which conflicts with this family's closed binary
  distribution; to keep any contamination question trivially answerable,
  the code never enters this repository. Read it on GitHub if needed.

## Deliberately not referenced

- `easychen/keynote-mcp`, `reichenbach/iwork_mcp` — Python/TypeScript
  servers shelling out to `osascript` (the unsupported TCC path we
  explicitly avoid; see docs/applescript-boundary.md). Their tool
  taxonomies informed the v1 category layout; their code is not a
  dependency or architectural reference.
