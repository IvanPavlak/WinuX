# Resolve-VisibleWindowExclusions

Returns the process names of `Universal.VisibleWindowExclusions` that apply to this machine: the processes `Kill-All` never force-kills or reports, and a workspace open never adopts.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.VisibleWindowExclusions`](../../configuration-reference.md#process-cleanup) | array of process names or `@{ Name; Machine }` entries | `Rainmeter`, `WindowsTerminal`, `Docker Desktop`, `obs64`, `PowerToys`, `PowerToys.FancyZones`, `PowerToys.Settings` | The processes a teardown leaves alone. A plain name applies on every machine; `@{ Name = "<process>"; Machine = "PC/Work" }` applies only on the machine types its `Machine` scope names. |
| [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types) | array of machine types | `Test` | The tokens a `Machine` scope may use; an unknown one is reported and the entry never applies. |

## Decisions

1. Which processes should outlive a `Kill-All` everywhere?
    - Options: Process names (no `.exe`) as plain entries. Keep `WindowsTerminal` and the three PowerToys entries.
    - Default: The shipped seven names.
    - More detail: [`Universal.VisibleWindowExclusions`](../../configuration-reference.md#process-cleanup)
2. Should any process outlive a `Kill-All` only on some machines?
    - Options: An entry `@{ Name = "<process>"; Machine = "PC" }` (several types joined with `/`), for example an agent app that keeps running on the machine that hosts the agents.
    - Default: None.
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

The shipped names are restated because the array replaces the base list wholesale; the last entry applies only on a PC.

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
        @{ Name = "MyAgentApp"; Machine = "PC" }
    )
}
```

## Step 2: Reload and confirm the merge landed

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.VisibleWindowExclusions
```

## Verification

Read-only checks. `Resolve-VisibleWindowExclusions` only reads the configuration; `-MachineType` shows what another machine type would get.

```powershell
Reload-PowerShellProfile
Resolve-VisibleWindowExclusions
Resolve-VisibleWindowExclusions -MachineType Laptop
```

If a scoped entry is missing on the machine it names, check that its `Machine` tokens are in `ValidMachineTypes` (an unknown token is logged as an error) and that `$global:MachineType` is what you expect.

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
            @{ Name = "MyAgentApp"; Machine = "PC" }
        )
    }
}
```

## Related

- [`Resolve-VisibleWindowExclusions` in the System module reference](../../../modules/system.md#resolve-visiblewindowexclusions) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [`Terminate-AllProcessesWithVisibleWindows`](Terminate-AllProcessesWithVisibleWindows.md), [`Report-KillAllSurvivors`](Report-KillAllSurvivors.md) and [`Get-WorkspaceOpenDelta`](../workflow/Get-WorkspaceOpenDelta.md) - read the list through this function
- [`Kill-All`](Kill-All.md) - the caller
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
