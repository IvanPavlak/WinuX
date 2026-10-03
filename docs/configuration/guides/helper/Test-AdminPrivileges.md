# Test-AdminPrivileges

Verifies or requests Administrator privileges, and decides whether a non-elevated shell is asked before the command is rerun elevated.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AutoElevate`](../../configuration-reference.md#auto-elevate) | bool | `$false` | Whether a function that needs Administrator privileges, run from a non-elevated shell, relaunches in the Administrator PowerShell straight away (`$true`) or first asks "Do you want to open the Administrator PowerShell and rerun the command?" (`$false`). |

The Windows UAC consent dialog appears in both cases: it is raised by Windows for the elevated relaunch and cannot be suppressed from PowerShell. `AutoElevate` removes only the WinuX question in front of it. An explicit `-AutoElevate` or `-AutoElevate:$false` passed to `Test-AdminPrivileges` wins over the key, and `-CheckOnly` never reads it.

## Decisions

1. Should admin-only commands relaunch elevated without asking first?
    - Options: `$true` (skip the question, relaunch immediately) or `$false` (ask every time).
    - Default: `$false` - the question is asked.
    - More detail: [`AutoElevate`](../../configuration-reference.md#auto-elevate)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`AutoElevate` is a top-level scalar, so the value in your local file simply replaces the base `$false`.

## Steps Overview

1. Set `AutoElevate`
2. Reload and confirm the merge landed

## Step 1: Set `AutoElevate`

Opt in to relaunching without the confirmation question. Leave it out, or set `$false`, to keep the question.

```powershell
AutoElevate = $true
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.AutoElevate
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.AutoElevate
Get-ConfigSetting -Path 'AutoElevate' -Default $false
Test-AdminPrivileges -CheckOnly
```

If the value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AutoElevate = $true
}
```

## Related

- [`Test-AdminPrivileges` in the Helper module reference](../../../modules/helper.md#test-adminprivileges) - parameters, usage and behaviour
- [`Open-Terminal`](../application/Open-Terminal.md) - opens the elevated Windows Terminal tab the command is rerun in
- [Helper configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md)
