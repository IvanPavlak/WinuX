# Initialize-Repository

Clones a repository to a local path, or, if it already exists there, updates it with [`Update-Repository`](Update-Repository.md), which keeps local work safe.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array of single-key hashtables | array of 1, no entry `Shallow` | `Shallow = $true` on an entry clones that entry's URL `--depth 1`. The URLs are compared without case, a user name, a trailing slash or `.git`. |

## Decisions

1. Which repositories should be cloned without their history?
    - Options: `Shallow = $true` on the entry of a repository with a large history (an Obsidian vault). The clone keeps its `.git` and can still commit and push. No repository name is special.
    - Default: Full history.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. `RepositoryGroups` is an array, so whatever you write is the complete value.

## Steps Overview

1. Mark the repository `Shallow`
2. Reload and confirm the merge landed

## Step 1: Mark the repository `Shallow`

```powershell
RepositoryGroups = @(
    @{ Personal = @(
            @{ Name = "MyNotes"; UrlPath = "Universal.GitHub.Private.MyNotes"; LocalPath = "Projects.MyNotes.Root"; Shallow = $true }
        )
    }
)
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryGroups | ConvertTo-Json -Depth 4
```

## Verification

Read-only checks. None of these change anything.

```powershell
$global:Configuration.RepositoryGroups | ForEach-Object { $_.Values } | ForEach-Object { $_ } | Where-Object { $_.Shallow } | ForEach-Object { $_.Name }
```

## Complete Example

```powershell
# Configuration.local.psd1
@{
    RepositoryGroups = @(
        @{ Personal = @(
                @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root" }
                @{ Name = "MyNotes"; UrlPath = "Universal.GitHub.Private.MyNotes"; LocalPath = "Projects.MyNotes.Root"; Shallow = $true }
            )
        }
    )
}
```

With that in place, `Update-Repositories MyNotes` clones `MyNotes` shallow while its folder is missing, and so does `Initialize-Repository` for the same URL.

```powershell
Initialize-Repository -RepositoryUrl "https://github.com/user/MyNotes" -LocalPath "<DevRoot>\MyNotes"
Initialize-Repository -RepositoryUrl "https://github.com/user/MyRepo" -LocalPath "<DevRoot>\MyRepo" -Token $pat
```

## Related

- [`Initialize-Repository` in the Git module reference](../../../modules/git.md#initialize-repository) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [`Update-Repositories`](Update-Repositories.md) - clones through this function
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
