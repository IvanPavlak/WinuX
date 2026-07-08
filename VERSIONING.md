# How WinuX Versions & Releases

## Versioning - Semantic Versioning 2.0.0

WinuX uses `MAJOR.MINOR.PATCH`. Because a distribution has no classic API, we define the
contract as: **the `Configuration.psd1` schema, the bootstrap/install contract, and the set
of exported functions.**

| Bump      | When                                                                                                                                  |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **MAJOR** | Breaking change to the config schema, the install/bootstrap contract, or removal of an exported function with no compatibility alias. |
| **MINOR** | New function, module, config option, or GUI surface - backward compatible.                                                            |
| **PATCH** | Bug fixes, doc fixes, theming tweaks, dependency bumps.                                                                               |

### Pre-1.0 (the 0.x series)

Per SemVer §4, anything MAY change while we are below 1.0. Breaking changes bump **MINOR**
(not MAJOR) and MUST appear under a `### Breaking` heading with migration notes.

**1.0.0** is reached when all four pillars are simultaneously true and proven on clean
machines:

1. A GUI covers almost everything a normal user needs.
2. A guided, standalone install.
3. WinuX is completely standalone (no manual clone-and-fix).
4. It is battle-tested (green CI + clean-VM smoke tests).

Release candidates use SemVer pre-release tags: `1.0.0-rc.1`, `1.0.0-rc.2`, …

### Milestone ladder

| Version     | Gate                                                                                                                                                 |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0.1.0       | First public release; sanitized snapshot, generic `Test` profile, license + governance files, docs on Pages, CI green, changelog started. |
| 0.2.0       | Fully config-driven bootstrap - fork, edit one config, run one line, working system; zero code edits.                                                |
| 0.3.0       | Standalone guided installer with uninstall/rollback.                                                                                                 |
| 0.4.0       | A safer, idempotent, migration-aware evolution of the existing `Bootstrap -WithInitialSetup` reprovisioning.                                         |
| 0.5.0       | Battle-testing: green CI on windows-latest + a documented clean-VM test matrix.                                                                      |
| 0.6.0-0.9.x | Incremental GUI build-out per config domain; 0.9.0 = GUI feature-complete.                                                                           |
| 1.0.0       | All four pillars true and proven.                                                                                                                    |

## Changelog

- Single source of truth: `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
- **Hand-curated, no emojis** - every entry is a deliberate, tested addition, written for
  humans (describe user-visible impact, not commit hashes).
- Always keep a `## [Unreleased]` section at the top; move its contents under a new
  `## [x.y.z] - YYYY-MM-DD` heading at release time and reset Unreleased.
- Sections, in order: **Added · Changed · Breaking · Deprecated · Removed · Fixed · Security**
  (omit empty ones).

## Release process (~5 minutes)

1. Move `[Unreleased]` items into a new dated `## [x.y.z]` section; reset Unreleased.
2. Update the compare/tag links at the bottom of `CHANGELOG.md`.
3. Commit: `Release vX.Y.Z`.
4. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z"` and push the tag.
5. The `Release` workflow (`.github/workflows/release.yml`) picks the tag up automatically:
   it builds `WinuX.exe` (`Windows/WinuX/New-WinuXExecutable.ps1`), extracts the matching
   `CHANGELOG.md` section as the release notes, and creates the GitHub Release with the
   executable and its SHA-256 checksum attached. Creating the release in the GitHub UI first
   also works - the workflow then only attaches the assets.
6. Verify the release page: notes match the changelog, and `WinuX.exe` + `WinuX.exe.sha256`
   are attached (`releases/latest/download/WinuX.exe` must resolve).

## Do we automate?

The **release page and installer** are automated: every `v*` tag builds `WinuX.exe` and
publishes the GitHub Release with the hand-written changelog section as its body (see step 5).

The **changelog itself** stays hand-curated. The history predates Conventional Commits and
this is a single-maintainer, end-user-facing project where a hand-curated changelog is higher
quality than a commit dump. If generation is ever wanted, adopt
[git-cliff](https://git-cliff.org/) as a _draft generator_ (config-driven, Keep-a-Changelog
compatible) rather than release-please or semantic-release, and only after commits move to
Conventional Commits going forward.
