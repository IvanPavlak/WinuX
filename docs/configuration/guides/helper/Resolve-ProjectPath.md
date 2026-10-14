# Resolve-ProjectPath

Resolves a project's file paths from the configuration mappings.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`ProjectTerminals`](../../configuration-reference.md#project-terminals) | array of `@{ Name; BasePath; Paths }` | array of 3 | The project lookup in the default mode: the entry whose `Name` matches `-ProjectName`. `BasePath` is dot-notation into the machine-specific paths (e.g. `Projects.MyProject`), and `Paths` names the subpath keys under it that are returned - all of them, or only the one `-PathKey` names. |
| [`RepositoryGroups`](../../configuration-reference.md#repository-groups) | array of single-key hashtables | array of 1 | The repository lookup with `-ForRepository`: group name to an array of `@{ Name; UrlPath; LocalPath }` entries. `UrlPath` is dot-notation into `Universal.GitHub` and `LocalPath` dot-notation into the machine-specific paths - resolving both is exactly what `Resolve-ProjectPath -ForRepository` does. |
| [`Universal.GitHub`](../../configuration-reference.md#github-configuration) | hashtable | `@{ Base = "https://github.com"; Private = @{ WinuX = "/YourUsername/WinuX.git" } }` | With `-ForRepository`: the value a `UrlPath` resolves to inside this hashtable is appended to `Base` to form the returned `RepositoryUrl`. |
| [`PathTemplates.Projects`](../../configuration-reference.md#path-templates--placeholder-system) | hashtable of project name to path fields | `Self` and `ExampleProject` | What `BasePath` and `LocalPath` resolve into, once `Expand-ConfigPaths` has expanded it into `$global:MachineSpecificPaths.Projects`. A project or path key missing here is reported as a null path segment. |

## Decisions

1. Which projects should resolve, and to which of their paths?
    - Options: One `ProjectTerminals` entry per project, with `BasePath` pointing at its `PathTemplates.Projects` entry and `Paths` naming the subpath keys (`ROOT`, `API`, `UI`, ...).
    - Default: The shipped three entries.
    - More detail: [`ProjectTerminals`](../../configuration-reference.md#project-terminals)
2. Which repositories should `-ForRepository` resolve?
    - Options: One `RepositoryGroups` entry per repository, in any group, carrying `Name`, `UrlPath` and `LocalPath` - see [Add New Repository](../git/add-new-repository.md).
    - Default: The shipped single example group (`WinuX`).
    - More detail: [`RepositoryGroups`](../../configuration-reference.md#repository-groups)
3. What is your GitHub base URL, and which repository paths does it combine with?
    - Options: `Universal.GitHub.Base` (e.g. `https://github.com` or `https://YourUsername@github.com`) plus one `"<Name>" = "/<owner>/<repo>.git"` entry per repository under a group such as `Private`.
    - Default: `https://github.com` and the placeholder `WinuX` entry.
    - More detail: [`Universal.GitHub`](../../configuration-reference.md#github-configuration)
4. Where does each project live on this machine?
    - Options: A `PathTemplates.Projects.<Project>` hashtable with a `Root` and any subpaths (`Api`, `Ui`, ...), written with placeholders such as `{Dev}` so the same entry resolves on every machine.
    - Default: The shipped `Self` and `ExampleProject` entries.
    - More detail: [`PathTemplates.Projects`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `ProjectTerminals`, `RepositoryGroups` - those keys are arrays, so whatever you write is the complete value.

## Steps Overview

1. Set `ProjectTerminals`
2. Set `RepositoryGroups`
3. Set `Universal.GitHub`
4. Set `PathTemplates.Projects`
5. Reload and confirm the merge landed

## Step 1: Set `ProjectTerminals`

The project lookup in the default mode. `BasePath` is dot-notation into the machine-specific paths, and `Paths` names the subpath keys under it that are returned.

```powershell
ProjectTerminals = @(
    @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("ROOT", "API") }
)
```

## Step 2: Set `RepositoryGroups`

The repository lookup with `-ForRepository`. `UrlPath` and `LocalPath` are dot-notation paths, not literal values - resolving them is exactly what `Resolve-ProjectPath -ForRepository` does.

```powershell
RepositoryGroups = @(
    @{ Personal = @(
            @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root" }
        )
    }
)
```

## Step 3: Set `Universal.GitHub`

`Base` plus the value a `UrlPath` resolves to is the returned `RepositoryUrl`. A leading `Universal.GitHub.` in `UrlPath` is optional - it is stripped before the walk.

```powershell
Universal = @{
    GitHub = @{
        Base    = "https://github.com"
        Private = @{ MyRepo = "/YourUsername/MyRepo.git" }
    }
}
```

## Step 4: Set `PathTemplates.Projects`

What `BasePath` and `LocalPath` resolve into. Path keys are matched case-insensitively, so `ROOT` in `Paths` reads `Root` here.

```powershell
PathTemplates = @{
    Projects = @{
        MyProject = @{ Root = "{Dev}\MyProject"; Api = "{Dev}\MyProject\src\Api" }
        MyRepo    = @{ Root = "{Dev}\MyRepo" }
    }
}
```

## Step 5: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectTerminals
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.ProjectTerminals
$global:Configuration.RepositoryGroups
$global:Configuration.Universal.GitHub
$global:MachineSpecificPaths.Projects
Resolve-ProjectPath -ProjectName "MyProject"
Resolve-ProjectPath -ProjectName "MyRepo" -ForRepository
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    ProjectTerminals = @(
        @{ Name = "MyProject"; BasePath = "Projects.MyProject"; Paths = @("ROOT", "API") }
    )
    RepositoryGroups = @(
        @{ Personal = @(
                @{ Name = "MyRepo"; UrlPath = "Universal.GitHub.Private.MyRepo"; LocalPath = "Projects.MyRepo.Root" }
            )
        }
    )
    Universal = @{
        GitHub = @{
            Base    = "https://github.com"
            Private = @{ MyRepo = "/YourUsername/MyRepo.git" }
        }
    }
    PathTemplates = @{
        Projects = @{
            MyProject = @{ Root = "{Dev}\MyProject"; Api = "{Dev}\MyProject\src\Api" }
            MyRepo    = @{ Root = "{Dev}\MyRepo" }
        }
    }
}
```

## Related

- [`Resolve-ProjectPath` in the Helper module reference](../../../modules/helper.md#resolve-projectpath) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [`Add-Project`](../configuration/Add-Project.md) - reads the same configuration
- [`Run-Project`](Run-Project.md) - reads the same configuration
- [`Open-ProjectTerminals`](../workflow/Open-ProjectTerminals.md) - reads the same configuration
- [`Open-Workspace`](../workflow/Open-Workspace.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
