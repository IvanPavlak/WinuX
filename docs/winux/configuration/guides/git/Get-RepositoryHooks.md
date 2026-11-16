# Get-RepositoryHooks

Lists every repository marked with `Hooks` in `RepositoryGroups` and the `core.hooksPath` found in its clone, so a clone where the tracked hooks are not on is seen, not assumed.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array of single-key hashtables | array of 1, no entry `Hooks` | `Hooks = "<folder>"` on an entry marks the repository as tracking its git hooks in that folder, relative to its root. Only marked entries are listed. |

## Decisions

1. Which repositories track their git hooks in a folder?
    - Options: `Hooks = ".githooks"` (or whatever folder the repository uses) on the entry of each such repository. `Update-Repositories` and `Initialize-Repository` then point the clone's `core.hooksPath` at it, and take that back once the key is removed. Mark only repositories whose hooks you have read: a hook is code that runs on this machine at every commit.
    - Default: No repository is marked, and none is touched.
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. `RepositoryGroups` is an array, so whatever you write is the complete value.

## Steps Overview

1. Mark the repository with `Hooks`
2. Reload, update and confirm

## Step 1: Mark the repository with `Hooks`

```powershell
RepositoryGroups = @(
    @{ Personal = @(
            @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root"; Hooks = ".githooks" }
        )
    }
)
```

## Step 2: Reload, update and confirm

```powershell
Reload-PowerShellProfile
Update-Repositories MyRepo
Get-RepositoryHooks
```

## Verification

Read-only checks. None of these change anything.

```powershell
Get-RepositoryHooks
Get-RepositoryHooks -PassThru | Format-Table Name, HooksPath, Found, State
git -C "<DevRoot>\MyRepo" config --local --get core.hooksPath
```

| State | Meaning | What to do |
| ----- | ------- | ---------- |
| `Active` | The value is the configured folder and the folder exists | Nothing |
| `NotSet` | No value in the clone | Run `Update-Repositories` |
| `Different` | Another value, set by hand | Run `Update-Repositories` to replace it, or remove the `Hooks` key to keep yours |
| `MissingFolder` | The configured folder is not in the working tree | Check the key for a typo, or the checked-out branch for the folder |
| `NotCloned` | The repository is not on this machine | Run `Update-Repositories` to clone it |
| `NotConfigured` | The repository has no local path on this machine | Nothing, unless it should have one |
| `NotARepository` | The path is not the top of its own working tree | Check `LocalPath` |
| `Stale` | Recorded by an earlier run, but the entry is no longer marked | Run `Update-Repositories`; it takes the value back |

## Complete Example

```powershell
# Configuration.local.psd1
@{
    RepositoryGroups = @(
        @{ Personal = @(
                @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root"; Hooks = ".githooks" }
                @{ Name = "MyNotes"; UrlPath = "Universal.GitHub.Private.MyNotes"; LocalPath = "Projects.MyNotes.Root" }
            )
        }
    )
}
```

With that in place, `Get-RepositoryHooks` lists `MyRepo` and never `MyNotes`, whatever folders `MyNotes` holds.

```powershell
Get-RepositoryHooks
Get-RepositoryHooks -PassThru | Where-Object State -ne Active
```

## Related

- [`Get-RepositoryHooks` in the Git module reference](../../../modules/git.md#get-repositoryhooks) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [`Update-Repositories`](Update-Repositories.md) - turns the hooks on and off
- [`Sync-RepositoryHooks`](Sync-RepositoryHooks.md) - the per-repository step
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
