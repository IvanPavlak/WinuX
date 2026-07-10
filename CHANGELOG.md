# Changelog

All notable changes to **WinuX** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). See [VERSIONING.md](VERSIONING.md) for how we version and release.

<!-- Sections, in order (omit any that are empty in a tagged release): Added · Changed · Breaking · Deprecated · Removed · Fixed · Security -->

## [Unreleased]

## [0.1.3] - 2026-07-10

### Added

- `Open-Project -InSameShell` (Workflow module): when explicitly passed, overrides the configured `InSameShell` value of the `Open-ProjectTerminals-Or-RunProject` action so the project's terminal tabs open in the caller's Windows Terminal window. Used by `Open-Workspace -Alongside` to gather all tabs in the relaunched shell window.

### Changed

- `Open-Workspace -Alongside` (Workflow module) now always runs in a completely new shell: the invocation relaunches itself in a fresh Windows Terminal window and hands the calling shell its prompt back immediately. The new window is created under an explicit window ID that is passed to the relaunched shell via `WT_WINDOW_ID`, terminal-opening actions inside it are forced to `-InSameShell` so the workspace's terminal tabs join that exact window (never the most-recently-used one), the window layout places the new window on the workspace's virtual desktops like any other workspace window, and a configured `Terminate-WindowsTerminalTabs -OnlyCurrent` closes the now-redundant bootstrap tab as its final step.
- `Open-Terminal -InSameShell` (Application module) targets the exact caller window via `$env:WT_WINDOW_ID` when the calling shell knows its own window ID, falling back to window ID 0 as before. Windows Terminal resolves `-w 0` to the *most recently used* window, so with multiple terminal windows open the fallback can land tabs in a different window than the caller's - setting `WT_WINDOW_ID` removes that ambiguity.

## [0.1.2] - 2026-07-09

### Changed

- `Configure-NerdFont` installs far fewer files, so the bootstrap font step finishes in a fraction of the time. `JetBrainsMonoNerdFont/` now ships only the four faces the shipped configuration actually renders - Regular, Bold, Italic, and Bold Italic of `JetBrainsMono Nerd Font` - instead of the full file family. Windows Terminal, Oh My Posh, and FastFetch are visually unchanged: they only ever request that one face at normal and bold weight, and the full Nerd Font glyph/icon set is present in every face.

### Removed

- Unused files from `JetBrainsMonoNerdFont/`: the `Mono` and `Propo` spacing variants, the ligature-free `NL` family, and every weight other than Regular and Bold (Thin, ExtraLight, Light, Medium, SemiBold, ExtraBold, and all their italics). Nothing in the shipped configuration referenced them. Forks that point a terminal or editor at one of these faces should install that variant themselves.

## [0.1.1] - 2026-07-09

### Added

- `Set-VisualEffects` (System module): applies the Performance Options "Visual Effects" settings programmatically from the new `VisualEffects` configuration section - one human-readable boolean per dialog checkbox, written via the registry and `SystemParametersInfo`. Config-gated: the base configuration ships the section fully commented so a vanilla bootstrap changes nothing; forks opt in via `Configuration.local.psd1`. Runs during Bootstrap right after `Set-TaskbarAutoHide`. Every managed effect is reported on its own colored row: green = enabled, red = disabled, yellow `[skipped]` = already at the configured value.
- `Write-LogStep -Style` (Logging module): render a step row in another level's color (e.g. a green/red outcome row) while keeping the plain Step layout, visibility, and STEP file-log tag.

### Changed

- Versioning policy (`VERSIONING.md`): below 1.0, `0.x.0` releases are reserved for milestone-ladder gates, and backward-compatible additions that land between milestones ship as `0.1.x` patch releases. The strict SemVer split (new function/config option = MINOR) resumes at 1.0.0.

## [0.1.0] - 2026-07-08

The first public release of WinuX.

### Added

- The whole system, in its first public form: a one-command PowerShell bootstrap that takes a fresh Windows 11 install to a fully configured machine - system settings, package managers (WinGet/Scoop/Chocolatey), dotfile symlinks, repositories, themes, and workspace automation - all driven by a single `Configuration.psd1` plus a personal `Configuration.local.psd1` override.
- Multi-machine support via hostname-detected machine types; ships the minimal, VM-ready `Test` profile - add your own types by configuration alone.
- The fork model: a personal config override that never conflicts with upstream pulls, and `merge=ours` protection for fork-owned files.
- A docsify documentation site (GitHub Pages) with a man-style reference for every function.
- Governance and licensing: MIT license, contributor guide, code of conduct, security policy, and third-party notices.
- CI: the full Pester suite on every pull request, and a release workflow that builds `WinuX.exe` from every version tag and attaches it - with a SHA-256 checksum - to the GitHub release.

[Unreleased]: https://github.com/IvanPavlak/WinuX/compare/v0.1.2...HEAD
[0.1.2]: https://github.com/IvanPavlak/WinuX/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/IvanPavlak/WinuX/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/IvanPavlak/WinuX/releases/tag/v0.1.0
