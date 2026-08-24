# Update-Repositories

Clones or updates one or more git repositories defined in `RepositoryGroups` in `Configuration.psd1`, where repositories are organized into named groups (for example "Private" and "Work") defined in configuration.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array of single-key hashtables | array of 1 | The repository groups `Update-Repositories` walks and `Initialize-Repository` can clone into. Group name to an array of repository entries. |

## Decisions

1. Which repository groups do you want to manage?
    - Options: One group per collection, e.g. `Personal`, `Work`. Each entry carries the repository name and its remote - see [Add New Repository](../git/add-new-repository.md).
    - Default: The shipped single example group.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
2. Where should each group be cloned to?
    - Options: A path per group, normally under `{Dev}`.
    - Default: The shipped path.
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

The repository groups `Update-Repositories` walks and `Initialize-Repository` can clone into. Group name to an array of repository entries.

```powershell
RepositoryGroups = @(
    @{ Personal = @(
        @{ Name = "MyRepo"; Url = "https://github.com/YourUsername/MyRepo.git" }
    )}
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
$global:Configuration.RepositoryGroups | ConvertTo-Json -Depth 4
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    RepositoryGroups = @(
        @{ Personal = @(
            @{ Name = "MyRepo"; Url = "https://github.com/YourUsername/MyRepo.git" }
        )}
    )
}
```

## Related

- [`Update-Repositories` in the Git module reference](../../../modules/git.md#update-repositories) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [Add New Repository](add-new-repository.md) - repository groups and what `Update-Repositories` walks
- [`Resolve-ProjectPath`](../helper/Resolve-ProjectPath.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
