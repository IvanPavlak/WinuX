# List-Functions

Parses the per-module documentation pages under `docs/modules/*.md` (and the fork-owned `docs/custom/*.md` pages, when present) to extract every documented function's name, signature, and description, then lists them grouped by module category with a total count.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`FunctionDiscrepancyExclusions`](../../configuration-reference.md#more-sections-quick-reference) | array of function names | array of 3 (`"Install-Bootstrap"`, `"fastfetch"`, `"Get-PoshStackCount"`) | Names `List-Functions -ListDiscrepancies` deliberately ignores, in BOTH directions - things that are not exported module functions: a documented standalone script, or a function the profile chain defines rather than a module. |
| [`ListFunctionsColors`](../../configuration-reference.md#console-colors) | hashtable, 3 keys | `@{ Border = "DarkCyan"; DiscrepancyError = "Red"; DiscrepancySuccess = "Green" }` | Console colours `List-Functions` prints with. |

## Decisions

1. Is any name being wrongly reported as a discrepancy, in either direction?
    - Options: Add it to the array. Supply the whole array, since arrays replace - copy the three shipped entries out of the base first.
    - Default: The three shipped entries.
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

Names `List-Functions -ListDiscrepancies` deliberately ignores, in both directions - things that are not exported module functions.

Two kinds end up here. A standalone script that is documented but never exported shows up as
documented-but-not-loaded (`Install-Bootstrap`). A function the PROFILE defines shows up the
other way round, but only after a reload: `Reload-PowerShellProfile` dot-sources the profile
chain from inside the System module, and PowerShell stamps the defining module onto every
function created during that call - even one declared `global:` - so it reports an empty
`ModuleName` in a fresh session and `System` after a reload, at which point the check reads it
as an undocumented System export. `fastfetch` (the all-hosts profile's image-logo wrapper) and
`Get-PoshStackCount` (defined by oh-my-posh's own init) are both that case.

The mirror image needs no configuration. A module function the profile REDEFINES in global scope
loses its module attribution, so the per-module enumeration stops reporting it even though the
session has it - `Initialize-OhMyPosh` and `Test-PowerPlan` are dot-sourced by the profile for
exactly that reason. Those are not excluded and should not be: a documented function counts as
loaded when it resolves at all, so they pass on their own, and one that is genuinely absent
still fails.

The array replaces wholesale, so copy the shipped entries before adding your own:

```powershell
FunctionDiscrepancyExclusions = @("Install-Bootstrap", "fastfetch", "Get-PoshStackCount", "My-ForkOnlyScript")
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
    FunctionDiscrepancyExclusions = @("Install-Bootstrap", "fastfetch", "Get-PoshStackCount", "My-ForkOnlyScript")
    ListFunctionsColors = @{ Border = "DarkGray" }
}
```

## Related

- [`List-Functions` in the Helper module reference](../../../modules/helper.md#list-functions) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
