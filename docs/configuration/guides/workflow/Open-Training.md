# Open-Training

Opens the training Word document in Microsoft Word.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.TrainingFile`](../../configuration-reference.md#universal-paths) | string (file name) | `""` (empty) | The Word document `Open-Training` opens, joined onto `TrainingDirectory`. |
| [`PathTemplates.TrainingDirectory`](../../configuration-reference.md#path-templates--placeholder-system) | path string (placeholders allowed) | `""` (empty) | The folder the training document lives in, read at runtime from `$global:MachineSpecificPaths.TrainingDirectory`. |

## Decisions

1. Which Word document should `Open-Training` open?
    - Options: The document's file name, e.g. `Training.docx`.
    - Default: Empty - set it before using `Open-Training`.
    - More detail: [`Universal`](../../configuration-reference.md#universal-paths)
2. Which folder holds it?
    - Options: A path template, placeholders allowed, e.g. `{User}\Training\2026`.
    - Default: Empty - set it before using `Open-Training`.
    - More detail: [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

Both keys sit inside hashtables (`Universal`, `PathTemplates`) that deep-merge, so setting just these two keys leaves every other entry alone.

## Steps Overview

1. Set `Universal.TrainingFile`
2. Set `PathTemplates.TrainingDirectory`
3. Reload and confirm the merge landed

## Step 1: Set `Universal.TrainingFile`

The file name of the Word document to open.

```powershell
Universal = @{
    TrainingFile = "Training.docx"
}
```

## Step 2: Set `PathTemplates.TrainingDirectory`

The folder that holds the document. It is expanded per machine type into `$global:MachineSpecificPaths.TrainingDirectory`, so placeholders work here.

```powershell
PathTemplates = @{
    TrainingDirectory = "{User}\Training\2026"
}
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.TrainingFile
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.TrainingFile
$global:MachineSpecificPaths.TrainingDirectory
Test-Path (Join-Path $global:MachineSpecificPaths.TrainingDirectory $global:Configuration.Universal.TrainingFile)
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        TrainingFile = "Training.docx"
    }
    PathTemplates = @{
        TrainingDirectory = "{User}\Training\2026"
    }
}
```

## Related

- [`Open-Training` in the Workflow module reference](../../../modules/workflow.md#open-training) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
