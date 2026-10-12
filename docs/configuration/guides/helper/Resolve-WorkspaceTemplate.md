# Resolve-WorkspaceTemplate

Expands one `WorkspaceActions` entry into the plain action list `Open-Workspace` runs: a templated entry stamps out its `WorkspaceTemplates` entry under its own name, with its variables, overrides and additions applied.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates) | hashtable of template name to `@{ Variables; Actions }` | `@{ Project = ... }` (one generic template) | The action lists templated workspaces stamp out. `Variables` hold defaults (`{Workspace}` and other variables may be referenced); each action may carry an optional `Id` for overrides and anchors. |
| [`WorkspaceActions`](../../configuration-reference.md#workspace-actions) | ordered list of single-key hashtables | 5 entries (`Default`, `Example`, `Fullscreen`, `Empty`, `WinuX` - the last one templated) | A templated entry is `@{ <Name> = @{ Template = "<template>"; Variables = @{...}; Overrides = @{...}; Add = @(...) } }`. A plain entry (an action list) only gets `{Workspace}` substituted. |

## Decisions

1. Do several workspaces share the same action list?
    - Options: Write the list once as a `WorkspaceTemplates` entry and give each workspace a one-line templated entry (`@{ MyProject = @{ Template = "Project" } }`), or keep writing plain action lists. Each templated workspace still keeps its own name, layout file, tracker entry and Obsidian workspace.
    - Default: The shipped `Project` template (browser group, VS Code folder, layout, desktop 1, close the launching tab) used by the `WinuX` workspace.
    - More detail: [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates)
2. What differs between the workspaces, and is it a value or an action?
    - Options: A value that differs (a browser group name, a folder) is a template variable (`Variables = @{ Repository = "{Workspace}" }`) set per entry in `Variables` or for one open on the command line (`-Repository OtherGroup`). A different parameter set on one action is an `Overrides` entry keyed by the action's `Id` or name (`$null` drops a parameter or the whole action). An extra action is an `Add` entry (before the template's first `Set-WorkspaceWindowLayout` unless it names a `Before` / `After` anchor).
    - Default: No variables beyond the template's defaults, no overrides, no additions.
    - More detail: [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates)
3. Does any template action need a stable `Id`?
    - Options: Give an action an `Id` when the template holds the same action twice (two `Open-Browser` actions) - an override or anchor by action name is then ambiguous and reported as an error. Otherwise the action name is enough.
    - Default: No `Id`s; override and anchor by action name.
    - More detail: [`WorkspaceTemplates`](../../configuration-reference.md#workspace-templates)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites twice. `WorkspaceActions` is an ordered list, so a local `WorkspaceActions` is the complete workspace list - copy the base entries you want to keep. `WorkspaceTemplates` is merged template by template instead of deep-merged: a local template replaces the base template of the same name whole, so a local `Project` must carry its complete `Actions` (and `Variables`).

## Steps Overview

1. Define the template in `WorkspaceTemplates`
2. Stamp it out in `WorkspaceActions`
3. Reload and confirm the merge landed

## Step 1: Define the template in `WorkspaceTemplates`

Write the shared action list once. `{Workspace}` is the entry's own name; any other `{Name}` must be a declared variable.

```powershell
WorkspaceTemplates = @{
    Repo = @{
        Variables = @{ Repository = "{Workspace}" }
        Actions   = @(
            @{ Id = "Docs"; Action = "Open-Browser"; Parameters = @{ Groups = @("{Repository}") } }
            @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{Workspace}" } }
            @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
            @{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
        )
    }
}
```

## Step 2: Stamp it out in `WorkspaceActions`

One line per workspace, plus `Variables`, `Overrides` or `Add` where a workspace differs. `Add-Workspace -Name MyProject -Template Repo` writes the one-line form for you.

```powershell
WorkspaceActions = @(
    @{ MyProject = @{ Template = "Repo" } }
    @{ MyRepo = @{
            Template  = "Repo"
            Variables = @{ Repository = "MyRepoDocs" }
            Overrides = @{ Docs = @{ Parameters = @{ Groups = @("{Repository}", "AI") } } }
            Add       = @( @{ Action = "Open-Obsidian"; After = "Open-VSCode" } )
        }
    }
)
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it. After the reload `WorkspaceActions` already holds the expanded lists; the raw templated definitions sit under `WorkspaceTemplateEntries`.

```powershell
Reload-PowerShellProfile
$global:Configuration.WorkspaceTemplates.Repo
$global:Configuration.WorkspaceTemplateEntries.MyRepo
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Test-ConfigurationSchema
$global:Configuration.WorkspaceTemplateErrors
(Resolve-WorkspaceTemplate -Name MyRepo -Definition $global:Configuration.WorkspaceTemplateEntries.MyRepo).Actions | ForEach-Object { $_.Action }
(Resolve-WorkspaceTemplate -Name MyRepo -Definition $global:Configuration.WorkspaceTemplateEntries.MyRepo -Variables @{ Repository = "OtherGroup" }).Actions
```

`Test-ConfigurationSchema` and `WorkspaceTemplateErrors` list every problem with the workspace named (`WorkspaceActions.MyRepo - unknown template [Rpeo] ...`). The last call previews what `Open-Workspace MyRepo -Repository OtherGroup` would run.

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    WorkspaceTemplates = @{
        Repo = @{
            Variables = @{ Repository = "{Workspace}" }
            Actions   = @(
                @{ Id = "Docs"; Action = "Open-Browser"; Parameters = @{ Groups = @("{Repository}") } }
                @{ Action = "Open-VSCode"; Parameters = @{ Folder = "{Workspace}" } }
                @{ Action = "Set-WorkspaceWindowLayout"; Parameters = @{ WorkspaceName = "{Workspace}" } }
                @{ Action = "Focus-VirtualDesktop"; Parameters = @{ DesktopNumber = 1 } }
            )
        }
    }
    WorkspaceActions = @(
        @{ Default = @(
                @{ Action = "Open-Browser"; Parameters = @{ Groups = @("AI") } }
            )
        }
        @{ MyProject = @{ Template = "Repo" } }
        @{ MyRepo = @{
                Template  = "Repo"
                Variables = @{ Repository = "MyRepoDocs" }
                Overrides = @{ Docs = @{ Parameters = @{ Groups = @("{Repository}", "AI") } } }
                Add       = @( @{ Action = "Open-Obsidian"; After = "Open-VSCode" } )
            }
        }
    )
}
```

## Related

- [`Resolve-WorkspaceTemplate` in the Helper module reference](../../../modules/helper.md#resolve-workspacetemplate) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Expand-WorkspaceTemplates`](Expand-WorkspaceTemplates.md) - expands every entry once at load
- [Add New Workspace](../workflow/add-new-workspace.md) - workspaces, action ordering and layouts
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
