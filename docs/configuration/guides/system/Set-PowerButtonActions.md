# Set-PowerButtonActions

Configures what happens when the power button is pressed, the sleep button is pressed, or the laptop lid is closed, for both battery and plugged-in states.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PowerButtonActions`](../../configuration-reference.md#power-button-actions) | hashtable of machine type to action settings | `@{}` (empty) | What `Set-PowerButtonActions -Auto` makes the power button, sleep button and lid do on this machine type (`PowerButtonOnBattery`, `PowerButtonPluggedIn`, `SleepButtonOnBattery`, `SleepButtonPluggedIn`, `LidCloseOnBattery`, `LidClosePluggedIn`: `DoNothing` / `Sleep` / `Hibernate` / `ShutDown`), plus the `DisableFastStartup` / `DisableSleep` / `DisableHibernate` booleans. A key the entry leaves out is not managed: that action or toggle stays as it is. Ships empty. |

## Decisions

1. What should the buttons and the lid do on this machine type?
    - Options: A `@{ <MachineType> = @{ ... } }` entry with any of the six action keys, each `DoNothing`, `Sleep`, `Hibernate` or `ShutDown`. Actions you leave out are not managed and stay as they are.
    - Default: Empty - `-Auto` warns and leaves the power settings as-is.
    - More detail: [`PowerButtonActions`](../../configuration-reference.md#power-button-actions)
2. Should Fast Startup, Sleep and Hibernate be disabled?
    - Options: `DisableFastStartup`, `DisableSleep`, `DisableHibernate` in the same machine-type entry, each `$true` or `$false`. Leave one out to keep it unmanaged, for example `DisableFastStartup` when Win11Debloat owns Fast Startup.
    - Default: All three unmanaged.
    - More detail: [`PowerButtonActions`](../../configuration-reference.md#power-button-actions)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PowerButtonActions`
2. Reload and confirm the merge landed

## Step 1: Set `PowerButtonActions`

What `Set-PowerButtonActions -Auto` makes the power button, sleep button and lid do, per machine type. Ships empty.

```powershell
PowerButtonActions = @{
    Laptop = @{
        PowerButtonOnBattery = "ShutDown"
        PowerButtonPluggedIn = "ShutDown"
        LidCloseOnBattery    = "Sleep"
        LidClosePluggedIn    = "DoNothing"
        DisableHibernate     = $true
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.PowerButtonActions
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.PowerButtonActions
powercfg /query SCHEME_CURRENT SUB_BUTTONS
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PowerButtonActions = @{
        Laptop = @{
            PowerButtonOnBattery = "ShutDown"
            PowerButtonPluggedIn = "ShutDown"
            SleepButtonOnBattery = "DoNothing"
            SleepButtonPluggedIn = "DoNothing"
            LidCloseOnBattery    = "Sleep"
            LidClosePluggedIn    = "DoNothing"
            DisableFastStartup   = $true
            DisableSleep         = $false
            DisableHibernate     = $true
        }
    }
}
```

## Related

- [`Set-PowerButtonActions` in the System module reference](../../../modules/system.md#set-powerbuttonactions) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
