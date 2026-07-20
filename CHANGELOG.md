# Changelog

All notable changes to **WinuX** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). See [VERSIONING.md](VERSIONING.md) for how we version and release.

<!-- Sections, in order (omit any that are empty in a tagged release): Added · Changed · Breaking · Deprecated · Removed · Fixed · Security -->

## [Unreleased]

## [0.1.7] - 2026-07-20

### Changed

- `Terminate-AllProcessesByName` (System module) reads its target list from the new `Universal.TerminateProcessNames` configuration key instead of a hardcoded list. The base configuration ships a minimal example (`Code`); keep your real cleanup targets in `Configuration.local.psd1` (the override replaces the array wholesale on merge). When the list is absent or empty the function warns and terminates nothing.
- `Terminate-AllProcessesWithVisibleWindows` (System module) reads its always-excluded process names from the new `Universal.VisibleWindowExclusions` configuration key instead of a hardcoded list; browser processes from `Universal.Browsers` are still excluded automatically. The base configuration ships the full previous default list (`Rainmeter`, `WindowsTerminal`, `Docker Desktop`, `obs64`, and the three PowerToys processes - those are load-bearing, never remove them). When the list is absent or empty the function warns and terminates nothing, since running without exclusions would force-kill `WindowsTerminal` - the very shell executing the cleanup.

### Removed

- `Start-Application -ExecutableName`: the `AppxPackage` start method no longer launches an executable out of the package's install folder, so the parameter is gone. Callers migrate by dropping `-ExecutableName` from `AppxPackage` invocations - the app to activate is resolved from the package manifest automatically (see Fixed).

### Fixed

- `Start-Application` (Application module): the `AppxPackage` method failed with "Access is denied" for packaged UWP/Store apps - their executables live under the ACL-locked `WindowsApps` folder and cannot be started directly with `Start-Process`. The method now resolves the app's AppUserModelID (`PackageFamilyName!AppId`) from the package manifest and activates it through `shell:AppsFolder`, the supported launch path for packaged apps. `Open-WhatsApp`, the method's only shipped caller, works again.
- WhatsApp Desktop actually runs as `WhatsApp.Root`, not `WhatsApp`, so `Open-WhatsApp`'s already-running guard never detected a running instance and `Clear-WhatsAppLocalStorage` never stopped the app before clearing its storage. Both now target `WhatsApp.Root` (the default `Terminate-AllProcessesByName` cleanup target moved into configuration - see Changed).

## [0.1.6] - 2026-07-15

### Changed

- `Configure-Taskbar` (System module) now machine-scopes the taskbar pin list: each `TaskbarConfiguration` row may carry a `Machine` field (`All`, `Test`, `PC/Laptop`, ...) matched against the current machine type through `Test-MachineTypeScope` — the same gate the app CSVs use — so one list drives every machine. A row that omits `Machine` (or leaves it blank) defaults to `All`, preserving the previous "pin everywhere" behavior for untagged rows. The shipped `Configuration.psd1` list is a tagged example; keep your real, machine-specific list in `Configuration.local.psd1` (it replaces the base array wholesale on merge).
- `Configure-Taskbar` and `Unpin-TaskbarApps` (System module) now write the generated `taskbar_layout.xml` directly to a machine-local path (`PathTemplates.TaskbarLayoutFile`, default `C:\ProgramData\provisioning\taskbar_layout.xml`) that the `StartLayoutFile` policy points at, instead of writing it into the repository and symlinking the provisioning path to it. The layout is produced entirely from configuration, so nothing needs to be versioned and no symlink is created; each machine keeps its own copy. On a machine provisioned by the old design, a pre-existing symlink at that path (live or dangling) is removed before writing, so the first run migrates cleanly to a real file instead of writing back through the link into the repo.

### Removed

- The versioned `Windows/TaskbarConfiguration/taskbar_layout.xml` file and the `SymbolicLinks.TaskbarConfiguration` / `PathTemplates.TaskbarConfigurationDir` configuration keys. The taskbar layout is now generated straight to its machine-local path (see Changed), so the committed copy — which had drifted out of sync with `TaskbarConfiguration` — and its symlink are no longer needed.

### Fixed

- `Rebuild-IconCache` (System module) no longer surfaces a `Remove-Item: … cannot find the file specified` error while clearing the icon cache. With Explorer stopped, a file enumerated in the cache folder can vanish before it is deleted; the cleanup now checks the folder exists, re-checks each file immediately before removing it, and ignores per-file failures — so nothing is removed when there is nothing to remove.

## [0.1.5] - 2026-07-15

### Added

- `Test-MachineTypeScope` (Bootstrap module): the single gate behind every machine-scoped data source - the `Machine` column of the WinGet/Scoop/Chocolatey CSVs and `BootstrapConfig.PersonalSteps`. Splits a scope like `PC/Laptop` on `/`, matches case-insensitively, treats `All` as the wildcard, and validates every token against `ValidMachineTypes`: an unknown token (e.g. the typo `Labtop`) is reported via `Write-LogError` together with its data source and the list of valid values, and contributes nothing to the match - a misspelled scope can no longer silently install or skip anything.
- `Invoke-PersonalSteps` (Bootstrap module): runs the fork-defined `BootstrapConfig.PersonalSteps`, extracted out of `Bootstrap` into its own exported function. Entries are now machine-gated: a plain function name runs on every machine type (exactly as before), while `@{ Function = "Install-MyTool"; Machine = "PC/Laptop" }` runs only where its `Machine` scope matches - mirroring the app CSVs' `Machine` column.

### Changed

- `Install-WingetApps`, `Install-ScoopApps`, and `Install-ChocolateyApps` (Application module) route their `Machine`-column filtering through `Test-MachineTypeScope`, so CSV rows gain the same unknown-token validation instead of three copies of a silent inline filter.

### Fixed

- `Test-AdminPrivileges` (Helper module): the elevate-and-rerun offer replayed the immediate caller's source line, which at call depth two or more is an engine line such as `& $stepName` - the fresh elevated shell has no such variable, so the rerun died with "The expression after '&' in a pipeline element produced an object that was not valid". It now replays the outermost call-stack frame that recorded a line - the command the user actually typed - with unchanged behavior for every existing depth-one caller.

## [0.1.4] - 2026-07-11

### Added

- The **Custom area** (`Modules/Custom` + `docs/custom`): a fork-owned half of the module tree, laid out as a mirror of `Modules/`, where a fork keeps the functions and whole modules that are not (yet) part of upstream WinuX. Upstream ships only the aggregator (`Custom.psd1` + `Custom.psm1`) and a README/landing page; a fork adds function files under `Custom/<Module>/Functions/`, their tests under `Custom/<Module>/Tests/`, and man-style docs under `docs/custom/<module>.md`. Because upstream never writes inside those payload paths, an upstream pull never conflicts with a fork's own code, and promoting something into WinuX later is a mechanical `git mv`. The `Custom` module autoloads lazily like every engine module - its `FunctionsToExport` ships empty and each fork lists its own functions there - and the loader skips, with a warning, any payload file whose name would shadow an existing engine function, so the Custom area only ever adds behavior. `Load-PathConfiguration` registers `Modules\Custom` as an additional module root so whole fork-owned modules (`Custom/<Name>` with their own manifest) autoload too. See the [Fork Model](docs/contributing/fork-model.md) and `Modules/Custom/README.md`.
- `Reload-WinuXModules` (System module): removes and re-imports every WinuX module, additionally scanning `Modules/Custom` for whole fork modules. Replaces `Reload-CustomModules` (see Changed).

### Changed

- Renamed `Reload-CustomModules` to `Reload-WinuXModules` (System module) to remove the ambiguity the Custom area introduces ("custom modules" previously meant the project's own modules). No compatibility alias is kept: update any call sites or aliases to the new name. `Reload-PowerShellProfile` calls it internally and is otherwise unchanged.
- `Run-Tests` (Tests module) now also discovers Pester tests under the Custom area (`Modules/Custom/<Module>/Tests`), so fork functions meet the same test bar as engine functions.
- `Test-ManifestCompleteness` (Helper module) and the "Manifest Completeness" Pester test now also verify the Custom area: every `Custom/<Module>/Functions/*.ps1` must be listed in `Custom.psd1`, and a whole fork module is checked against its own manifest. Both pass unchanged on a pure-upstream setup, where the Custom area is empty.
- `List-Functions` (Helper module) now parses `docs/custom/*.md` alongside `docs/modules/*.md`, so `-ListDiscrepancies` checks fork functions against the loaded `Custom` module exactly as it does engine functions.

## [0.1.3] - 2026-07-10

### Added

- `Open-Project -InSameShell` (Workflow module): when explicitly passed, overrides the configured `InSameShell` value of the `Open-ProjectTerminals-Or-RunProject` action so the project's terminal tabs open in the caller's Windows Terminal window. Used by `Open-Workspace -Alongside` to gather all tabs in the relaunched shell window.

### Changed

- `Open-Workspace -Alongside` (Workflow module) now always runs in a completely new shell: the invocation relaunches itself in a fresh Windows Terminal window and hands the calling shell its prompt back immediately. The new window is created under an explicit window ID that is passed to the relaunched shell via `WT_WINDOW_ID`, terminal-opening actions inside it are forced to `-InSameShell` so the workspace's terminal tabs join that exact window (never the most-recently-used one), the window layout places the new window on the workspace's virtual desktops like any other workspace window, and a configured `Terminate-WindowsTerminalTabs -OnlyCurrent` closes the now-redundant bootstrap tab as its final step.
- `Open-Terminal -InSameShell` (Application module) targets the exact caller window via `$env:WT_WINDOW_ID` when the calling shell knows its own window ID, falling back to window ID 0 as before. Windows Terminal resolves `-w 0` to the *most recently used* window, so with multiple terminal windows open the fallback can land tabs in a different window than the caller's - setting `WT_WINDOW_ID` removes that ambiguity.

### Fixed

- `Open-Workspace -Alongside` (Workflow module) is far less prone to failing partway through with virtual-desktop "RPC server may be unavailable" errors (or a silently ignored `Switch-Desktop`). The Windows `VirtualDesktop` COM/RPC session that creating, switching, and removing desktops relies on tends to go stale in a long-running shell, and `-Alongside` is the heaviest user of those calls (it creates desktops to the right of existing ones, moves the new windows onto them, and prunes empties). Because the whole flow now runs in a brand-new shell (see Changed), those calls execute against a fresh RPC session from the start, which circumvents the stale-session failures in practice - it does not fix a session wedged outside the WinuX process, hence "far less prone" rather than "never".

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

[Unreleased]: https://github.com/IvanPavlak/WinuX/compare/v0.1.7...HEAD
[0.1.7]: https://github.com/IvanPavlak/WinuX/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/IvanPavlak/WinuX/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/IvanPavlak/WinuX/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/IvanPavlak/WinuX/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/IvanPavlak/WinuX/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/IvanPavlak/WinuX/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/IvanPavlak/WinuX/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/IvanPavlak/WinuX/releases/tag/v0.1.0
