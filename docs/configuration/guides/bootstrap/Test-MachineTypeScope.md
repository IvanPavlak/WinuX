# Test-MachineTypeScope

Tests whether a machine-scope string (`All`, `PC`, `PC/Laptop`, ...) applies to a machine type, validating every token against `ValidMachineTypes` plus the `All` wildcard.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types) | array of strings | `@("Test")` | The machine types WinuX accepts. `DetermineMachineType` refuses anything not listed, and `Test-MachineTypeScope` uses it to decide whether a CSV row or a step applies. |

This is the gate behind the `Machine` column in the app CSVs and behind the per-machine-type step toggles. A scope of `All` (or blank) applies everywhere; a comma-separated list applies only to the named types; a `!Type` entry excludes one.

## Decisions

1. Which machine types do you use?
    - Options: One name per type, e.g. `@("Test", "Machine", "Laptop", "Work")` - see [Add New Machine](../bootstrap/add-new-machine.md). The array replaces wholesale, so keep `Test` in the list unless you really mean to drop it.
    - Default: `@("Test")`.
    - More detail: [`ValidMachineTypes`](../../configuration-reference.md#valid-machine-types)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ValidMachineTypes` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `ValidMachineTypes`
2. Reload and confirm the merge landed

## Step 1: Set `ValidMachineTypes`

The machine types WinuX accepts. `DetermineMachineType` refuses anything not listed, and `Test-MachineTypeScope` uses it to decide whether a CSV row or a step applies.

```powershell
ValidMachineTypes = @("Test", "Machine", "Laptop")
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.ValidMachineTypes
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.ValidMachineTypes
Test-MachineTypeScope -Scope "Test" -MachineType $global:MachineType -Context "manual check"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ValidMachineTypes = @("Test", "Machine", "Laptop")
}
```

## Related

- [`Test-MachineTypeScope` in the Bootstrap module reference](../../../modules/bootstrap.md#test-machinetypescope) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
- [Add New Machine](add-new-machine.md) - the full 7-step walk for bringing a new machine type online
- [`DetermineMachineType`](DetermineMachineType.md) - reads the same configuration
- [`Save-AppCsvOverlay`](../configuration/Save-AppCsvOverlay.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
