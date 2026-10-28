# Report-KillAllSurvivors

The closing audit of `Kill-All`: lists every visible application window still standing that is neither a `Universal.VisibleWindowExclusions` process nor an `-Exclude` match, and returns them so the run ends on a warning instead of a success line.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.VisibleWindowExclusions`](../../configuration-reference.md#process-cleanup) | array of process names | `Rainmeter`, `WindowsTerminal`, `Docker Desktop`, `obs64`, `PowerToys`, `PowerToys.FancyZones`, `PowerToys.Settings` | The processes whose windows are expected to outlive a `Kill-All` and are therefore never reported (matched case-insensitively on the process name). The same list `Terminate-AllProcessesWithVisibleWindows` spares. Browsers are NOT exempt here. Empty means every window still standing is reported. |

## Decisions

1. Which processes' windows may survive a `Kill-All` without being reported?
    - Options: Process names (no `.exe`) in `Universal.VisibleWindowExclusions`. The list is shared with `Terminate-AllProcessesWithVisibleWindows`, so a name added here is also never force-killed - keep `WindowsTerminal` and the three PowerToys entries. For a one-off, pass `-Exclude` (title or process-name patterns) to `Kill-All` instead.
    - Default: The shipped seven names.
    - More detail: [`Universal.VisibleWindowExclusions`](../../configuration-reference.md#process-cleanup)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `Universal.VisibleWindowExclusions` - it is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `Universal.VisibleWindowExclusions`
2. Reload and confirm the merge landed

## Step 1: Set `Universal.VisibleWindowExclusions`

`Universal` is a hashtable, so this key merges over the base; the array itself replaces the base list wholesale, which is why the shipped names are restated.

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

Read-only checks. None of these change anything - `Report-KillAllSurvivors` only lists windows, it closes nothing.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.VisibleWindowExclusions
Report-KillAllSurvivors
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

- [`Report-KillAllSurvivors` in the System module reference](../../../modules/system.md#report-killallsurvivors) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [`Terminate-AllProcessesWithVisibleWindows`](Terminate-AllProcessesWithVisibleWindows.md) - reads the same configuration
- [`Kill-All`](Kill-All.md) - the caller
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
