# Expand-WorkspaceTemplates

Expands every templated `WorkspaceActions` entry of the loaded configuration once, right after `Configuration.local.psd1` is merged, so every reader of `WorkspaceActions` sees plain action lists.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | ordered list of single-key hashtables | 5 entries, `WinuX` templated | Every templated entry is replaced in place by its expanded action list; every plain entry gets its `{Workspace}` token substituted. |
| [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates) | hashtable of template name to `@{ Variables; Actions }` | `@{ Project = ... }` | The templates the entries stamp out (through `Resolve-WorkspaceTemplate`). |

The function also writes two runtime keys that are not configuration settings and never belong in a configuration file: `WorkspaceTemplateEntries` (the raw templated definitions, which `Open-Workspace` expands again when the command line sets a variable) and `WorkspaceTemplateErrors` (the problems found, which `Test-ConfigurationSchema` reports).

## Decisions

1. Which workspaces should be templated?
    - Options: Any workspace whose actions follow a shared pattern can become `@{ <Name> = @{ Template = "<template>" } }`; the rest stay plain action lists. Both shapes can sit side by side in one `WorkspaceActions` list.
    - Default: Only the shipped `WinuX` workspace is templated (`Project` template).
    - More detail: [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates)
2. Should a broken template block the shell?
    - Options: It never does - a templated entry that does not expand is logged at load (`... - the workspace opens nothing until this is fixed`), stays in the workspace menu, and opening it repeats the errors and runs nothing. Fix the entry, or temporarily turn it back into a plain action list.
    - Default: Errors are logged on every load unless the load is `-Quiet`.
    - More detail: [`WorkspaceActions`](../../configuration-reference.md#workspace-actions)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`WorkspaceTemplates` is the exception to the hashtable rule: it merges template by template, so a local template replaces the base template of the same name whole.

## Steps Overview

1. Template a workspace in `WorkspaceActions`
2. Reload and confirm the merge landed

## Step 1: Template a workspace in `WorkspaceActions`

Turn a workspace into a templated entry. Keep every other entry of the base list you want - a local `WorkspaceActions` replaces the base list.

```powershell
WorkspaceActions = @(
    @{ Default = @( @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") } } ) }
    @{ MyProject = @{ Template = "Project" } }
)
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
Get-OrderedEntry $global:Configuration.WorkspaceActions "MyProject"
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
(Get-OrderedEntry $global:Configuration.WorkspaceActions "MyProject") | ForEach-Object { $_.Action }
$global:Configuration.WorkspaceTemplateEntries.Keys
$global:Configuration.WorkspaceTemplateErrors
Test-ConfigurationSchema
```

The first line shows the expanded action list, the second which workspaces are templated, and the last two report any template problem with the workspace named.

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    WorkspaceTemplates = @{
        Project = @{
            Variables = @{ Repository = "{Workspace}" }
            Actions   = @(
                @{ Action = "Open-Browser"; Parameters = @{ Groups = @("{Repository}") } }
                @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{Workspace}" } }
                @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
            )
        }
    }
    WorkspaceActions = @(
        @{ Default = @( @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") } } ) }
        @{ MyProject = @{ Template = "Project" } }
        @{ MyRepo = @{ Template = "Project"; Variables = @{ Repository = "MyRepoDocs" } } }
    )
}
```

## Related

- [`Expand-WorkspaceTemplates` in the Helper module reference](../../../modules/helper.md#expand-workspacetemplates) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Resolve-WorkspaceTemplate`](Resolve-WorkspaceTemplate.md) - expands one entry; the template rules in detail
- [`Load-PathConfiguration`](../bootstrap/Load-PathConfiguration.md) - calls this function after the local merge
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
