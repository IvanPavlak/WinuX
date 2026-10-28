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
   profile runs that check at every load, and `Bootstrap` at the start of every run. The
   deprecations it knows are the `$deprecations` table at the top of
   `Test-ConfigurationSchema`, one entry per key or step name (since, removal, replacement),
   which is the only thing a later deprecation adds to; a deprecation warns, never fails, and
   a key the base still ships warns only when it differs from the shipped value. Where the old shape is a function, the old
   name stays as an alias or a thin wrapper that warns once per session. The same change
   records the item in the `Deprecated` map of `Windows/PowerShell/Modules/Tests/ContractBaseline.json`
   with the version the deprecation ships in - that record is what later lets the gate accept
   its removal (see "How it is enforced").
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

### What the policy costs

Discipline. A configuration key or an exported function can no longer be removed or reshaped in
one step: a rename ships the new name next to the old one, a parameter that has to go keeps
working until the next MAJOR, and every removal waits for that MAJOR - however obvious the
cleanup looks today. Old shapes live on in the code for at least one MINOR, usually longer,
because MAJORs are rare on purpose.

That is the price of the promise in the bump table, and it is paid by whoever changes the
contract, not by every fork that merges the change. A policy that is only written down does not
hold that line: a single careless PR that drops a key would make its release a MAJOR, and with
enough of them every release is one, which tells forks nothing. So the policy is enforced.

### How it is enforced

`Windows/PowerShell/Modules/Tests/ContractBaseline.json` records the contract at the last
release: every exported function (every module except the fork-owned Custom area) with its
parameters, whether each is mandatory and its `[Alias()]` names; every exported alias; and every
key of the shipped `Configuration.psd1`, two levels deep. It also holds the `Deprecated` map -
item to the version that deprecated it - under `Functions`, `Parameters` (`Name -Parameter`) and
`ConfigurationKeys` (`Top.Child`).

The `Infrastructure-Contract` test, part of `Run-Tests -TestName "Infrastructure"` and of every
CI run, fails a change that:

- **Breaks the contract** - removes an exported function, a parameter or a configuration key, or
  makes a parameter mandatory. Additions never fail; a renamed parameter that keeps the old name
  as an `[Alias()]`, or a function kept as an exported alias, is not a removal. Two exceptions,
  both read from `[Unreleased]` in `CHANGELOG.md`, because they are what make the next release a
  MAJOR: a `### Removed` entry naming an item in backticks whose deprecation has already shipped
  in a release (its `Deprecated` version is no later than the baseline's), or a `### Breaking`
  entry naming it.
- **Misnames its release** - for every release from 1.0.0 on: `### Removed` or `### Breaking`
  outside a MAJOR; a MAJOR with neither, which is exactly the gratuitous MAJOR this policy
  exists to prevent; `### Added`, `### Changed` or `### Deprecated` in a PATCH; a MAJOR or MINOR
  that does not reset the lower parts to 0, or a version that does not go up.
- **Forgets the baseline** - the baseline's version must be the newest release in
  `CHANGELOG.md`, so a change that cuts a release without refreshing it fails.

Taking a snapshot is the release step `Run-Tests -UpdateContractBaseline`, which runs no tests:
it rewrites the file from the working tree, stamps it with the newest released version, and
carries the `Deprecated` records forward - dropping the ones the release removed, keeping the
rest.

The gate sees what a script can read. It cannot see a key the code reads that the shipped
`Configuration.psd1` does not list, a parameter that keeps its name but changes its meaning, or
a bootstrap step that behaves differently; those stay on the reviewer and on this document.

### From 0.1.94 to 1.0.0

The 0.x series tracked a milestone ladder that ended in a graphical front-end and a guided
installer for non-technical users. That destination was dropped (see the
[roadmap](../docs/winux/roadmap.md)); the terminal and the configuration file *are* the product. With
the destination gone, the ladder had nothing left to measure, and its practice of shipping
breaking changes in 0.1.x PATCH releases (MINOR was reserved for milestones) was telling forks
the opposite of what they needed to know.

1.0.0 therefore followed 0.1.94 directly. It declared the contract above stable and switched to
the strict bump table and the deprecation policy; its one engine change was a fix that rode along
(the Terminal-Icons import repairs a torn theme cache), and no configuration key or exported
function changed shape. Everything that
shipped as `### Breaking` in the 0.x series stays as it shipped - the policy applies from 1.0.0
onward.

Release candidates, when a MAJOR warrants one, use SemVer pre-release tags: `2.0.0-rc.1`,
`2.0.0-rc.2`, ...

## Changelog

- Single source of truth: `Windows/CHANGELOG.md` ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).
- **Hand-curated, no emojis** - every entry is a deliberate, tested addition, written for
  humans (describe user-visible impact, not commit hashes).
- Always keep a `## [Unreleased]` section at the top; move its contents under a new
  `## [x.y.z] - YYYY-MM-DD` heading at release time and reset Unreleased.
- Sections, in order: **Added · Changed · Breaking · Deprecated · Removed · Fixed · Security**
  (omit empty ones). The section names decide the bump, and the contract gate checks them: a
  PATCH holds only `### Fixed` and `### Security`, so a doc fix or a theming tweak is a fix; a
  `### Changed` entry makes the release at least a MINOR.
- A `### Deprecated` entry names the replacement and the migration; the matching
  `### Removed` entry in the later MAJOR repeats the migration, so a fork skipping releases
  finds it in one place.

## Release process (~5 minutes)

1. Move `[Unreleased]` items into a new dated `## [x.y.z]` section; reset Unreleased. Pick the
   bump from the table above: any `### Removed` entry that removes part of the contract, or
   any `### Breaking` entry, means MAJOR; any `### Added`, `### Changed` or `### Deprecated`
   entry means at least MINOR; otherwise PATCH. The contract gate fails a bump that disagrees.
2. Update the compare/tag links at the bottom of `Windows/CHANGELOG.md` (tags are `winux/vX.Y.Z`).
3. Refresh the contract baseline: `Run-Tests -UpdateContractBaseline`, then
   `Run-Tests -TestName "Infrastructure"`. The baseline file ships in the same commit.
4. Commit the release edits (the changelog section, the compare links and the baseline) together with the change they release, in the same commit and pull request; there is no separate release commit. A release with nothing else pending is its own small change, titled `Release vX.Y.Z`.
5. Merge the pull request. Nothing is tagged by hand: on every push to `master` the `winux-release.yml`
   workflow reads the newest `## [x.y.z]` heading of `Windows/CHANGELOG.md` and, when the tag
   `winux/vX.Y.Z` does not exist yet, creates it on that commit. A merge that only touched
   `[Unreleased]` creates nothing. The workflow runs only in the repository its manifest's `url`
   names (`Windows/PowerShell/Upstream.conf`), so the same file inside a fork never tags the fork.
6. The `Release` workflow (`.github/workflows/release.yml`) then runs for the new tag (called by
   `winux-release.yml`, or by a `winux/v*` tag pushed by hand):
   it builds `WinuX.exe` (`Windows/WinuX/New-WinuXExecutable.ps1`), extracts the matching
   `Windows/CHANGELOG.md` section as the release notes, and creates the GitHub Release with the
   executable and its SHA-256 checksum attached. Creating the release in the GitHub UI first
   also works - the workflow then only attaches the assets.
7. Verify the release page: notes match the changelog, and `WinuX.exe` + `WinuX.exe.sha256`
   are attached (`releases/latest/download/WinuX.exe` must resolve).

## Tag names

Releases are tagged `winux/vX.Y.Z`, never a bare `vX.Y.Z`. A fork may merge several upstreams (WinuX
and its macOS counterpart Foundation, which tags `foundation/vX.Y.Z`), and a clone keeps every tag in
one namespace: with the prefix in the tag itself, a plain `git fetch` brings every upstream's
releases with no clash, no `--no-tags` and no refspec. The prefix is the `tag-prefix` line of
`Windows/PowerShell/Upstream.conf`.

The tags published before 2.0.0 were bare (`v0.1.0` to `v1.9.0`). They move once, by hand:
`Windows/WinuX/Show-RetagPlan.ps1` prints every old-to-new pair in release order with its commit,
then the commands that create the prefixed annotated tags on the same commits, push them, re-point
each GitHub release (`gh release edit vX.Y.Z --tag winux/vX.Y.Z`) and delete the bare names. It runs
none of them.

## Do we automate?

The **release page and installer** are automated: every `winux/v*` tag builds `WinuX.exe` and
publishes the GitHub Release with the hand-written changelog section as its body (see step 6).
The **versioning policy** is enforced by the contract gate (see "How it is enforced"), so a
release cannot drift from the bump table unnoticed.

The **changelog itself** stays hand-curated. The history predates Conventional Commits and
this is a single-maintainer, end-user-facing project where a hand-curated changelog is higher
quality than a commit dump. If generation is ever wanted, adopt
[git-cliff](https://git-cliff.org/) as a _draft generator_ (config-driven, Keep-a-Changelog
compatible) rather than release-please or semantic-release, and only after commits move to
Conventional Commits going forward.
