# Changelog

All notable changes to **WinuX** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
See [VERSIONING.md](VERSIONING.md) for how we version and release.

<!-- Sections, in order (omit any that are empty in a tagged release):
     Added · Changed · Breaking · Deprecated · Removed · Fixed · Security -->

## [Unreleased]

The first public release of WinuX. Everything below will be promoted to `## [0.1.0]` when the
initial release is tagged.

### Added

- The whole system, in its first public form: a one-command PowerShell bootstrap that takes a
  fresh Windows 11 install to a fully configured machine - system settings, package managers
  (WinGet/Scoop/Chocolatey), dotfile symlinks, repositories, themes, and workspace automation -
  all driven by a single `Configuration.psd1` plus a personal `Configuration.local.psd1` override.
- Multi-machine support via hostname-detected machine types; ships the minimal, VM-ready `Test`
  profile - add your own types by configuration alone.
- The fork model: a personal config override that never conflicts with upstream pulls, and
  `merge=ours` protection for fork-owned files.
- A docsify documentation site (GitHub Pages) with a man-style reference for every function.
- Governance and licensing: MIT license, contributor guide, code of conduct, security policy,
  and third-party notices.
- CI: the full Pester suite on every pull request, and a release workflow that builds
  `WinuX.exe` from every version tag and attaches it - with a SHA-256 checksum - to the
  GitHub release.

[Unreleased]: https://github.com/IvanPavlak/WinuX/commits/master
