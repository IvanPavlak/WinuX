# Terminate-AllBrowserProcesses

Gracefully terminates every browser declared in `Configuration.Universal.Browsers` (Firefox, Tor, Chrome, Edge, Brave) by posting `WM_CLOSE` to each browser's visible top-level windows.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.Browsers`](../../configuration-reference.md#browser-configuration) | hashtable of browser name to `@{ Exe; PrivateArg; NewWindowArg }` | `Firefox`, `Tor`, `Chrome`, `Edge`, `Brave` | The browsers whose windows are closed. Only `Exe` is read here: its file name without `.exe` is the process name targeted. An entry without `Exe`, or with a name `Get-BrowserTitlePattern` does not know (anything but the shipped five), is skipped. |

## Decisions

1. Are the shipped browser executables the ones installed on this machine?
    - Options: Override `Universal.Browsers.<Name>.Exe` with an absolute or placeholder path. Only the file name matters to this function (it becomes the process name), so a browser installed elsewhere under the same file name needs no change.
    - Default: The shipped default install locations.
    - More detail: [`Universal.Browsers`](../../configuration-reference.md#browser-configuration)
2. Do you use a browser the base `Browsers` map does not list?
    - Options: You can add an entry for `Open-Browser`, but this function only closes the five browsers `Get-BrowserTitlePattern` knows, so an added browser is neither closed here nor force-killed by `Terminate-AllProcessesWithVisibleWindows` (every `Browsers` executable is excluded there) - `Report-KillAllSurvivors` lists its windows instead.
    - Default: The shipped five.
    - More detail: [`Universal.Browsers`](../../configuration-reference.md#browser-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal.Browsers`
2. Reload and confirm the merge landed

## Step 1: Set `Universal.Browsers`

Only needed when a browser's executable lives somewhere the base does not expect. `Universal` and `Browsers` are hashtables, so overriding one browser's `Exe` leaves every other key as shipped.

```powershell
Universal = @{
    Browsers = @{
        Brave = @{
            Exe = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
        }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.Browsers
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.Browsers.Keys
$global:Configuration.Universal.Browsers.Values.Exe
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        Browsers = @{
            Brave = @{
                Exe = "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe"
            }
        }
    }
}
```

## Related

- [`Terminate-AllBrowserProcesses` in the System module reference](../../../modules/system.md#terminate-allbrowserprocesses) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Open-Browser`](../application/Open-Browser.md) - reads the same configuration
- [`Terminate-AllProcessesWithVisibleWindows`](Terminate-AllProcessesWithVisibleWindows.md) - excludes the same browsers from its force-kill
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
