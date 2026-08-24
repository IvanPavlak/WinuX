# Open-Acrobat

Opens Adobe Acrobat with one or more PDF groups defined in `AcrobatPdfGroups` in `Configuration.psd1`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`AcrobatGroups`](../../configuration-reference.md#acrobat-configuration) | array of strings | array of 1 (`"ExampleRulebook"`) | The named PDF groups `Open-Acrobat` offers. A group name here must have a matching entry in `AcrobatPdfGroups`. |
| [`AcrobatPdfGroups`](../../configuration-reference.md#acrobat-configuration) | hashtable of group name to file array | hashtable, 1 key | The actual PDF paths behind each `AcrobatGroups` name. Paths accept placeholders such as `{User}` and `{Dev}`. |

## Decisions

1. Which PDF collections do you want to open by name?
    - Options: One group name per collection, e.g. `Manuals`, `Contracts`, `Rulebooks`. Replaces the shipped `ExampleRulebook` entry.
    - Default: Leave the shipped example alone and skip - `Open-Acrobat` then only offers `ExampleRulebook`.
    - More detail: [`AcrobatGroups`](../../configuration-reference.md#acrobat-configuration)
2. Which PDF files belong to each group?
    - Options: Absolute paths, or placeholder paths like `{User}\Documents\Manuals\Router.pdf`.
    - Default: Skip - the shipped `ExampleRulebook` group points at a sample path and `Open-Acrobat` reports a missing file rather than failing.
    - More detail: [`AcrobatPdfGroups`](../../configuration-reference.md#acrobat-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `AcrobatGroups` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `AcrobatGroups`
2. Set `AcrobatPdfGroups`
3. Reload and confirm the merge landed

## Step 1: Set `AcrobatGroups`

The named PDF groups `Open-Acrobat` offers. A group name here must have a matching entry in `AcrobatPdfGroups`.

```powershell
AcrobatGroups = @("Manuals")
```

## Step 2: Set `AcrobatPdfGroups`

The actual PDF paths behind each `AcrobatGroups` name. Paths accept placeholders such as `{User}` and `{Dev}`.

```powershell
AcrobatPdfGroups = @{
    Manuals = @(
        "{User}\Documents\Manuals\Router.pdf"
        "{User}\Documents\Manuals\Monitor.pdf"
    )
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.AcrobatGroups
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.AcrobatGroups
$global:Configuration.AcrobatPdfGroups
Open-Acrobat              # interactive menu
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    AcrobatGroups = @("Manuals")
    AcrobatPdfGroups = @{
        Manuals = @(
            "{User}\Documents\Manuals\Router.pdf"
            "{User}\Documents\Manuals\Monitor.pdf"
        )
    }
}
```

## Related

- [`Open-Acrobat` in the Application module reference](../../../modules/application.md#open-acrobat) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [Add Browser Group](add-browser-group.md) - browser groups, nesting, unique names, search and per-browser selection
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
