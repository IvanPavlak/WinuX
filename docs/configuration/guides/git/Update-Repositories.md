# Update-Repositories

Clones or updates one or more git repositories defined in `RepositoryGroups` in `Configuration.psd1`, where repositories are organized into named groups (for example "Private" and "Work") defined in configuration, never in code.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array of single-key hashtables | array of 1 | The repository groups `Update-Repositories` walks and `Initialize-Repository` can clone into. Group name to an array of repository entries. |
| [`RepositoryUpdate.IncludeDefaultBranch`](../../configuration-reference.md#repository-update) | bool | `$false` | Also fast-forward each repository's default branch (for example `master`) when another branch is checked out, without checking it out. `-IncludeDefaultBranch` / `-IncludeDefaultBranch:$false` overrides it for one call. |

## Decisions

1. Which repository groups do you want to manage?
    - Options: One group per collection, e.g. `Personal`, `Work`, `OpenSource`. Group names are freely configurable and never known to code - `Update-Repositories -Group <name>` takes whatever keys you define, matched case-insensitively, and an unknown name lists the configured ones. Each entry carries the repository name and its remote - see [Add New Repository](../git/add-new-repository.md).
    - Default: The shipped single example group.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
2. Where should each repository be cloned to?
    - Options: A `LocalPath` per repository, written in dot-notation into the machine-specific paths (normally under `{Dev}`), so the same entry resolves to a different folder on each machine.
    - Default: The shipped path.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
3. In what order should a group's repositories be updated?
    - Options: Whatever order you write them in - the list is walked as configured and never sorted. A repository listed in two groups is still updated only once.
    - Default: The shipped order.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
4. Should the default branch be kept current while you work on another branch?
    - Options: `$true` fast-forwards each repository's default branch after the checked-out branch, with `git fetch origin <default>:<default>` - git refuses anything but a fast-forward, the working tree and the stash are never touched, a default branch with local commits is left alone, and one never checked out locally is skipped. `$false` updates only the checked-out branch, as before. Which branch counts as the default is [`Resolve-RepositoryDefaultBranch`](Resolve-RepositoryDefaultBranch.md)'s decision.
    - Default: `$false`.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `RepositoryGroups` - that key is an array, so whatever you write is the complete value. `RepositoryUpdate` is a hashtable, so a single key there is enough.

## Steps Overview

1. Set `RepositoryGroups`
2. Set `RepositoryUpdate.IncludeDefaultBranch`
3. Reload and confirm the merge landed

## Step 1: Set `RepositoryGroups`

The repository groups `Update-Repositories` walks and `Initialize-Repository` can clone into. Group name to an array of repository entries. Each entry carries `Name` (what you select it by), `UrlPath` (dot-notation into `Universal.GitHub`) and `LocalPath` (dot-notation into the machine-specific paths) - both paths are dot-notation, not literal values.

```powershell
RepositoryGroups = @(
    @{ Personal = @(
            @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root" }
        )
    }
)
```

## Step 2: Set `RepositoryUpdate.IncludeDefaultBranch`

Turn on the default-branch fast-forward for every call, the Bootstrap repository step included.

```powershell
RepositoryUpdate = @{
    IncludeDefaultBranch = $true
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryGroups
$global:Configuration.RepositoryUpdate.IncludeDefaultBranch
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryGroups
$global:Configuration.RepositoryGroups | ConvertTo-Json -Depth 4

# What each selection mode would actually update, without updating anything
Resolve-RepositoryTargets -All | Format-Table Name, Group, RepositoryUrl, LocalPath
Resolve-RepositoryTargets -Group Work | Format-Table Name, LocalPath
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal        = @{
        GitHub = @{
            Base    = "https://YourUsername@github.com"
            Private = @{
                MyRepo = "/YourUsername/MyRepo.git"
            }
        }
    }

    RepositoryGroups = @(
        @{ Personal = @(
                @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root" }
            )
        }
    )

    RepositoryUpdate = @{
        IncludeDefaultBranch = $true
    }
}
```

With that in place:

```powershell
Update-Repositories -Group Personal              # the whole group, in configuration order, master too
Update-Repositories MyRepo                       # one repository by name
Update-Repositories -All                         # every group
Update-Repositories                              # interactive menu
Update-Repositories -All -IncludeDefaultBranch:$false   # this once, the checked-out branch only
Update-Repositories -All -NoClone -Quiet         # what is on disk, one line each, no Administrator
```

## Related

- [`Update-Repositories` in the Git module reference](../../../modules/git.md#update-repositories) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [Add New Repository](add-new-repository.md) - repository groups and what `Update-Repositories` walks
- [`Resolve-RepositoryTargets`](Resolve-RepositoryTargets.md) - expands every selection mode this function offers
- [`Update-Repository`](Update-Repository.md) - updates each repository
- [`Resolve-RepositoryDefaultBranch`](Resolve-RepositoryDefaultBranch.md) - which branch counts as the default
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - reads the same configuration
- [`Resolve-RepositoryUpdateScope`](../bootstrap/Resolve-RepositoryUpdateScope.md) - which groups Bootstrap pulls
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
