# Add New Repository

This guide shows how to add a Git repository to WinuX for automatic cloning and updating via `Update-Repositories`.

## Steps Overview

1. Add GitHub URL to `Universal.GitHub`
2. Add a repository entry in `RepositoryGroups`
3. (Optional) Add project paths if it's a development project

## Step 1: Add GitHub URL

In `Configuration.psd1` under `Universal.GitHub`, add your repository URL:

```powershell
Universal = @{
    GitHub = @{
        Base = "https://YourUsername@github.com"

        # For personal/private repos
        Private = @{
            WinuX       = "/YourUsername/WinuX.git"
            Obsidian    = "/YourUsername/Obsidian.git"
            MyNewRepo   = "/YourUsername/MyNewRepo.git"    # ← Add here
        }

        # For work repos (organization)
        MyOrg = @{
            ProjectA = "/my-org/ProjectA.git"
            ProjectB = "/my-org/ProjectB.git"
        }
    }
}
```

## Step 2: Add Repository Mapping

In `RepositoryGroups`, add the repository under a group:

```powershell
RepositoryGroups = @(
    # Existing groups...

    @{ Private = @(
            @{ Name = "MyNewRepo"; UrlPath = "Universal.GitHub.Private.MyNewRepo"; LocalPath = "Projects.MyNewRepo.Root" }
        )
    }
)
```

**Understanding the mapping:**

| Property    | Description                                             | Example                              |
| ----------- | ------------------------------------------------------- | ------------------------------------ |
| `Name`      | Repository name (selection and by-name updates)         | `MyNewRepo`                          |
| `UrlPath`   | Dot-notation path to URL in `Universal.GitHub`          | `Universal.GitHub.Private.MyNewRepo` |
| `LocalPath` | Dot-notation path to local directory in `PathTemplates` | `Projects.MyNewRepo.Root`            |
| Group key   | Category the entry lives under (freely configurable)    | `Private` or `Work`                  |

## Step 3: Add Local Path (if needed)

If the `LocalPath` doesn't exist yet, add it to `PathTemplates.Projects`:

```powershell
PathTemplates = @{
    Projects = @{
        MyNewRepo = @{
            Root = "{Dev}\MyNewRepo"
        }
    }
}
```

Or for a simple path outside Projects:

```powershell
PathTemplates = @{
    MyNewRepoDirectory = "{Dev}\MyNewRepo"
}

# Then use in the group:
@{ Private = @(
        @{ Name = "MyNewRepo"; UrlPath = "Universal.GitHub.Private.MyNewRepo"; LocalPath = "MyNewRepoDirectory" }
    )
}
```

## Usage

After configuration, use `Update-Repositories`:

```powershell
# Interactive menu - select repos to update
Update-Repositories

# Update specific repo by name
Update-Repositories MyNewRepo

# Update all private repos
Update-Repositories -Private

# Update all work repos
Update-Repositories -Work

# Update everything
Update-Repositories -All

# Download repo as plain source (no .git) to Desktop
Update-Repositories MyNewRepo -Archive

# Archive into current directory instead
Update-Repositories MyNewRepo -Archive -InCurrentDirectory
```

## Repository Groups

### Private Repositories

Personal repos that require authentication - place them under the `Private` group (included with the `-Private` flag):

```powershell
@{ Private = @(
        @{ Name = "MyPrivateRepo"; UrlPath = "Universal.GitHub.Private.MyPrivateRepo"; LocalPath = "Projects.MyPrivateRepo.Root" }
    )
}
```

### Work Repositories

Organization repos - place them under the `Work` group (included with the `-Work` flag):

```powershell
@{ Work = @(
        @{ Name = "WorkProject"; UrlPath = "Universal.GitHub.MyOrg.WorkProject"; LocalPath = "Projects.MyOrg.WorkProject.Root" }
    )
}
```

## How Update-Repositories Works

For each repository:

```
1. Check if repo exists locally
   ├─→ If NO: Clone using Initialize-Repository
   └─→ If YES: Continue to update

2. Detect uncommitted changes
   └─→ Create timestamped stash (e.g., "master_2026-01-21_14-30-00")

3. Fetch latest from origin
   └─→ git fetch origin

4. Pull with fast-forward only
   └─→ git pull --ff-only

5. Restore stash if created
   └─→ git stash pop

6. Report status
   └─→ Success, already up-to-date, or error message
```

## Complete Example

Adding a new private repository "MyAwesomeProject":

```powershell
# 1. Add URL
Universal = @{
    GitHub = @{
        Private = @{
            WinuX           = "/IvanPavlak/WinuX.git"
            MyAwesomeProject = "/IvanPavlak/MyAwesomeProject.git"  # ← New
        }
    }
}

# 2. Add local path
PathTemplates = @{
    Projects = @{
        MyAwesomeProject = @{
            Root     = "{Dev}\MyAwesomeProject"
            Solution = "{Dev}\MyAwesomeProject\MyAwesomeProject.sln"
        }
    }
}

# 3. Add repository entry
RepositoryGroups = @(
    @{ Private = @(
            @{ Name = "MyAwesomeProject"; UrlPath = "Universal.GitHub.Private.MyAwesomeProject"; LocalPath = "Projects.MyAwesomeProject.Root" }
        )
    }
)
```

Then:

```powershell
# Clone/update the new repo
Update-Repositories MyAwesomeProject

# Or update all private repos including the new one
Update-Repositories -Private
```

## Troubleshooting

### Authentication Failed

Ensure your Git credentials are configured:

```powershell
git config --global credential.helper manager
```

### Repository Not Found in Menu

Verify the mapping name matches exactly and the paths are valid:

```powershell
# Check configuration loaded correctly (find your repo across all groups)
$Configuration.RepositoryGroups | ForEach-Object { $_[@($_.Keys)[0]] } | Where-Object Name -eq "MyNewRepo"
```

### Path Not Expanding

Ensure `LocalPath` uses valid dot-notation to an existing path in configuration:

```powershell
# Test path resolution
$MachineSpecificPaths.Projects.MyNewRepo.Root
```
