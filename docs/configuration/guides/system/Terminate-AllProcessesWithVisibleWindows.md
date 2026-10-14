# Terminate-AllProcessesWithVisibleWindows

Forcefully terminates all processes that own a visible, titled top-level window (found window-side through `Get-VisibleWindowProcess`), preserving the default exclusions used by the desktop cleanup flow: every browser declared in `Configuration.Universal.Browsers` (handled gracefully by `Terminate-AllBrowserProcesses` instead) plus every process named in the `Universal.VisibleWindowExclusions` configuration list (`Rainmeter...

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.VisibleWindowExclusions`](../../configuration-reference.md#process-cleanup) | array of process names | `Rainmeter`, `WindowsTerminal`, `Docker Desktop`, `obs64`, `PowerToys`, `PowerToys.FancyZones`, `PowerToys.Settings` | The processes never force-killed. An empty list makes the function warn and terminate nothing, since it would otherwise kill `WindowsTerminal` - the shell running the cleanup. The PowerToys entries are load-bearing. |
| [`Universal.Browsers`](../../configuration-reference.md#browser-configuration) | hashtable of browser name to `@{ Exe; ... }` | `Firefox`, `Tor`, `Chrome`, `Edge`, `Brave` | Every entry's `Exe` file name (without `.exe`) is added to the exclusions, because `Terminate-AllBrowserProcesses` closes those windows gracefully instead. |

## Decisions

1. Which processes must survive the force-kill?
    - Options: Process names (no `.exe`) in `Universal.VisibleWindowExclusions` - tray-style apps, recorders, anything whose window you never want killed. The list is an array, so copy the whole base list and add to it: keep `WindowsTerminal` and the three PowerToys entries. For a one-off, pass `-Exclude` (window-title patterns) instead.
    - Default: The shipped seven names.
    - More detail: [`Universal.VisibleWindowExclusions`](../../configuration-reference.md#process-cleanup)
2. Are all your browsers in `Universal.Browsers`?
    - Options: A browser listed there is spared here and closed gracefully by `Terminate-AllBrowserProcesses`; a browser NOT listed is treated like any other app and force-killed. Hashtables merge per key, so adding one browser does not remove the others.
    - Default: The shipped five.
    - More detail: [`Universal.Browsers`](../../configuration-reference.md#browser-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal.VisibleWindowExclusions`
2. Reload and confirm the merge landed

## Step 1: Set `Universal.VisibleWindowExclusions`

`Universal` is a hashtable, so this key merges over the base; the array itself replaces the base list wholesale, which is why the shipped names are restated. `Universal.Browsers` rarely needs touching - see the [`Terminate-AllBrowserProcesses` guide](Terminate-AllBrowserProcesses.md).

```powershell
Universal = @{
    VisibleWindowExclusions = @(
        "Rainmeter"
        "WindowsTerminal"
        "Docker Desktop"
        "obs64"
        "PowerToys"
        "PowerToys.FancyZones"
        "PowerToys.Settings"
        "MyTrayApp"
    )
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.VisibleWindowExclusions
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.VisibleWindowExclusions
$global:Configuration.Universal.Browsers.Values.Exe
Get-VisibleWindowProcess | Select-Object ProcessName, Id, WindowTitles
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        VisibleWindowExclusions = @(
            "Rainmeter"
            "WindowsTerminal"
            "Docker Desktop"
            "obs64"
            "PowerToys"
            "PowerToys.FancyZones"
            "PowerToys.Settings"
            "MyTrayApp"
        )
    }
}
```

## Related

- [`Terminate-AllProcessesWithVisibleWindows` in the System module reference](../../../modules/system.md#terminate-allprocesseswithvisiblewindows) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Report-KillAllSurvivors`](Report-KillAllSurvivors.md) - reads the same exclusion list
- [`Terminate-AllBrowserProcesses`](Terminate-AllBrowserProcesses.md) - closes the excluded browsers gracefully
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
