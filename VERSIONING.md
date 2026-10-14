# How WinuX Versions & Releases

## Versioning - Semantic Versioning 2.0.0

WinuX uses `MAJOR.MINOR.PATCH`. Because a distribution has no classic API, we define the
contract as: **the `Configuration.psd1` schema, the bootstrap/install contract, and the set
of exported functions.**

| Bump      | When                                                                                                                                                      |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **MAJOR** | A change that breaks the contract: a config key or shape that stops being read, a bootstrap step that stops working as documented, an exported function removed or re-signatured with no compatibility path. |
| **MINOR** | New function, module, config option, or backward-compatible behavior change - and every deprecation (the old shape keeps working, a warning says what replaces it). |
| **PATCH** | Bug fixes, doc fixes, theming tweaks, dependency bumps, tested-version pins.                                                                              |

The contract is what a fork depends on when it merges upstream: its `Configuration.local.psd1`
override, its `*.local.csv` overlays, its own Custom-area code calling exported functions, and
the way it bootstraps a machine. The version number exists to tell a fork, before it merges,
whether any of that needs attention.

### Deprecation policy - breaking changes are batched, never surprises

A breaking change does not land in the release that introduces its replacement. It goes
through two steps:

1. **Deprecate (MINOR).** The new shape ships and the old one keeps working. The release
   notes list the change under `### Deprecated` with the migration. Where the old shape is a
   configuration key, `Test-ConfigurationSchema` warns on it and names the replacement; the
   profile runs that check at every load, and the mechanism will also run it at the start of
   `Bootstrap`. The next deprecation adds the warning mechanism together with its entry and
   covers the keys carried over from 0.x (below). Where the old shape is a function, the old
   name stays as an alias or a thin wrapper that warns once per session.
2. **Remove (MAJOR).** The old shape is removed in the next MAJOR, under `### Removed`, with
   the migration repeated. A deprecation survives at least one MINOR release before its
   removal, so a fork that merges every release sees the warning before the break.

A MAJOR therefore carries removals, not surprises: the pending ones accumulate under
`### Deprecated` and ship together with one migration section, whenever the maintainer decides
to cut one. There is no promised cadence. A fork that keeps its warnings at zero merges a MAJOR
as uneventfully as a PATCH.

The only exception is a change that cannot keep the old shape working - a security fix, or a
Windows change that invalidates the old behavior outright. That bumps MAJOR immediately, under
`### Breaking`, with migration notes.

### From 0.1.94 to 1.0.0

The 0.x series tracked a milestone ladder that ended in a graphical front-end and a guided
installer for non-technical users. That destination was dropped (see the
[roadmap](docs/roadmap.md)); the terminal and the configuration file *are* the product. With
the destination gone, the ladder had nothing left to measure, and its practice of shipping
breaking changes in 0.1.x PATCH releases (MINOR was reserved for milestones) was telling forks
the opposite of what they needed to know.

1.0.0 therefore followed 0.1.94 directly. It declared the contract above stable and switched to
the strict bump table and the deprecation policy; its one engine change was a fix that rode along
(the Terminal-Icons import repairs a torn theme cache), and no configuration key or exported
function changed shape. Everything that
shipped as `### Breaking` in the 0.x series stays as it shipped - the policy applies from 1.0.0
onward.

Two keys deprecated during 0.x carry over as deprecated: `BootstrapConfig.WSLSetup` (still
honored when `BootstrapConfig.Steps.WSL` is absent) and `PathTemplates.ObsidianStartupScript`
(ignored since 0.1.61). Neither warns yet; both are covered when the warning mechanism lands,
and neither is removed before 2.0.0.

Release candidates, when a MAJOR warrants one, use SemVer pre-release tags: `2.0.0-rc.1`,
`2.0.0-rc.2`, ...

## Changelog

- Single source of truth: `CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
- **Hand-curated, no emojis** - every entry is a deliberate, tested addition, written for
  humans (describe user-visible impact, not commit hashes).
- Always keep a `## [Unreleased]` section at the top; move its contents under a new
  `## [x.y.z] - YYYY-MM-DD` heading at release time and reset Unreleased.
- Sections, in order: **Added · Changed · Breaking · Deprecated · Removed · Fixed · Security**
  (omit empty ones).
- A `### Deprecated` entry names the replacement and the migration; the matching
  `### Removed` entry in the later MAJOR repeats the migration, so a fork skipping releases
  finds it in one place.

## Release process (~5 minutes)

1. Move `[Unreleased]` items into a new dated `## [x.y.z]` section; reset Unreleased. Pick the
   bump from the table above: any `### Removed` entry that removes part of the contract, or
   any `### Breaking` entry, means MAJOR; any `### Added`, `### Changed` or `### Deprecated`
   entry means at least MINOR; otherwise PATCH.
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
