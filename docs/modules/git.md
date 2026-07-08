# Git Module

The Git module provides **repository management**, **Git workflow automation**, and **common Git operations**.

## [Git-Diff](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Git-Diff.ps1)

- **Description:** Shows the diff between the working tree and the last commit. Runs `git diff HEAD` to display all unstaged and staged changes relative to HEAD.
- **Usage:** `Git-Diff`
- **Alias:** gdf

## [Git-Obsidian](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Git-Obsidian.ps1)

- **Description:** Commits and pushes all pending changes in the Obsidian vault repository, providing a quick vault backup to GitHub without opening Obsidian.
- **Usage:** `Git-Obsidian`

Navigates to the Obsidian vault directory (`$MachineSpecificPaths.ObsidianDirectory`) and checks for uncommitted changes. If any are present, it stages everything with `git add .`, creates a commit with the message `"Vault Backup: dd.MM.yyyy | HH:mm"`, and pushes to the remote. If there are no changes, it reports that nothing changed and does nothing. The original working directory is always restored on exit.

```powershell
# Commit and push any pending vault changes (or report that nothing changed)
Git-Obsidian
```

**See also:** [Configuration: Add Repository](../configuration/guides/add-new-repository.md)

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

## [Update-Repositories](https://github.com/IvanPavlak/WinuX/blob/master/Windows/PowerShell/Modules/Git/Functions/Update-Repositories.ps1)

- **Description:** Clones or updates one or more git repositories defined in `RepositoryGroups` in `Configuration.psd1`, where repositories are organized into named groups (for example "Private" and "Work") defined in configuration. With no parameters it shows an interactive menu grouped by group name; with switches it updates the corresponding group, a named repository, or a specific URL/path pair directly. Archive mode downloads repository contents without the `.git` directory (to the Desktop by default), trying `git archive` first and falling back to `git clone --depth 1` with `.git` removal. Requires administrator privileges.
- **Parameters:** -Repositories, -RepositoryUrl, -LocalPath, -Private, -Work, -All, -InCurrentDirectory, -Archive
- **Usage:** `Update-Repositories`, `Update-Repositories MyRepo`, `Update-Repositories -Private`, `Update-Repositories -Work`, `Update-Repositories -All`, `Update-Repositories -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo"`, `Update-Repositories -All -Archive`, `Update-Repositories -All -Archive -InCurrentDirectory`

Repository URL and local-path mappings are read from `RepositoryGroups` in `Configuration.psd1`. In a normal update the function checks each repository for uncommitted changes and, if found, creates a timestamped stash (`<branch>_yyyy-MM-dd_HH-mm-ss`), fetches from origin, pulls fast-forward-only, and then pops the stash. The stash is created with an ephemeral per-command identity (`-c user.name/-c user.email`), so it works even on machines where no global git identity is configured yet - stash authorship is throwaway metadata (Bootstrap additionally restores the real identity from `GitConfig` before calling this function). If a repository is missing locally it is cloned via `Initialize-Repository`; merge conflicts abort the pull and preserve work in the stash. In archive mode it produces plain source (no git history): it tries `git archive` against `main` then `master`, falls back to a shallow clone, removes the resulting `.git` directory, and skips any target that already exists.

| Parameter             | Description                                                                                                                                      |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `-Repositories`       | One or more repository names to update by name, as defined in `RepositoryGroups` (positional).                                                   |
| `-RepositoryUrl`      | HTTPS URL of a specific repository to update. Must be paired with `-LocalPath`.                                                                  |
| `-LocalPath`          | Absolute local path for the repository. Must be paired with `-RepositoryUrl`.                                                                    |
| `-Private`            | Updates all repositories in the "Private" group.                                                                                                 |
| `-Work`               | Updates all repositories in the "Work" group.                                                                                                    |
| `-All`                | Updates every repository regardless of type.                                                                                                     |
| `-InCurrentDirectory` | Clones (or archives) into the current working directory instead of the configured paths.                                                         |
| `-Archive`            | Downloads repository contents without git history. Targets the Desktop by default; combine with `-InCurrentDirectory` to use the current folder. |

```powershell
# Interactive menu - all configured repositories grouped by type
Update-Repositories

# Update a single repository by name
Update-Repositories MyRepo

# Update all private repositories
Update-Repositories -Private

# Update every configured repository
Update-Repositories -All

# Clone or update a specific repository by URL into a chosen path
Update-Repositories -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo"

# Download all repositories as plain source (no .git) to the Desktop
Update-Repositories -All -Archive

# Archive specific repositories into the current directory
Update-Repositories MyRepo OtherProject -Archive -InCurrentDirectory
```

**See also:** [Configuration: Add Repository](../configuration/guides/add-new-repository.md), [Modules: Workflow](workflow.md)

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

- **Group key** (e.g. `Private`, `Work`): freely configurable category; `-Private`/`-Work` and the interactive menu follow whatever groups you define
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
