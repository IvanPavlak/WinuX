# Bootstrap Module

The Bootstrap module is the **heart of WinuX** - it orchestrates the entire system setup process, manages PowerShell profile initialization, and handles the two-stage bootstrap architecture.

## [Bootstrap](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Bootstrap.ps1)

- **Description:** The main orchestration function and heart of WinuX. Provisions a complete machine - installs software, configures Windows, and creates symlinks - by running all setup steps in a fixed order. Requires administrator privileges and an active internet connection, and is safe to re-run since every installation and configuration step is idempotent.
- **Parameters:** -RepoRoot, -WithInitialSetup, -Skip, -Include
- **Usage:** `Bootstrap`, `Bootstrap -WithInitialSetup`, `Bootstrap -RepoRoot "<DevRoot>\WinuX"`, `Bootstrap -Skip UpgradeAll, WSL`

Transforms a fresh Windows installation into a fully configured development environment. The `-WithInitialSetup` switch adds first-time-only steps (machine rename, Windows activation, Win11Debloat) and should be omitted on subsequent runs. If `-RepoRoot` is not supplied it defaults to `$global:MachineSpecificPaths.Projects.Self.Root`. Logging runs via `Start-Logging` / `Stop-Logging` for the duration of the run.

Every step is individually toggleable via `BootstrapConfig.Steps`, resolved once per run by [Resolve-BootstrapSteps](#resolve-bootstrapsteps); `-Skip`/`-Include` override the config per invocation. Most steps also no-op on their own when their configuration section is empty, so an enabled step on the empty base config applies nothing. The opt-in steps that act the moment they run default off: `MicrosoftActivationScripts`, `Win11Debloat`, `DeveloperMode`, `NuGetConfig`, `CoreAiRules`, `LockedStartLayout`.

The three package-manager steps are additionally gated by [Resolve-PackageManagers](#resolve-packagemanagers), called once per run: a manager is installed only when it is listed in `PackageManagers` **and** has at least one app for this machine type. The step toggle can therefore only turn a manager off - enabling `ScoopApps` does not install Scoop if `PackageManagers` omits it or its app list is empty. On the base configuration that means WinGet alone, because `ScoopApps.csv` and `ChocolateyApps.csv` ship empty.

Execution sequence:

1. (`-WithInitialSetup` only) `Rename-Machine`, `Start-MicrosoftActivationScripts`, `Start-Win11Debloat` (the latter two opt-in via `Steps`)
2. `Update-Repositories` - pulls latest dotfiles and all configured repositories; scope governed by `BootstrapConfig.RepositoryUpdateScope` (`"None"` skips), not by a step
3. Execution policy, Developer Mode, power plan, power button actions
4. System theme, locale, display language, keyboard layouts
5. Nerd Font, PowerShell modules, special folder redirections
6. WSL configuration
7. WinGet, Scoop, and Chocolatey - install each manager in play then its apps from CSVs
8. Upgrade all packages, fork-defined personal steps (BootstrapConfig.PersonalSteps, each entry optionally machine-gated like the app CSVs' `Machine` column), .NET EF CLI
9. Environment variables, Conda environments, NuGet config, taskbar pins
10. WSL environment initialization, symbolic links, CoreAiRules enforcement layer (opt-in via `Steps.CoreAiRules`), WSL SSH setup
11. Lock taskbar layout, restart Explorer, restart machine

| Parameter           | Type     | Required | Description                                                                                                                  |
| ------------------- | -------- | -------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `-RepoRoot`         | String   | No       | Absolute path to the WinuX repository root. Auto-detected from `$global:MachineSpecificPaths.Projects.Self.Root` if omitted. |
| `-WithInitialSetup` | Switch   | No       | Includes first-time-only steps: machine rename, Windows activation, and Win11Debloat. Omit on subsequent runs.               |
| `-Skip`             | String[] | No       | Step names forced off for this run, overriding `BootstrapConfig.Steps`. See `Resolve-BootstrapSteps` for the step list.      |
| `-Include`          | String[] | No       | Step names forced on for this run, overriding `BootstrapConfig.Steps`.                                                       |

```powershell
# Re-provision the machine (safe for repeated use after initial setup)
Bootstrap

# First-time provisioning on a new machine
Bootstrap -WithInitialSetup

# Provision using an explicit dotfiles repository path
Bootstrap -RepoRoot "<DevRoot>\WinuX"

# Re-provision without upgrading packages or touching WSL
Bootstrap -Skip UpgradeAll, WSL

# Force a config-disabled or default-off step on for one run
Bootstrap -Include Win11Debloat
```

## [DetermineMachineType](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/DetermineMachineType.ps1)

- **Description:** Resolves the current machine type from the Windows hostname, or interactively if the hostname is not mapped. Looks up `$env:COMPUTERNAME` in the `HostnameToMachineType` table in `Configuration.psd1`; if unmapped, prompts the user to select from `ValidMachineTypes` (PC, Laptop, Work, Test). Sets `$global:MachineType` and returns it, short-circuiting immediately if it is already set and valid.
- **Usage:** `DetermineMachineType`

Determines the machine type from the Windows hostname. The lookup runs against `HostnameToMachineType` in `Configuration.psd1`; when the hostname is not found, it displays the available types and **prompts the user interactively** until a valid selection is made, then stores the result in `$global:MachineType`. If `$global:MachineType` is already set to a valid value, it is returned without prompting; if it is set but invalid, the stale value is discarded and resolution proceeds normally.

```
$env:COMPUTERNAME → HostnameToMachineType lookup → MachineType
"MyMachine"       → HostnameToMachineType["MyMachine"] → "PC"
"Unknown"         → Not found → Interactive prompt → User selects type
```

```powershell
# Resolve and return the machine type (e.g. "PC" or "Laptop");
# prompts interactively only when the hostname is not in HostnameToMachineType
DetermineMachineType
```

Relevant `Configuration.psd1` keys:

| Key                     | Description                                                                                                   |
| ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| `ValidMachineTypes`     | Allowed machine types (e.g. `@("PC", "Laptop", "Work", "Test")`); selections are validated against this list. |
| `HostnameToMachineType` | Maps a hostname to a machine type for automatic resolution.                                                   |

> Note: `DetermineMachineType` does **not** fall back to `DefaultMachineType`; it prompts the user instead. `DefaultMachineType` is only used by `Load-PathConfiguration` for silent profile loading, so shell startup never blocks on input.

## [Expand-ConfigPaths](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Expand-ConfigPaths.ps1)

- **Description:** Expands placeholder tokens (`{Dev}`, `{User}`, `{MachineType}`, `{RepoRoot}`, `{AppData}`) in configuration paths with their actual values based on machine type and base paths, then applies machine-specific overrides. Lives in the Bootstrap module (imported eagerly at startup) so `Load-PathConfiguration` can expand paths without autoloading the larger Helper module.
- **Parameters:** -Configuration, -MachineType, -RepoRoot
- **Usage:** `Expand-ConfigPaths -Configuration $Configuration -MachineType "PC"`

Reads `PathTemplates` and `BasePaths` from the full `Configuration.psd1` hashtable and delegates the recursive token substitution to `Expand-Hashtable`, using the selected machine type's `Dev` and `User` base paths. If `MachineType` is not present in `BasePaths`, it warns and falls back to `Test`. After expansion, any entries in `Configuration.MachineOverrides[MachineType]` are merged into the result via `Merge-Hashtable`.

| Token           | Meaning                                                       |
| --------------- | ------------------------------------------------------------- |
| `{Dev}`         | Development directory for the machine type (e.g. `<DevRoot>`) |
| `{User}`        | User-specific directory (e.g. `C:\Users\<User>`)              |
| `{MachineType}` | The current machine type (PC, Laptop, Work, Test)             |
| `{RepoRoot}`    | Root of the WinuX repository                                  |
| `{AppData}`     | User AppData directory                                        |

| Parameter        | Description                                                                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `-Configuration` | The full `Configuration.psd1` hashtable.                                                                                             |
| `-MachineType`   | The machine type (PC, Laptop, Work, Test) used to select base paths and overrides. Falls back to `Test` if not found in `BasePaths`. |
| `-RepoRoot`      | Optional explicit repository root for the `{RepoRoot}` token; passed in by `Load-PathConfiguration` from the self-located root.      |

```powershell
# Expand all placeholder paths for the PC machine type
$paths = Expand-ConfigPaths -Configuration $Configuration -MachineType "PC"
```

**See also:** [Expand-Hashtable](#expand-hashtable), [Merge-Hashtable](#merge-hashtable)

## [Expand-Hashtable](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Expand-Hashtable.ps1)

- **Description:** Recursively walks a hashtable (or nested array, list, or string) and replaces placeholder tokens with actual values: `{Dev}` -> development path, `{User}` -> user path, `{MachineType}` -> machine type name, `{RepoRoot}` -> WinuX repository root, and `{AppData}` / `%APPDATA%` / `%ALLUSERSPROFILE%` / `%LOCALAPPDATA%` -> their environment paths. Also converts Windows paths to WSL `/mnt/...` paths when the original string contains forward slashes. Non-placeholder tokens pass through unchanged. Used internally by `Expand-ConfigPaths`; rarely called directly.
- **Parameters:** -Source, -DevPath, -UserPath, -MachineTypeName, -RepoRoot
- **Usage:** `Expand-Hashtable -Source $config -DevPath "<DevRoot>" -UserPath "C:\Users\<User>" -MachineTypeName "MyMachine"`

Recurses into nested hashtables and `IList` collections, expanding every string value it encounters while preserving structure and null entries. If `-RepoRoot` is omitted, it is inferred from `Source.Projects.Self.Root` (with `{Dev}` resolved first). When a source string contains a forward slash and expands to a Windows drive path, it is rewritten to the equivalent WSL mount path (for example `C:\foo` becomes `/mnt/c/foo`).

| Parameter          | Description                                                                                   |
| ------------------ | --------------------------------------------------------------------------------------------- |
| `-Source`          | The hashtable, array/list, string, or value to expand. May be deeply nested. (Mandatory)      |
| `-DevPath`         | Development directory path substituted for `{Dev}`. (Mandatory)                               |
| `-UserPath`        | User directory path substituted for `{User}`. (Mandatory)                                     |
| `-MachineTypeName` | Machine type name substituted for `{MachineType}`. (Mandatory)                                |
| `-RepoRoot`        | Optional WinuX root for `{RepoRoot}`. Inferred from `Source.Projects.Self.Root` when omitted. |

```powershell
# Expand all placeholder tokens in a config hashtable
$expanded = Expand-Hashtable -Source $config -DevPath "<DevRoot>" -UserPath "C:\Users\<User>" -MachineTypeName "MyMachine"
```

## [Import-AppCsv](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Import-AppCsv.ps1)

- **Description:** The single read path for the three app lists. Parses the committed CSV named by `BootstrapConfig.DataFiles`, layers the sibling machine-local `<name>.local.csv` over it when one exists, and returns the combined active rows. It is for app lists exactly what `Configuration.local.psd1` is for settings: the committed CSV stays the shipped baseline upstream can keep improving, everything a person chose for this machine lives in the overlay beside it, so a fork never has to edit a tracked CSV and pulling upstream never conflicts on one.
- **Parameters:** -DataFileKey, -RepoRoot
- **Usage:** `Import-AppCsv -DataFileKey WinGetApps`, `Import-AppCsv -DataFileKey ScoopApps | Where-Object { $_.Global -eq 'true' }`

Called by `Install-WinGetApps`, `Install-ScoopApps`, `Install-ChocolateyApps` and `Get-PinnedApps` in place of a plain `Import-Csv`, so every reader sees the same effective list and the comment-and-blank-row filtering each of them used to do individually now lives in one place.

Layering rules:

| Overlay row                        | Effect                                                                                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `App` matches a base row           | **Replaces** that row in place, which is what lets the overlay pin a version, change the install scope, or re-target a machine without touching the base.      |
| `App` is new                       | **Added**, after the committed rows.                                                                                                                          |
| `App` is `-<id>`                   | **Removes** the matching base row. Without this there would be no way to opt out of a shipped app, since a layer that can only add or replace cannot subtract. |
| `App` starts with `#`, or is blank | Dropped, in the committed file and the overlay alike.                                                                                                          |

Matching is **case-insensitive**, because package ids are. Row order is base-first, then overlay-only additions, so the shipped install order is preserved and this machine's own apps follow it. A row whose `App` still carries the `-` marker is never returned - the marker is an instruction, not a package id. When an overlay both removes and replaces the same `App`, the **removal wins**, whichever order the two rows appear in.

A missing overlay is the normal case and is **not** an error; most machines never write one. A missing **base** file is an error, since it is a tracked file the repository is supposed to ship.

| Parameter      | Type   | Required | Description                                                                                                                                                                                                       |
| -------------- | ------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-DataFileKey` | String | Yes      | Which list to read: `WinGetApps`, `ScoopApps` or `ChocolateyApps`. Resolved through `BootstrapConfig.DataFiles`, so the location stays configuration-driven. Anything outside that set is rejected by `ValidateSet`. |
| `-RepoRoot`    | String | No       | Repository root the relative data-file path is resolved against. Defaults to `$global:MachineSpecificPaths.Projects.Self.Root`.                                                                                     |

```powershell
# The active WinGet rows, with any machine-local overlay applied
Import-AppCsv -DataFileKey WinGetApps

# Filter the combined list exactly as a plain Import-Csv result would be filtered
Import-AppCsv -DataFileKey ScoopApps | Where-Object { $_.Global -eq 'true' }
```

> [!IMPORTANT]
> The column header must be **line 1** of the committed file and of the overlay, with any commentary after it. `Import-Csv` takes line 1 as the header unconditionally, so a leading comment line becomes the header and every real row then parses under a bogus column name with an empty `App` - which this function's own blank-`App` filter would then silently discard.

This function only reads. [Save-AppCsvOverlay](configuration.md#save-appcsvoverlay) writes the overlay, and the committed CSV is never modified by either.

**See also:** [Save-AppCsvOverlay](configuration.md#save-appcsvoverlay), [Software List: Machine-Local Overlay](../reference/software-list.md#machine-local-overlay), [Test-MachineTypeScope](#test-machinetypescope), [Fork Model](../contributing/fork-model.md)

## [Initialize-Configuration](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Initialize-Configuration.ps1)

- **Description:** First-run writer that captures your personal identity and paths into a sibling `Configuration.local.psd1` override - never into the committed `Configuration.psd1`. WinuX ships a generic base config (blank Git identity, placeholder paths) and commits no personal data; this function writes only the keys that differ - `GitConfig.UserName`/`UserEmail`, the `BasePaths.<MachineType>` `{Dev}`/`{User}` roots, and this machine's `HostnameToMachineType` entry - which `Load-PathConfiguration` deep-merges over the base at load time. Because the base file is never edited, pulling upstream updates into a fork never conflicts on configuration. Validates that the generated override parses before writing, and does nothing if the override already has a Git identity unless `-Force` is given.
- **Parameters:** -Owner, -GitName, -GitEmail, -DevPath, -MachineType, -ConfigPath, -LocalConfigPath, -Force
- **Usage:** `Initialize-Configuration`, `Initialize-Configuration -GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"`

Run once after cloning to make WinuX yours. Any value not passed as a parameter is requested interactively; in a non-interactive session missing values fall back to sensible defaults (your `%USERNAME%`, `%USERPROFILE%\Development\GitHub`) instead of prompting, so automated runs never block. The override file is gitignored by WinuX - keep it on your machine or in your own fork; your Git email never lands in the WinuX repository. See the [Fork Model](../contributing/fork-model.md) for how this override keeps a personal fork conflict-free.

| Parameter          | Type   | Required | Description                                                                            |
| ------------------ | ------ | -------- | -------------------------------------------------------------------------------------- |
| `-Owner`           | String | No       | Your GitHub username/owner; defaults the Git name and informs the prompts.             |
| `-GitName`         | String | No       | Git `user.name` written into `GitConfig.UserName`.                                     |
| `-GitEmail`        | String | No       | Git `user.email` written into `GitConfig.UserEmail` (local override only).             |
| `-DevPath`         | String | No       | Development root for the `{Dev}` placeholder (e.g. `C:\Users\You\Development\GitHub`). |
| `-MachineType`     | String | No       | Machine type to map this hostname to and set `BasePaths` for. Defaults to `Test`.      |
| `-ConfigPath`      | String | No       | Path to the base `Configuration.psd1`; used only to locate the override beside it.     |
| `-LocalConfigPath` | String | No       | Path to the override file to write. Defaults to `Configuration.local.psd1` beside it.  |
| `-Force`           | Switch | No       | Rewrite the override even if the Git identity is already populated.                    |

```powershell
# Interactive first run: prompts for owner, Git name/email, and dev path
Initialize-Configuration

# Non-interactive: supply everything up front (nothing is prompted)
Initialize-Configuration -GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"
```

## [Install-Bootstrap](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1)

- **Description:** The self-contained Stage 1 first-run script. Ensures PowerShell 7 is installed (relaunching as Administrator if needed), installs and configures Git, clones the WinuX repository for the specified branch, resolves your Git identity from the cloned configuration, then imports the full Bootstrap module and hands off to `Bootstrap -WithInitialSetup`.
- **Parameters:** -Branch, -Token
- **Usage:** `Install-Bootstrap`, `Install-Bootstrap -Branch master`, `irm '.../Install-Bootstrap.ps1' -Headers @{ Authorization = "Bearer $Pat" } | iex`

`Install-Bootstrap` is the entry point of WinuX's two-stage bootstrap, downloaded and piped to `Invoke-Expression` via a one-liner on a fresh machine. It solves the chicken-and-egg problem where no modules yet exist by inlining the essential helper functions (`Loading-Spinner`, `Install-Git`, `Initialize-Repository`, and others) it needs to get the system to a usable state. The script ensures PowerShell 7 is present, relaunching itself elevated in `pwsh` and carrying the GitHub token across the relaunch when started under Windows PowerShell. It installs and configures Git, clones the WinuX repository (checking out `-Branch` if it differs from `master`), resolves your Git identity from the clone's committed configuration (falling back to `WINUX_GIT_*`, the existing global git config, or a prompt), imports the full Bootstrap module from the clone, and finally invokes `Bootstrap -RepoRoot <clone> -WithInitialSetup` to enter Stage 2.

| Parameter | Type         | Description                                                                                                                                       |
| --------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-Branch` | String       | Branch to clone and check out. Defaults to `master`. Populated from `$env:WINUX_BRANCH` by the trailing invocation when set.                      |
| `-Token`  | SecureString | GitHub Personal Access Token used to authenticate the clone of the private repository. Cached into `$global:GithubPat` for the elevated relaunch. |

```powershell
# Public repo: no token needed
irm 'https://raw.githubusercontent.com/IvanPavlak/WinuX/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1' | iex

# Private repo: pass a PAT as a Bearer header (fetches the script and clones)
$Headers = @{ Authorization = "Bearer $Pat" }
irm 'https://raw.githubusercontent.com/<owner>/<repo>/master/Windows/PowerShell/Modules/Bootstrap/Install-Bootstrap.ps1' -Headers $Headers | iex

# Bootstrap from a non-default branch (set before downloading the script)
$env:WINUX_BRANCH = 'OtherBranch'
```

**See also:** [Getting Started: First Run](../getting-started/first-run.md), [Getting Started: Installation](../getting-started/installation.md)

## [Install-WinGetPackageManager](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Install-WinGetPackageManager.ps1)

- **Description:** Installs the WinGet package manager if it is not already present. Checks whether the `winget` command is available; if so, reports the current version and returns. Otherwise it installs the community `winget-install` script from the PowerShell Gallery via `Install-Script` and runs it to provision WinGet.
- **Usage:** `Install-WinGetPackageManager`

Invoked automatically by Bootstrap as the first of the package-manager setup steps.

```powershell
# Install WinGet, or report that it is already installed
Install-WinGetPackageManager
```

## [Invoke-PersonalSteps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Invoke-PersonalSteps.ps1)

- **Description:** Runs the fork-defined personal install steps from `BootstrapConfig.PersonalSteps`. Each entry is either a plain function name (runs on every machine type) or `@{ Function = "Name"; Machine = "PC/Laptop" }` gated per machine type exactly like the app CSVs' `Machine` column, with scope tokens validated via `Test-MachineTypeScope`. Entries without a `Function` name and entries that do not resolve to an exported command are skipped with a warning; out-of-scope entries are skipped silently. When nothing applies - the list is empty (the base config ships it empty) or every entry is gated to other machine types - it reports so with a warning naming the current machine type. Requires administrator privileges (asserted up front via `Test-AdminPrivileges`, so a non-elevated run fails fast instead of mid-step). Called automatically by `Bootstrap` right after `Upgrade-All`.
- **Usage:** `Invoke-PersonalSteps`

```powershell
# Run every configured personal step applicable to the current machine type
Invoke-PersonalSteps
```

**See also:** [Test-MachineTypeScope](#test-machinetypescope)

## [Load-PathConfiguration](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Load-PathConfiguration.ps1)

- **Description:** Loads `Configuration.psd1`, detects the machine type, expands path placeholders, and registers the custom Modules directory for autoload. Called automatically by the PowerShell profile on every shell start and by Bootstrap during provisioning; not intended for direct invocation in normal use.
- **Parameters:** -RepoRoot, -Configuration, -Quiet
- **Usage:** `Load-PathConfiguration -RepoRoot "C:\Users\<User>\Development\GitHub\WinuX"`, `Load-PathConfiguration -RepoRoot $path -Quiet`

This is the single function that brings the entire WinuX system online. It reads the provided `$Configuration` hashtable (or imports `Configuration.psd1` from disk via `Import-PowerShellDataFile` when omitted), looks up `$env:COMPUTERNAME` in the `HostnameToMachineType` mapping, and falls back **silently** to `DefaultMachineType` when the hostname is not mapped - so profile loading never blocks on user input. It ensures the `Modules\` folder is in `$env:PSModulePath` for first-use autoload, then expands the `Universal` section with `Expand-Hashtable` and resolves all placeholder paths via `Expand-ConfigPaths` (both are Bootstrap functions, so this no longer autoloads any other module). Returns `$true` on success and `$false` on failure.

On a successful load it sets three global variables:

- `$global:Configuration` - full configuration hashtable with `Universal` paths expanded
- `$global:MachineType` - detected machine type (PC, Laptop, Work, Test)
- `$global:MachineSpecificPaths` - all PathTemplate paths expanded for the current machine

| Parameter        | Type      | Required | Description                                                                                                                                                 |
| ---------------- | --------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-RepoRoot`      | String    | Yes      | Absolute path to the WinuX repository root. Used to locate `Windows\PowerShell\Configuration.psd1` and the `Modules\` folder.                               |
| `-Configuration` | Hashtable | No       | An already-parsed configuration hashtable. When provided, skips re-reading the file from disk (Bootstrap and the profile use this to avoid a second parse). |
| `-Quiet`         | Switch    | No       | Suppresses all console output. Used when loading configuration in background or startup contexts.                                                           |

```powershell
# Called automatically by the profile, but can be run manually
Load-PathConfiguration -RepoRoot "C:\Users\<User>\Development\GitHub\WinuX"

# Load silently, reusing an already-parsed configuration
Load-PathConfiguration -RepoRoot $path -Configuration $global:Configuration -Quiet

# Verify loaded configuration
$global:MachineType                              # e.g. "PC"
$global:MachineSpecificPaths.Projects.Self   # Expanded paths
```

**See also:** [DetermineMachineType](bootstrap.md) (interactive machine-type prompt used during Bootstrap)

## [Merge-Hashtable](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Merge-Hashtable.ps1)

- **Description:** Recursively merges override values into a target hashtable (by reference). When both the target and override hold a hashtable for the same key, those nested hashtables are merged recursively; otherwise the override value replaces the target value. Used by `Expand-ConfigPaths` to apply machine-specific configuration overrides.
- **Parameters:** -Target, -Overrides
- **Usage:** `Merge-Hashtable -Target $config -Overrides $overrides`

| Parameter    | Description                                                                           |
| ------------ | ------------------------------------------------------------------------------------- |
| `-Target`    | The target hashtable to modify (passed by reference and mutated in place). Mandatory. |
| `-Overrides` | The overrides hashtable whose values are merged into `-Target`. Mandatory.            |

```powershell
# Deep merge: nested hashtables are combined, scalar values are replaced
$config    = @{ Dev = "<DevRoot>"; Projects = @{ Path = "<DevRoot>\MyProject" } }
$overrides = @{ Projects = @{ Path = "C:\Users\<User>\MyProject" } }
Merge-Hashtable -Target $config -Overrides $overrides
# $config now has Dev = "<DevRoot>", Projects.Path = "C:\Users\<User>\MyProject" (deeply merged)
```

**See also:** [Expand-ConfigPaths](#expand-configpaths)

## [Resolve-BootstrapSteps](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Resolve-BootstrapSteps.ps1)

- **Description:** Resolves which Bootstrap provisioning steps should run, in a single pass. A thin wrapper over the Helper module's generic [Resolve-Steps](helper.md#resolve-steps): per step, `-Skip` beats `-Include` beats config (`BootstrapConfig.Steps.<Name>` in `$global:Configuration` - a plain boolean, or a per-machine-type hashtable with a `Default` fallback) beats the built-in defaults. Returns an ordered hashtable of step name → boolean, in Bootstrap execution order. `Bootstrap` calls this exactly once per invocation; the only side effect is a warning per step that appears in both `-Skip` and `-Include` (the step is skipped), so it is also safe to call ad hoc to inspect what a Bootstrap invocation would do with the current config.
- **Parameters:** -Skip (step names forced off), -Include (step names forced on)
- **Usage:** `Resolve-BootstrapSteps`, `Resolve-BootstrapSteps -Skip UpgradeAll, WSL`

Step names, in execution order: `RenameMachine`, `MicrosoftActivationScripts`, `Win11Debloat` (these three only run with `-WithInitialSetup`), `ExecutionPolicy`, `DeveloperMode`, `PowerPlan`, `PowerButtonActions`, `SystemTheme`, `Locale`, `DisplayLanguage`, `KeyboardLayouts`, `NerdFont`, `PowerShellModules`, `SpecialFolders`, `WSL`, `WinGetApps`, `ScoopApps`, `ChocolateyApps`, `UpgradeAll`, `DotnetEf`, `EnvironmentVariables`, `CondaEnvironments`, `NuGetConfig`, `Taskbar`, `SymbolicLinks`, `CoreAiRules`, `LockedStartLayout`.

Most steps default **on**, because their functions no-op when their configuration section is empty - an enabled step on the empty base config applies nothing. The opt-in exceptions default **off**, because they have no configuration to be empty and act the moment they run: `MicrosoftActivationScripts`, `Win11Debloat`, `DeveloperMode`, `NuGetConfig` (prompts for a GitHub PAT), `CoreAiRules` (machine-global AI agent policy - see [CoreAiRules](../ai/coreairules.md)), and `LockedStartLayout`. Repository updates are deliberately not a step - they are governed by `BootstrapConfig.RepositoryUpdateScope` (`"None"` is its off switch).

**Deprecated:** the old `BootstrapConfig.WSLSetup` key (same shape as a `Steps` value) is still honored as a fallback when `Steps` carries no `WSL` entry, so forks that predate `Steps` keep working unmodified. The `PromptForActivation` / `PromptForDebloat` keys are gone entirely - MAS and Win11Debloat no longer prompt on a vanilla install and are opted into via `Steps`.

| Parameter  | Type       | Default | Description                                                      |
| ---------- | ---------- | ------- | ----------------------------------------------------------------- |
| `-Skip`    | `string[]` | -       | Step names forced off for this invocation; wins over `-Include`. |
| `-Include` | `string[]` | -       | Step names forced on for this invocation, overriding config.     |

```powershell
# What would a parameterless Bootstrap do with the current config?
Resolve-BootstrapSteps

# Parameter override beats a config-disabled step
Resolve-BootstrapSteps -Include Win11Debloat
```

**See also:** [Bootstrap](#bootstrap), [Resolve-Steps](helper.md#resolve-steps), [Configuration Reference: BootstrapConfig](../configuration/configuration-reference.md#bootstrapconfig)

## [Resolve-PackageManagers](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Resolve-PackageManagers.ps1)

- **Description:** The single gate deciding which of WinGet, Scoop and Chocolatey WinuX installs and upgrades. Returns the managers in play, in canonical spelling and canonical order (WinGet, Scoop, Chocolatey - the order Bootstrap installs them in), so callers can switch on the returned strings directly. Consumed by [`Bootstrap`](#bootstrap) and [`Upgrade-All`](system.md#upgrade-all).
- **Parameters:** -PackageManager (explicit override), -MachineType
- **Usage:** `Resolve-PackageManagers`, `Resolve-PackageManagers -PackageManager "Chocolatey"`

A manager is in play when **both** conditions hold:

- It is listed in `PackageManagers` in `Configuration.psd1`. That list is the opt-in: a manager absent from it is never installed and never upgraded.
- Its effective app list holds at least one row applicable to this machine type. The list is read through [`Import-AppCsv`](#import-appcsv), so the machine-local `<name>.local.csv` overlay counts, and each row's `Machine` column is checked with [`Test-MachineTypeScope`](#test-machinetypescope), so a manager whose only apps target other machines counts as empty.

The second condition is what keeps a package manager off a machine that has no use for it. Installing one is not free - it is a download, a PATH entry and a shim directory that then sit there managing nothing - and the base Scoop and Chocolatey lists ship empty, so a vanilla bootstrap used to install two managers for zero apps. Deriving it from the data rather than from the list alone also means the two cannot drift: a fork that empties its Scoop overlay stops installing Scoop without having to remember to also edit `PackageManagers`.

Unknown entries are reported through `Write-LogError` with the valid values, the same way `Test-MachineTypeScope` reports a misspelled machine scope, so a typo like `"Chocolatley"` is surfaced instead of silently dropping a manager. An empty `PackageManagers` returns nothing with a warning.

| Parameter          | Type       | Default               | Description                                                                                                                                    |
| ------------------ | ---------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `-PackageManager`  | `string[]` | -                     | Explicit manager(s) to use instead of resolving from configuration. Honoured as given - neither the opt-in list nor the empty-list check applies. Backs `Upgrade-All -PackageManager`. |
| `-MachineType`     | `string`   | `$global:MachineType` | Machine type the app lists are filtered against.                                                                                               |

```powershell
# What would Bootstrap install on this machine?
Resolve-PackageManagers

# Base configuration => WinGet alone (Scoop and Chocolatey ship empty lists)
```

**See also:** [Bootstrap](#bootstrap), [Import-AppCsv](#import-appcsv), [Test-MachineTypeScope](#test-machinetypescope), [Upgrade-All](system.md#upgrade-all), [Configuration Reference: PackageManagers](../configuration/configuration-reference.md#packagemanagers)

## [Test-MachineTypeScope](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Bootstrap/Functions/Test-MachineTypeScope.ps1)

- **Description:** Tests whether a machine-scope string (`All`, `PC`, `PC/Laptop`, ...) applies to a machine type, validating every token against `ValidMachineTypes` plus the `All` wildcard. Unknown tokens - e.g. a `Labtop` typo - are reported via `Write-LogError` together with the valid values and contribute nothing to the match, so a misspelled scope can never silently install or skip anything. Matching is case-insensitive. The single gate behind the app CSVs' `Machine` column (`Install-WingetApps`, `Install-ScoopApps`, `Install-ChocolateyApps`) and `BootstrapConfig.PersonalSteps` entries (via `Invoke-PersonalSteps`).
- **Parameters:** -Scope, -MachineType, -Context
- **Usage:** `Test-MachineTypeScope -Scope "PC/Laptop" -MachineType "Laptop"`

| Parameter      | Description                                                                                                     |
| -------------- | --------------------------------------------------------------------------------------------------------------- |
| `-Scope`       | Machine-scope string: machine types separated by `/`, or `All`. A blank scope is reported and never matches.    |
| `-MachineType` | Machine type to test the scope against. Defaults to `$global:MachineType`; when empty, only `All` scopes match. |
| `-Context`     | Optional data-source label (e.g. `WinGetApps.csv [Git.Git]`) included in error messages for instant diagnosis.  |

```powershell
# True - the scope covers Laptop
Test-MachineTypeScope -Scope "PC/Laptop" -MachineType "Laptop"

# False, and reports the unknown token [Labtop] with the list of valid values
Test-MachineTypeScope -Scope "Labtop" -MachineType "Laptop" -Context "WinGetApps.csv [MyApp]"
```

**See also:** [DetermineMachineType](#determinemachinetype)

## Two-Stage Architecture

WinuX uses a two-stage bootstrap to solve the chicken-and-egg problem - on a fresh machine, no modules exist yet:

```
┌─────────────────────────────────────────────────────────────────────────┐
│  STAGE 1: Install-Bootstrap.ps1 (self-contained first-run script)       │
├─────────────────────────────────────────────────────────────────────────┤
│  • Fetched via a one-liner or WinuX.exe (WinuX.ps1 entry point)         │
│  • Contains inline copies of essential functions                        │
│    (Loading-Spinner, Install-Git, Initialize-Repository, etc.)          │
│  • Ensures PowerShell 7 is installed (relaunches as admin if needed)    │
│  • Clones the WinuX repository                                          │
│  • Imports the full Bootstrap module from the cloned repo               │
│  • Calls Bootstrap -WithInitialSetup to hand off to Stage 2             │
├─────────────────────────────────────────────────────────────────────────┤
│  STAGE 2: Bootstrap function (full module system)                       │
├─────────────────────────────────────────────────────────────────────────┤
│  • All modules are available                                            │
│  • Runs the complete setup sequence (see Execution Flow below)          │
│  • Can be re-run anytime: Bootstrap (without -WithInitialSetup)         │
└─────────────────────────────────────────────────────────────────────────┘
```

### WinuX.ps1 Entry Point

`Windows/WinuX/WinuX.ps1` is the installer entry point and the source compiled into `WinuX.exe` - the double-clickable installer that `.github/workflows/release.yml` builds (via `Windows/WinuX/New-WinuXExecutable.ps1`) and attaches to every tagged GitHub release. The binary itself is gitignored, never committed - `releases/latest/download/WinuX.exe` always serves the newest build (see `Windows/WinuX/ExecutableCreation.md`).

It stays Windows PowerShell 5.1-compatible (the engine ps2exe-compiled executables host) and decides by **where it runs**:

- **Standalone** (a fresh machine): forces TLS 1.2, resolves the repository from `WINUX_REPO_URL` (default: the public WinuX repository), downloads `Install-Bootstrap.ps1` **anonymously**, and pipes it to `Invoke-Expression`. When the anonymous download fails (a **private** repository or fork), it prompts for a GitHub PAT, retries with a `Bearer` header, and keeps the PAT as a `SecureString` in `$Token` - which `Install-Bootstrap`'s trailing invocation picks up for the authenticated clone, exactly like the documented private one-liner.
- **Inside a clone** (`<root>\Windows\WinuX\`): skips the download entirely and relaunches an elevated PowerShell 7 that imports the clone's Bootstrap module and runs `Bootstrap -WithInitialSetup` - the same reprovisioning `Install-Bootstrap` ends with.

To install a **fork**, a **private** repository (with a PAT), or a specific **branch**, either set `WINUX_REPO_URL` / `WINUX_BRANCH` before launching the script/executable, or use the parameterized `Install-Bootstrap.ps1` one-liners in [Installation](../getting-started/installation.md).

## SymbolicLinkMaker (System Module)

`SymbolicLinkMaker` is defined in the [System Module](system.md) but is a key part of the bootstrap flow. It creates all configured symbolic links from the WinuX repository.

```
Configuration.psd1 → SymbolicLinks = @{
    Git = @{
        Path   = "{User}\.gitconfig"          # Created here
        Target = "{RepoRoot}\Git\.gitconfig" # Points to this
    }
}

Result: C:\Users\<User>\.gitconfig → WinuX\Git\.gitconfig
```

| Path Type                | Handler                           |
| ------------------------ | --------------------------------- |
| Windows paths (`C:\...`) | `New-Item -ItemType SymbolicLink` |
| WSL paths (`/home/...`)  | `wsl ln -sf`                      |
| Nested configs           | Recursive processing              |

See [Add Symbolic Link Guide](../configuration/guides/system/add-symbolic-link.md) for details.

## Profile Initialization

When PowerShell starts, `Microsoft.PowerShell_profile.ps1` runs:

```
┌─────────────────────────────────────────────────────────────────┐
│  Profile Startup                                                │
├─────────────────────────────────────────────────────────────────┤
│  1. Minimal Bootstrap                                           │
│     ├─→ Import Configuration.psd1 → $global:Configuration       │
│     ├─→ Determine MachineType from $env:COMPUTERNAME            │
│     ├─→ Build modules path, add to $env:PSModulePath            │
│     └─→ Import Bootstrap module                                 │
│                                                                 │
│  2. Load-PathConfiguration -Configuration $global:Configuration │
│     ├─→ Reuses pre-loaded config (no second file read)          │
│     ├─→ Registers Modules/ in PSModulePath for autoload         │
│     ├─→ Expands placeholders → $global:MachineSpecificPaths     │
│     └─→ Sets $global:Configuration, $global:MachineType         │
│                                                                 │
│  3. Console Enhancement                                         │
│     ├─→ Oh-My-Posh (WinuX_{MachineType}.omp.json theme)         │
│     ├─→ FastFetch (system info display)                         │
│     ├─→ PSReadLine (history, predictions, key bindings)         │
│     └─→ Terminal-Icons (file/folder icons)                      │
│                                                                 │
│  4. Register Aliases                                            │
│     ├─→ Git: gb, gbd, gsw, gp, gmm, gs, gdf                     │
│     ├─→ Workflow: w, b, efm, rp, t                              │
│     └─→ Dev tools: dnr, dnbr, dnp, nir, c, l                    │
│                                                                 │
│  5. Startup Checks                                              │
│     └─→ Test-PowerPlan (dot-sourced directly, no module import) │
└─────────────────────────────────────────────────────────────────┘
```

> [!NOTE]
> WinuX modules are **not imported at startup**. Each `.psd1` manifest declares `FunctionsToExport`, enabling PowerShell autoload. A module loads automatically the first time one of its exported functions is called - keeping shell startup fast. This includes the fork-owned `Custom` module, which autoloads via its own `FunctionsToExport` (maintained by the fork, empty upstream - see [Fork Model: the Custom area](../contributing/fork-model.md)). The one exception is `Bootstrap`, which is imported explicitly (its `Expand-Hashtable` / `Expand-ConfigPaths` functions perform path expansion in `Load-PathConfiguration`).

> [!NOTE]
> `Test-PowerPlan` is dot-sourced directly from its `.ps1` file rather than importing the entire `System` module at startup. This avoids loading ~46 system functions just for one startup check.

### Global Variables After Initialization

| Variable                       | Description             | Example   |
| ------------------------------ | ----------------------- | --------- |
| `$global:MachineType`          | Current machine type    | `"PC"`    |
| `$global:MachineSpecificPaths` | Expanded path templates | Hashtable |
| `$global:Configuration`        | Raw configuration       | Hashtable |

### Accessing Configuration

```powershell
# Machine type
$MachineType
# Output: PC

# Specific project path
$MachineSpecificPaths.Projects.Self.Root
# Output: C:\Users\<User>\Development\GitHub\WinuX

# Configuration value
$Configuration.Themes[$MachineType]
# Output: Dark

# List all projects
$Configuration.Projects
# Output: @("MyProject", "OtherProject", "ThirdProject", ...)
```

## Data Files

Bootstrap uses CSV files for package definitions:

| File                 | Location                  | Purpose             |
| -------------------- | ------------------------- | ------------------- |
| `WinGetApps.csv`     | `Modules/Bootstrap/Data/` | WinGet packages     |
| `ScoopApps.csv`      | `Modules/Bootstrap/Data/` | Scoop packages      |
| `ChocolateyApps.csv` | `Modules/Bootstrap/Data/` | Chocolatey packages |

Each of the three may have a machine-local `<name>.local.csv` beside it, which [Import-AppCsv](#import-appcsv) layers over the committed list and [Save-AppCsvOverlay](configuration.md#save-appcsvoverlay) writes. Nothing ever edits the committed CSV, so a fork's own app choices never touch a tracked file and upstream can keep improving the baseline. WinuX gitignores the overlays, exactly as it gitignores `Configuration.local.psd1`. See [Software List: Machine-Local Overlay](../reference/software-list.md#machine-local-overlay).

### WinGetApps.csv Format

```csv
App,Version,Scope,Interactive,Source,Machine
Microsoft.PowerShell,Latest,d,n,w,All
Microsoft.WindowsTerminal,Latest,d,n,w,All
Microsoft.PowerToys,0.100.2,d,n,w,All
```

| Column      | Values                       | Description               |
| ----------- | ---------------------------- | ------------------------- |
| App         | Package ID                   | WinGet package identifier |
| Version     | Latest / 1.2.3               | Version to install        |
| Scope       | d/m/u                        | default, machine, user    |
| Interactive | y/n                          | Requires user interaction |
| Source      | w/s                          | winget, msstore           |
| Machine     | All/PC/Laptop/Work/PC/Laptop | Target machines           |
