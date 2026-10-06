# Invoke-StartupRepositoryUpdate

Updates the configured repositories automatically, once per interval, after the first prompt of a shell is drawn. Off by default.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`RepositoryUpdate.Startup.Enabled`](../../configuration-reference.md#repository-update) | bool | `$false` | Whether a new shell updates the repositories at all. |
| [`RepositoryUpdate.Startup.IntervalHours`](../../configuration-reference.md#repository-update) | int | `24` | Minimum hours between two automatic runs. The stamp file `Logs\.last-repository-update` records the last run. |
| [`RepositoryUpdate.Startup.Scope`](../../configuration-reference.md#repository-update) | hashtable | absent | Which groups the automatic run updates, per machine type. Absent falls back to `BootstrapConfig.RepositoryUpdateScope`, then to every group. |

The run itself is `Update-Repositories -NoClone -Quiet`, so it also follows [`RepositoryUpdate.IncludeDefaultBranch`](../../configuration-reference.md#repository-update), configured through [`Update-Repositories`](Update-Repositories.md).

## Decisions

1. Should a new shell update your repositories on its own?
    - Options: `$true` runs the update once per interval, after the first prompt is drawn - shell start itself pays nothing, but the summary prints below the prompt and typing waits until the fetches finish. Repositories missing on this machine are listed as skipped, never cloned, so it never asks for Administrator. `$false` leaves updating to you (`Update-Repositories`) and to Bootstrap.
    - Default: `$false`.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)
2. How often?
    - Options: Any number of hours. `24` means the first shell of the day; `8` roughly twice a working day; `0` every shell. Several shells opened at once still run it only once - the run is claimed with a lock file (`Logs\.repository-update.lock`), and a lock left by a shell that died mid-run is cleared by the next one. The stamp records the last run, so a machine that was off for days updates on its first shell back. A run that failed (offline, for example) is not retried until the interval has passed again - `Invoke-StartupRepositoryUpdate -Force` reruns it by hand.
    - Default: `24`.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)
3. Which groups should it update?
    - Options: Leave `Scope` out to update whatever Bootstrap updates on this machine type (`BootstrapConfig.RepositoryUpdateScope`), or set `Scope` in the same shape - `"All"`, a group name, a comma-separated string or an array, per machine type with a `Default` fallback - when the daily update should cover less (or more) than Bootstrap.
    - Default: Absent - the Bootstrap scope, which itself defaults to every group.
    - More detail: [`RepositoryUpdate`](../../configuration-reference.md#repository-update)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`RepositoryUpdate` and `Startup` are hashtables, so writing only `Startup.Enabled` keeps the shipped interval. A `Scope` value written as an array replaces the whole array, as any array does.

## Steps Overview

1. Set `RepositoryUpdate.Startup`
2. Reload and confirm the merge landed

## Step 1: Set `RepositoryUpdate.Startup`

Turn it on, choose the interval, and optionally narrow the groups per machine type.

```powershell
RepositoryUpdate = @{
    Startup = @{
        Enabled       = $true
        IntervalHours = 24
        Scope         = @{ Default = "All"; Test = "Private" }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryUpdate.Startup
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.RepositoryUpdate.Startup

# Which groups the startup update would pull on this machine
Resolve-RepositoryUpdateScope -Path 'RepositoryUpdate.Startup.Scope'

# When it last ran (the next run is due IntervalHours after this)
Get-Item (Join-Path $global:LoggingState.LogsDir ".last-repository-update") -Force -ErrorAction SilentlyContinue | Select-Object LastWriteTime
```

To see a run without waiting for the interval, `Invoke-StartupRepositoryUpdate -Force -RedrawPrompt` does exactly what a new shell would, including drawing the prompt again under the summary (it updates repositories, so it is not read-only). To skip it for one shell, start it with `$env:WINUX_STARTUP_SKIP = "RepositoryUpdate"`.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    RepositoryUpdate = @{
        IncludeDefaultBranch = $true
        Startup              = @{
            Enabled       = $true
            IntervalHours = 24
            Scope         = @{ Default = "All"; Test = "Private" }
        }
    }
}
```

## Related

- [`Invoke-StartupRepositoryUpdate` in the Git module reference](../../../modules/git.md#invoke-startuprepositoryupdate) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [`Update-Repositories`](Update-Repositories.md) - what each run calls, and the default-branch setting
- [`Resolve-RepositoryUpdateScope`](../bootstrap/Resolve-RepositoryUpdateScope.md) - resolves the scope
- [`Measure-ShellStartup`](../system/Measure-ShellStartup.md) - the startup stages, `RepositoryUpdate` among them
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
