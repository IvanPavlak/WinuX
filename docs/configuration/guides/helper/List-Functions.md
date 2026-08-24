# List-Functions

Parses the per-module documentation pages under `docs/modules/*.md` (and the fork-owned `docs/custom/*.md` pages, when present) to extract every documented function's name, signature, and description, then lists them grouped by module category with a total count.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`FunctionDiscrepancyExclusions`](../../configuration-reference.md#more-sections-quick-reference) | array of function names | array of 1 (`"Install-Bootstrap"`) | Functions `List-Functions -ListDiscrepancies` deliberately ignores - scripts that are not exported module functions. |
| [`ListFunctionsColors`](../../configuration-reference.md#console-colors) | hashtable, 3 keys | `@{ Border = "DarkCyan"; DiscrepancyError = "Red"; DiscrepancySuccess = "Green" }` | Console colours `List-Functions` prints with. |

## Decisions

1. Is any name being wrongly reported as a discrepancy?
    - Options: Add it to the array. Supply the whole array, since arrays replace.
    - Default: The shipped single entry.
    - More detail: [`FunctionDiscrepancyExclusions`](../../configuration-reference.md#more-sections-quick-reference)
2. Do you want different colours in the function list?
    - Options: Any `[ConsoleColor]` name.
    - Default: DarkCyan / Red / Green.
    - More detail: [`ListFunctionsColors`](../../configuration-reference.md#console-colors)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `FunctionDiscrepancyExclusions` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `FunctionDiscrepancyExclusions`
2. Set `ListFunctionsColors`
3. Reload and confirm the merge landed

## Step 1: Set `FunctionDiscrepancyExclusions`

Functions `List-Functions -ListDiscrepancies` deliberately ignores - scripts that are not exported module functions.

```powershell
FunctionDiscrepancyExclusions = @("Install-Bootstrap", "My-ForkOnlyScript")
```

## Step 2: Set `ListFunctionsColors`

Console colours `List-Functions` prints with.

```powershell
ListFunctionsColors = @{ Border = "DarkGray" }
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.FunctionDiscrepancyExclusions
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.FunctionDiscrepancyExclusions
$global:Configuration.ListFunctionsColors
List-Functions
List-Functions -ListDiscrepancies    # must report none
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    FunctionDiscrepancyExclusions = @("Install-Bootstrap", "My-ForkOnlyScript")
    ListFunctionsColors = @{ Border = "DarkGray" }
}
```

## Related

- [`List-Functions` in the Helper module reference](../../../modules/helper.md#list-functions) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
