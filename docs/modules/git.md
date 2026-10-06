# Git Module

The Git module provides **repository management**, **Git workflow automation**, and **common Git operations**.

## [Format-RepositoryUpdateResult](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Format-RepositoryUpdateResult.ps1)

- **Description:** Turns one repository update result (what `Update-Repository` returns, or what `Update-Repositories` records for a repository it cloned or skipped) into the one-line summary `Update-Repositories -Quiet` prints. Returns the message, the level to print it at (`Success` or `Warning`) and the totals bucket it counts towards (`Updated`, `UpToDate`, `Attention` or `Skipped`). Pure: it prints nothing. Whenever the default branch differs from the checked-out one, the line says what happened to it (`master up to date`, `master fast-forwarded`, `no local master`), so silence never has to be interpreted. A result needs attention when the fetch failed, the pull could not fast-forward, local changes could not be stashed or restored, an error occurred, or the default branch diverged, could not be fetched or could not be named.
- **Parameters:** -Result
- **Usage:** `Format-RepositoryUpdateResult -Result (Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo" -Quiet)`

```powershell
# The line Update-Repositories -Quiet would print for one repository
Format-RepositoryUpdateResult -Result (Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo" -IncludeDefaultBranch -Quiet)
# [MyRepo] feature/login - updated, master fast-forwarded
```

**See also:** [Update-Repositories](#update-repositories), [Update-Repository](#update-repository)

## [Git-Diff](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Git-Diff.ps1)

- **Description:** Shows the diff between the working tree and the last commit. Runs `git diff HEAD` to display all unstaged and staged changes relative to HEAD.
- **Usage:** `Git-Diff`
- **Alias:** gdf

## [Git-Obsidian](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Git-Obsidian.ps1)

- **Description:** Commits and pushes all pending changes in the Obsidian vault repository, providing a quick vault backup to GitHub without opening Obsidian.
- **Usage:** `Git-Obsidian`

Navigates to the Obsidian vault directory (`$MachineSpecificPaths.ObsidianDirectory`) and brings the remote up to date with the vault. If the working tree has changes, it stages everything with `git add .` and creates a commit with the message `"Vault Backup: dd.MM.yyyy | HH:mm"`. It then counts the commits the branch has that its upstream does not (`git rev-list --count @{upstream}..HEAD`) - the commit just made plus anything an earlier run left behind when its push failed - and pushes when that count is not zero. Only when the tree is clean **and** nothing is unpushed does it report `No changes to update!`. The original working directory is always restored on exit.

Success is reported only when `git push` actually exited 0. A failed commit or push is logged as an error together with the state the vault is left in (`Push failed - the vault is committed locally but the remote was not updated!`), and the next run pushes the pending commits (`Found [1] unpushed commit(s) from an earlier run. Pushing...`) instead of looking at the clean tree and reporting that nothing changed. If the branch has no upstream, the function still attempts the push so that git reports the cause rather than the function hiding it behind `No changes`.

```powershell
# Commit and push any pending vault changes, push commits an earlier failed
# run left behind, or report that nothing changed
Git-Obsidian
```

**See also:** [Configuration: Add Repository](../configuration/guides/git/add-new-repository.md)

## [GitBranch](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/GitBranch.ps1)

- **Description:** Creates a new branch or lists all branches. When called with a branch name, creates that branch with `git branch <name>`. When called with no argument, lists all local and remote branches with verbose output via `git branch -v -a`.
- **Parameters:** -BranchName
- **Usage:** `GitBranch`, `GitBranch feature/my-feature`
- **Alias:** gb

| Parameter     | Description                                                               |
| ------------- | ------------------------------------------------------------------------- |
| `-BranchName` | Name of the branch to create. Omit to list all local and remote branches. |

```powershell
# List all local and remote branches (git branch -v -a)
GitBranch
gb

# Create a new branch
GitBranch feature/my-feature
gb feature/my-feature
```

**See also:** [GitSwitch](git.md), [GitBranchDeleteAndPrune](git.md)

## [GitBranchDeleteAndPrune](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/GitBranchDeleteAndPrune.ps1)

- **Description:** Force-deletes a local branch and prunes stale remote-tracking refs for origin. Runs `git branch -D <BranchName>` to remove the specified local branch, then `git remote prune origin` to clear any remote-tracking refs that no longer exist on the remote.
- **Parameters:** -BranchName
- **Usage:** `GitBranchDeleteAndPrune feature/done`, `GitBranchDeleteAndPrune -BranchName "feature/done"`
- **Alias:** gbd

| Parameter     | Description                         |
| ------------- | ----------------------------------- |
| `-BranchName` | Name of the local branch to delete. |

```powershell
# Force-delete a local branch and prune stale origin refs
GitBranchDeleteAndPrune feature/done

# Deletes the local branch with git branch -D
# Then runs git remote prune origin to drop stale remote-tracking refs
```

## [GitMergeM](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/GitMergeM.ps1)

- **Description:** Merges the default branch into the current branch. Checks whether a `master` or `main` branch exists in the repository (in that order) and merges it into the currently checked-out branch. Reports an error if neither branch is found.
- **Usage:** `GitMergeM`
- **Alias:** gmm

```powershell
# Merge master (or main, if master is absent) into the current branch
GitMergeM
```

## [GitPull](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/GitPull.ps1)

- **Description:** Pulls the latest changes from the remote for the current branch by running `git pull`, forwarding any additional arguments straight to git.
- **Usage:** `GitPull`, `gp`
- **Alias:** gp

## [GitStatus](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/GitStatus.ps1)

- **Description:** Shows the working tree status with verbose output. Runs `git status -v -v -u`, which displays the full diff of staged changes (`-v -v`) and all untracked files (`-u`). Any additional arguments are forwarded to `git`.
- **Usage:** `GitStatus`, `gs`
- **Alias:** gs

```powershell
# Full working tree status with staged diffs and untracked files
GitStatus

# Same, using the alias
gs
```

## [GitSwitch](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/GitSwitch.ps1)

- **Description:** Switches to the specified branch using `git switch`. Called with no argument, it switches to the default branch, preferring `master` and falling back to `main`. Reports an error if the named branch (or, in the no-argument case, neither default branch) does not exist.
- **Parameters:** -BranchName
- **Usage:** `GitSwitch`, `GitSwitch feature/my-feature`, `GitSwitch -BranchName feature/my-feature`
- **Alias:** gsw

| Parameter     | Description                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------------- |
| `-BranchName` | Name of the branch to switch to. Omit to switch to the default branch (`master`, otherwise `main`). |

```powershell
# Switch to the default branch (master if it exists, otherwise main)
GitSwitch

# Switch to a named branch (errors if it does not exist)
GitSwitch feature/my-feature

# Same, using the alias
gsw feature/my-feature
```

## [Initialize-Repository](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Initialize-Repository.ps1)

- **Description:** Clones a repository to a local path, or pulls the latest changes if it already exists there. When a `Token` is provided, it is injected into the HTTPS clone URL for authenticated access to private repositories; after a successful clone the origin remote is reset to the credential-free URL, so the token never persists in `.git/config`.
- **Parameters:** -RepositoryUrl, -LocalPath, -Token
- **Usage:** `Initialize-Repository -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo"`, `Initialize-Repository -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo" -Token $pat`

If the target path does not exist, the repository is cloned from `RepositoryUrl`; if it already exists, `git pull` fetches the latest changes. Parent directories are created automatically via `Initialize-Directory`. The Obsidian repository is cloned shallow (`--depth 1`) due to its large history, and every cloned repository has `takeown` applied to set the current user as owner.

| Parameter        | Description                                                                                                                                  |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `-RepositoryUrl` | HTTPS URL of the repository to clone or update.                                                                                              |
| `-LocalPath`     | Absolute local path where the repository should be cloned.                                                                                   |
| `-Token`         | Personal access token for authenticated HTTPS cloning of private repositories. Used only for the clone itself - origin is reset to the credential-free URL afterwards, so the token is never persisted or logged. |

```powershell
# Clone a public repository to the specified path
Initialize-Repository -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo"

# Clone a private repository using a personal access token
Initialize-Repository -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo" -Token $pat
```

**See also:** [Update-Repositories](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Update-Repositories.ps1)

## [Install-Git](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Install-Git.ps1)

- **Description:** Installs Git via WinGet (if not already available) and configures Git global settings. Reads the `GitConfig` section of `Configuration.psd1` to set `user.name`, `user.email`, and enable `core.longpaths`. Called automatically by Bootstrap.
- **Usage:** `Install-Git`

If `git` is not already on PATH, installs it using the WinGet package ID from `GitConfig.WingetPackageId` and refreshes the current session PATH. It then applies the global Git settings whether or not Git was just installed, so running it again simply re-applies configuration.

**Actions:**

- Installs Git via WinGet using `GitConfig.WingetPackageId` (skipped if `git` is already available).
- Sets `user.name` from `GitConfig.UserName`.
- Sets `user.email` from `GitConfig.UserEmail`.
- Enables `core.longpaths` system-wide, required for cloning the Obsidian repository which has very long filenames.

```powershell
# Install and configure Git, or re-apply git config if already installed
Install-Git
```

## [Invoke-StartupRepositoryUpdate](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Invoke-StartupRepositoryUpdate.ps1)

- **Description:** The automatic repository update, queued by the profile as the startup stage `RepositoryUpdate` so it runs after the first prompt is drawn - shell start pays nothing. Off unless `RepositoryUpdate.Startup.Enabled` is `$true`, and throttled by a stamp file (`Logs\.last-repository-update`) to once per `RepositoryUpdate.Startup.IntervalHours` (default 24). Updates the groups `RepositoryUpdate.Startup.Scope` names (falling back to `BootstrapConfig.RepositoryUpdateScope`, then every group) with `Update-Repositories -NoClone -Quiet`: missing repositories are listed as skipped and never cloned, so it never asks for Administrator, and it prints one line per repository plus a totals line. Never throws.
- **Parameters:** -Force, -RedrawPrompt
- **Usage:** `Invoke-StartupRepositoryUpdate`, `Invoke-StartupRepositoryUpdate -Force`

The stamp records when the last run happened, so a machine that was off for days updates on its first shell back - nothing is scheduled, so nothing can be missed. It is written before the update starts: several tabs opened at once run it only once, and a run that failed (offline, for example) is not retried until the interval has passed again. `-Force` runs it now, ignoring `Enabled` and the interval.

The run happens inside the shell after the prompt is already drawn, so its summary pushes the prompt away and typing waits until the fetches finish. The profile passes `-RedrawPrompt`, which draws the prompt again below the summary with PSReadLine's `InvokePrompt` - without it PSReadLine keeps waiting on a blank line. Skip it for one shell with `$env:WINUX_STARTUP_SKIP = "RepositoryUpdate"`.

| Parameter       | Type     | Default | Description                                                                                             |
| --------------- | -------- | ------- | ------------------------------------------------------------------------------------------------------- |
| `-Force`        | `switch` | off     | Run now, ignoring `Enabled` and the interval.                                                           |
| `-RedrawPrompt` | `switch` | off     | After a run, draw the prompt again below the summary. Does nothing when no update ran or outside PSReadLine. |

```powershell
# What a new shell would do, right now
Invoke-StartupRepositoryUpdate -Force

# When did it last run?
Get-Item (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -Force | Select-Object LastWriteTime
```

**See also:** [Update-Repositories](#update-repositories), [Resolve-RepositoryUpdateScope](bootstrap.md#resolve-repositoryupdatescope), [Invoke-StartupRepositoryUpdate configuration guide](../configuration/guides/git/Invoke-StartupRepositoryUpdate.md)

## [Resolve-RepositoryDefaultBranch](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Resolve-RepositoryDefaultBranch.ps1)

- **Description:** Resolves the name of a repository's default branch for the default-branch step of `Update-Repositories`. Returns `RepositoryUpdate.DefaultBranch` when it is set, otherwise what the remote reports (`refs/remotes/origin/HEAD`, without its `origin/` prefix), otherwise `$null`, so the caller skips the step. Read-only: nothing is fetched and no ref is written.
- **Parameters:** `[-LocalPath]`
- **Usage:** `Resolve-RepositoryDefaultBranch`, `Resolve-RepositoryDefaultBranch -LocalPath "<DevRoot>\MyRepo"`

`git clone` writes `origin/HEAD`, so every repository `Update-Repositories` cloned answers on its own. A repository created another way may carry none; `Update-Repository` then runs `git remote set-head origin --auto` once to record it, and this function is called again. Set `RepositoryUpdate.DefaultBranch` only when every configured repository shares one default branch name.

| Parameter    | Type     | Default     | Description                              |
| ------------ | -------- | ----------- | ---------------------------------------- |
| `-LocalPath` | `string` | `$PWD.Path` | The repository's working-tree path.      |

```powershell
# The default branch of the repository the shell stands in
Resolve-RepositoryDefaultBranch

# The default branch of a configured repository
Resolve-RepositoryDefaultBranch -LocalPath "<DevRoot>\MyRepo"
```

**See also:** [Update-RepositoryDefaultBranch](#update-repositorydefaultbranch), [Update-Repositories](#update-repositories), [Resolve-RepositoryDefaultBranch configuration guide](../configuration/guides/git/Resolve-RepositoryDefaultBranch.md)

## [Resolve-RepositoryTargets](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Resolve-RepositoryTargets.ps1)

- **Description:** Expands repository names, group names, or every configured group into resolved repository targets. The single place that turns a selection into concrete repositories: each one is resolved through `Resolve-ProjectPath -ForRepository`, so the configured `UrlPath` / `LocalPath` dot-notation becomes a real URL and a real path for this machine. Group matching is case-insensitive and the returned `Group` carries the configured spelling; an unknown group name logs one error listing every configured group and returns `$null` without resolving anything. Order follows the configuration - groups in the order they were requested (configuration order for `-All`), repositories in the order their group lists them - and the result is deduplicated by `LocalPath`, so a repository listed in two groups is still only updated once.
- **Parameters:** -Repositories, -Group, -All
- **Usage:** `Resolve-RepositoryTargets -Group Work`, `Resolve-RepositoryTargets -Group Work, OpenSource`, `Resolve-RepositoryTargets -All`, `Resolve-RepositoryTargets -Repositories MyRepo`

Returns one `PSCustomObject` per repository with `Name`, `Group`, `RepositoryUrl` and `LocalPath`. `$null` is reserved for "a requested group name is not configured"; a group that exists but is empty yields an empty array. `Update-Repositories` delegates every selection mode to this function, including the interactive menu, which is why menu entries carry real URLs.

| Parameter        | Description                                                                                              |
| ---------------- | -------------------------------------------------------------------------------------------------------- |
| `-Repositories`  | Repository names as defined in `RepositoryGroups`. Null or whitespace entries are skipped.               |
| `-Group`         | One or more group names from `RepositoryGroups`. Matched case-insensitively.                              |
| `-All`           | Expands every configured group, in configuration order.                                                  |

```powershell
# Every repository in one group, in the order the configuration lists them
Resolve-RepositoryTargets -Group Work

# Several groups at once - Work first, shared repositories listed once
Resolve-RepositoryTargets -Group Work, OpenSource

# Everything, for a report
Resolve-RepositoryTargets -All | Format-Table Name, Group, LocalPath
```

**See also:** [Configuration: Add Repository](../configuration/guides/git/add-new-repository.md)

## [Test-GitRepository](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Test-GitRepository.ps1)

- **Description:** Tells whether a path is inside a git repository, by walking up to the root looking for a `.git` entry. Both shapes count: the ordinary `.git` DIRECTORY of a normal clone, and the `.git` FILE a worktree or a submodule carries (a one-line `gitdir: ...` pointer). Neither is opened; the test is `Test-Path` and nothing else. A path that does not exist is not an error - the walk simply finds no `.git` above it and returns `$false` - so a caller can pass a stale `$PWD` without guarding it.
- **Parameters:** `[-Path]`
- **Usage:** `Test-GitRepository`, `Test-GitRepository -Path "C:\Development\WinuX\Windows"`, `if (Test-GitRepository) { onefetch }`

No process is spawned. `git rev-parse --is-inside-work-tree` answers the same question more thoroughly - it knows about `GIT_DIR`, `.git` files pointing nowhere, and the ceiling directories - but it costs a process launch, and this runs on every `Show-TerminalGreeting` call and therefore on every `c` and every shell start. The walk is a handful of stat calls and is not measurable.

| Parameter | Type     | Default     | Description                                                                                                       |
| --------- | -------- | ----------- | ------------------------------------------------------------------------------------------------------------------- |
| `-Path`   | `string` | `$PWD.Path` | The directory to start the walk at. A file path works as long as its directory exists - the walk starts there.    |

```powershell
# Is this shell inside a repository?
Test-GitRepository

# Any directory below the root answers the same way
Test-GitRepository -Path "C:\Development\WinuX\Windows\PowerShell"

# The guard Invoke-Onefetch is built on
if (Test-GitRepository) { onefetch }
```

**See also:** [Invoke-Onefetch](system.md#invoke-onefetch), [Show-TerminalGreeting](system.md#show-terminalgreeting), [Test-GitRepository configuration guide](../configuration/guides/git/Test-GitRepository.md)

## [Update-Repositories](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Update-Repositories.ps1)

- **Description:** Clones or updates one or more git repositories defined in `RepositoryGroups` in `Configuration.psd1`, where repositories are organized into named groups (for example "Private" and "Work") defined in configuration, never in code. With no parameters it shows an interactive menu grouped by group name; otherwise it updates one or more groups (`-Group`), a named repository, everything (`-All`), or a specific URL/path pair. The selection modes are mutually exclusive, enforced by parameter sets. Each existing repository is updated by [`Update-Repository`](#update-repository): local changes are stashed, the checked-out branch is fast-forwarded, and the stash is popped. With `-IncludeDefaultBranch`, or `RepositoryUpdate.IncludeDefaultBranch` in configuration, each repository's default branch is fast-forwarded too, without checking it out. A repository missing locally is cloned, or with `-NoClone` reported and skipped. `-Quiet` prints one line per repository plus a totals line (via [`Format-RepositoryUpdateResult`](#format-repositoryupdateresult)). A run that spans several groups prints a heading per group, in configuration order. Archive mode downloads repository contents without the `.git` directory (to the Desktop by default) via `git clone --depth 1` with `.git` removal. Administrator privileges are required only to clone: in archive mode, and when a selected repository is missing and `-NoClone` is not given.
- **Parameters:** -Repositories, -RepositoryUrl, -LocalPath, -Group, -All, -InCurrentDirectory, -Archive, -IncludeDefaultBranch, -NoClone, -Quiet
- **Usage:** `Update-Repositories`, `Update-Repositories MyRepo`, `Update-Repositories -Group Private`, `Update-Repositories -Group Private, Work`, `Update-Repositories -All`, `Update-Repositories -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo"`, `Update-Repositories -All -Archive`, `Update-Repositories -All -Archive -InCurrentDirectory`, `Update-Repositories -All -IncludeDefaultBranch`, `Update-Repositories MyRepo -IncludeDefaultBranch:$false`, `Update-Repositories -All -NoClone -Quiet`

Repository URL and local-path mappings are read from `RepositoryGroups` in `Configuration.psd1`, and every selection mode is expanded by [`Resolve-RepositoryTargets`](#resolve-repositorytargets), so repositories are updated in the order the configuration lists them and a repository that appears in more than one selected group is updated only once. In a normal update each repository is checked for uncommitted changes and, if found, a timestamped stash (`<branch>_yyyy-MM-dd_HH-mm-ss`) is created, the branch is fetched from origin and pulled fast-forward-only, and the stash is popped. The stash is created with an ephemeral per-command identity (`-c user.name/-c user.email`), so it works even on machines where no global git identity is configured yet - stash authorship is throwaway metadata (Bootstrap additionally restores the real identity from `GitConfig` before calling this function). Merge conflicts abort the pull and preserve work in the stash.

The default-branch step ([`Resolve-RepositoryDefaultBranch`](#resolve-repositorydefaultbranch), then [`Update-RepositoryDefaultBranch`](#update-repositorydefaultbranch)) runs `git fetch origin <default>:<default>`: git refuses anything but a fast-forward, and the working tree and the stash are never touched. It runs before the stash is popped and also after a pull that could not fast-forward. A default branch with local commits origin does not have is left exactly as it is, and one that was never checked out locally is skipped, never created. The Bootstrap repository step calls this function, so it follows the same configuration.

A repository missing locally is cloned via `Initialize-Repository`, which takes ownership of the new folder and is the only reason Administrator is needed; updating repositories that already exist works in any shell. The Administrator check happens once, after the selection and before the first clone. In archive mode it produces plain source (no git history): a `git clone --depth 1` whose `.git` directory is then removed, skipping any target that already exists.

> [!NOTE]
> Archive mode does **not** use `git archive --remote`. That asks the server to run the `git-upload-archive` service, which GitHub serves on no protocol - it answers HTTP 422 and git exits 128. Since every URL this function builds comes from `Universal.GitHub`, the attempt could never succeed; it only cost two failed round trips per repository (one for `main`, one for `master`) and printed a misleading "git archive not supported" warning on every single download.

| Parameter             | Description                                                                                                                                      |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Repositories`       | One or more repository names to update by name, as defined in `RepositoryGroups` (positional).                                                   |
| `-RepositoryUrl`      | HTTPS URL of a specific repository to update. Must be paired with `-LocalPath`.                                                                  |
| `-LocalPath`          | Absolute local path for the repository. Must be paired with `-RepositoryUrl`.                                                                    |
| `-Group`              | One or more group names from `RepositoryGroups`, matched case-insensitively. An unknown name lists the configured groups and updates nothing.     |
| `-All`                | Updates every repository regardless of group.                                                                                                    |
| `-InCurrentDirectory` | Clones (or archives) into the current working directory instead of the configured paths.                                                         |
| `-Archive`            | Downloads repository contents without git history. Targets the Desktop by default; combine with `-InCurrentDirectory` to use the current folder. |
| `-IncludeDefaultBranch` | Also fast-forward each repository's default branch. Not given: `RepositoryUpdate.IncludeDefaultBranch` decides (default off). `-IncludeDefaultBranch:$false` turns it off for one call. |
| `-NoClone`            | Report and skip repositories missing locally instead of cloning them, so the call never needs Administrator.                                    |
| `-Quiet`              | One line per repository plus a totals line, with git silenced. The form the startup update prints.                                              |

```powershell
# Interactive menu - all configured repositories grouped by type
Update-Repositories

# Update a single repository by name
Update-Repositories MyRepo

# Update all repositories in one group
Update-Repositories -Group Private

# Update several groups, in that order, with shared repositories updated once
Update-Repositories -Group Private, Work

# Update every configured repository
Update-Repositories -All

# Clone or update a specific repository by URL into a chosen path
Update-Repositories -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo"

# Download all repositories as plain source (no .git) to the Desktop
Update-Repositories -All -Archive

# Archive specific repositories into the current directory
Update-Repositories MyRepo OtherProject -Archive -InCurrentDirectory

# Also bring each repository's default branch (master) up to date
Update-Repositories -All -IncludeDefaultBranch

# Everything already on disk, one line each, without asking for Administrator
Update-Repositories -All -NoClone -Quiet
```

What `-Quiet` prints for a run over two groups, with the default branch on (illustrative names):

```text
[Updating All Repositories]

[Private]

=> [MyRepo] master - up to date
=> [OtherProject] feature/login - updated, master fast-forwarded

[Work]

=> [MyWorkRepo] develop - up to date, main up to date

=> Repositories => 1 updated, 2 up to date, 0 need attention, 0 skipped
```

**See also:** [Configuration: Add Repository](../configuration/guides/git/add-new-repository.md), [Modules: Workflow](workflow.md)

## [Update-Repository](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Update-Repository.ps1)

- **Description:** Updates one cloned repository, the per-repository step of `Update-Repositories`: stashes local changes (untracked files included, ephemeral identity), fetches and fast-forwards the checked-out branch, optionally fast-forwards the default branch without checking it out, then pops the stash. A pull that cannot fast-forward is aborted and the stash given back; a failed stash leaves the repository alone; a conflicting pop keeps the stash. A checked-out branch origin does not have (never pushed) has nothing to pull, and a fetch that fails while origin has the branch (offline) pulls nothing and is reported as such instead of as up to date. Returns one result object. Without `-Quiet` every step is logged and git's own output reaches the console; with `-Quiet` nothing is logged and git is silenced.
- **Parameters:** -Name, -LocalPath, -IncludeDefaultBranch, -Quiet
- **Usage:** `Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo"`, `Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo" -IncludeDefaultBranch -Quiet`

When neither `RepositoryUpdate.DefaultBranch` nor `origin/HEAD` names the default branch (a repository not created by `git clone`), it asks origin once with `git remote set-head origin --auto`, which writes only that local ref, and resolves again - so such a repository heals itself on its first run.

The result carries `Name`, `LocalPath`, `Branch`, `Outcome` (`Updated`, `UpToDate`, `NoUpstream`, `FetchFailed`, `Conflict`, `StashFailed`, `StashConflict` or `Error`), `DefaultBranch`, `DefaultBranchOutcome` (`$null` when the step did not run, `Unresolved` when no default branch could be named, otherwise what `Update-RepositoryDefaultBranch` returned) and `StashName` (set only while a stash is still held). The repository must exist; cloning is `Update-Repositories`' job.

| Parameter               | Type     | Default    | Description                                                         |
| ----------------------- | -------- | ---------- | ------------------------------------------------------------------- |
| `-Name`                 | `string` | (required) | Display name, used in messages and returned in the result.          |
| `-LocalPath`            | `string` | (required) | The repository's working-tree path. Must exist.                     |
| `-IncludeDefaultBranch` | `switch` | off        | Also fast-forward the default branch.                               |
| `-Quiet`                | `switch` | off        | Log nothing and silence git; the caller prints the result.          |

```powershell
# Update one repository, preserving local changes
Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo"

# The same, master too, and only the result back
Update-Repository -Name MyRepo -LocalPath "<DevRoot>\MyRepo" -IncludeDefaultBranch -Quiet | Format-List
```

**See also:** [Update-Repositories](#update-repositories), [Update-RepositoryDefaultBranch](#update-repositorydefaultbranch), [Format-RepositoryUpdateResult](#format-repositoryupdateresult)

## [Update-RepositoryDefaultBranch](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Update-RepositoryDefaultBranch.ps1)

- **Description:** Fast-forwards a repository's default branch (for example `master`) without checking it out, by running `git fetch origin <default>:<default>`. The refspec has no leading `+`, so git refuses anything but a fast-forward, and fetching into a branch that is not checked out never touches the working tree, the index or the stash. Returns one outcome: `Current` (the default branch is the checked-out one, nothing to do), `Missing` (no local branch of that name; skipped, never created), `UpToDate`, `Updated`, `Diverged` (the local branch has commits origin does not; left untouched) or `Failed` (offline, no such remote branch, or the branch is checked out in another worktree). With `-Quiet` it logs nothing and silences git, and the caller reports the outcome.
- **Parameters:** -DefaultBranch, -CurrentBranch, -LocalPath, -Quiet
- **Usage:** `Update-RepositoryDefaultBranch -DefaultBranch master -CurrentBranch feature/login`, `Update-RepositoryDefaultBranch -DefaultBranch master -CurrentBranch feature/login -LocalPath "<DevRoot>\MyRepo" -Quiet`

A rejected fast-forward and a failed fetch exit with the same code, so the outcome is decided from the refs afterwards: when the local branch is not an ancestor of `origin/<default>`, the two have diverged.

| Parameter        | Type     | Default     | Description                                                          |
| ---------------- | -------- | ----------- | -------------------------------------------------------------------- |
| `-DefaultBranch` | `string` | (required)  | The default branch's name, typically from `Resolve-RepositoryDefaultBranch`. |
| `-CurrentBranch` | `string` | (required)  | The checked-out branch.                                              |
| `-LocalPath`     | `string` | `$PWD.Path` | The repository's working-tree path.                                  |
| `-Quiet`         | `switch` | off         | Log nothing and silence git; the caller prints the outcome.          |

```powershell
# Bring master up to date while a feature branch stays checked out
Update-RepositoryDefaultBranch -DefaultBranch master -CurrentBranch feature/login

# Resolve the name first, as Update-Repositories does
$default = Resolve-RepositoryDefaultBranch -LocalPath "<DevRoot>\MyRepo"
Update-RepositoryDefaultBranch -DefaultBranch $default -CurrentBranch (git -C "<DevRoot>\MyRepo" rev-parse --abbrev-ref HEAD) -LocalPath "<DevRoot>\MyRepo"
```

**See also:** [Resolve-RepositoryDefaultBranch](#resolve-repositorydefaultbranch), [Update-Repositories](#update-repositories), [Update-RepositoryDefaultBranch configuration guide](../configuration/guides/git/Update-RepositoryDefaultBranch.md)

## Configuration

### Repository URL Structure

Repositories are configured in `Configuration.psd1`:

```powershell
Universal = @{
    GitHub = @{
        Base = "https://YourUsername@github.com"
        Private = @{
            MyRepo = "/YourUsername/MyRepo.git"
            Obsidian = "/YourUsername/Obsidian.git"
        }
        MyOrg = @{
            MyWorkRepo = "/my-org/MyWorkRepo.git"
        }
    }
}
```

### Repository Groups

```powershell
RepositoryGroups = @(
    @{ Private = @(
            @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "RepoRoot" }
        )
    }
    @{ Work = @(
            @{ Name = "MyWorkRepo"; UrlPath = "Universal.GitHub.MyOrg.MyWorkRepo"; LocalPath = "Projects.MyOrg.MyWorkRepo.Root" }
        )
    }
)
```

- **Group key** (e.g. `Private`, `Work`): freely configurable category; `-Group <name>` and the interactive menu follow whatever groups you define - no group name is known to code
- **Name**: Display name and identifier
- **UrlPath**: Dot-notation path to URL in Universal section
- **LocalPath**: Dot-notation path to local directory

### Git Configuration

```powershell
GitConfig = @{
    WingetPackageId = "Git.Git"
    UserName        = "Your Name"
    UserEmail       = "your@email.com"
}
```

## Common Workflows

### Daily Update

```powershell
# Update all personal and work repos
Update-Repositories -All
```

### New Machine Setup

```powershell
# Bootstrap does this automatically
Bootstrap -WithInitialSetup

# Or manually clone all repos:
Update-Repositories -All
```

### Quick Obsidian Backup

```powershell
# From anywhere
Git-Obsidian
# Commits and pushes Obsidian vault
```

### Feature Branch Workflow

```powershell
# Create feature branch
gb feature/new-feature

# Work on feature...

# Merge main into your branch to stay up to date
gmm

# Clean up
gbd feature/new-feature
```
