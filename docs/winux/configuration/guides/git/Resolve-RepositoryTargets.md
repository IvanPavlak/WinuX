# Resolve-RepositoryTargets

Expands repository names, group names, or every configured group into resolved repository targets.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array of single-key hashtables | array of 1 | The groups this function expands, their names, and the order repositories come back in. Group name to an array of repository entries, each carrying `Name`, `UrlPath` and `LocalPath`. |

## Decisions

1. What should your groups be called?
    - Options: Anything. Group names are never known to code - `-Group` takes whatever keys you define here, matched case-insensitively, and an unknown name lists the configured ones instead of guessing. `Private` and `Work` are only the shipped example; `OpenSource`, `Clients`, `Archived` are just as valid.
    - Default: The single shipped `Private` group.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
2. In what order should repositories inside a group be updated?
    - Options: Whatever order you write them in. The list is walked as configured and never sorted, so putting the repository you care about most first makes it update first.
    - Default: The shipped order.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
3. Should a repository belong to more than one group?
    - Options: Yes - list the same entry under several groups. Selecting both groups still updates it once, because the result is deduplicated by resolved `LocalPath`.
    - Default: Each shipped repository belongs to one group.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `RepositoryGroups` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `RepositoryGroups`
2. Reload and confirm the merge landed

## Step 1: Set `RepositoryGroups`

The groups this function expands. Each repository entry carries `Name` (what you select it by), `UrlPath` (dot-notation into `Universal.GitHub`) and `LocalPath` (dot-notation into the machine-specific paths). Both paths are dot-notation, not literal values - that is how the same entry resolves to different folders on different machines.

```powershell
RepositoryGroups = @(
    @{ Private = @(
            @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root" }
        )
    }
    @{ Work = @(
            @{ Name = "MyWorkRepo"; UrlPath = "Universal.GitHub.MyOrg.MyWorkRepo"; LocalPath = "Projects.MyOrg.MyWorkRepo.Root" }
        )
    }
)
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryGroups
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryGroups

# Every configured repository, with the URL and path each one actually resolved to
Resolve-RepositoryTargets -All | Format-Table Name, Group, RepositoryUrl, LocalPath

# One group, in configuration order
Resolve-RepositoryTargets -Group Work | Format-Table Name, LocalPath

# A deliberate typo, to see the error list your configured group names
Resolve-RepositoryTargets -Group Wrok
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level. If a repository resolves with an empty `LocalPath`, its `LocalPath` dot-notation names a path this machine type does not define.

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
            MyOrg   = @{
                MyWorkRepo = "/my-org/MyWorkRepo.git"
            }
        }
    }

    RepositoryGroups = @(
        @{ Private = @(
                @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root" }
            )
        }
        @{ Work = @(
                @{ Name = "MyWorkRepo"; UrlPath = "Universal.GitHub.MyOrg.MyWorkRepo"; LocalPath = "Projects.MyOrg.MyWorkRepo.Root" }
            )
        }
    )
}
```

## Related

- [`Resolve-RepositoryTargets` in the Git module reference](../../../modules/git.md#resolve-repositorytargets) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [Add New Repository](add-new-repository.md) - repository groups and what `Update-Repositories` walks
- [`Update-Repositories`](Update-Repositories.md) - reads the same configuration
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - resolves each entry's `UrlPath` and `LocalPath`
- [`Resolve-RepositoryUpdateScope`](../bootstrap/Resolve-RepositoryUpdateScope.md) - which of these groups Bootstrap pulls
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
