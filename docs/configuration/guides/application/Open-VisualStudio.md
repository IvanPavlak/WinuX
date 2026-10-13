# Open-VisualStudio

Opens one or more Visual Studio solutions configured in `VisualStudioSolutions` in `Configuration.psd1`, where each entry maps a name to a `.sln` file path.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.VisualStudio2026Exe`](../../configuration-reference.md#application-executables) | string (path) | `""` (empty) | The `devenv.exe` to launch. Required: empty or missing, the function reports an error and opens nothing. |
| [`VisualStudioSolutions`](../../configuration-reference.md#visual-studio-solutions) | array of `@{ Name; Solution }` | array of 1 (`ExampleProject`) | The solutions `Open-VisualStudio` offers, and what `Close-Project` closes. `Solution` is not a literal path but a dot-notation reference into the expanded `PathTemplates` (`$global:MachineSpecificPaths`), e.g. `"Projects.ExampleProject.Solution"`. |
| [`PathTemplates.Projects`](../../configuration-reference.md#path-templates--placeholder-system) | hashtable of project to path fields | `Self`, `ExampleProject` | Where each `Solution` reference resolves to - normally the project's `Solution` field, a `.sln` path. Placeholders such as `{Dev}` belong here. |

## Decisions

1. Where is Visual Studio installed on this machine?
    - Options: The full path of `devenv.exe`, e.g. `C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\devenv.exe`.
    - Default: Empty - the function reports an error until it is set.
    - More detail: [`Universal`](../../configuration-reference.md#application-executables)
2. Which Visual Studio solutions do you open regularly?
    - Options: One entry per solution with a name and a `Solution` reference such as `"Projects.MyProject.Solution"`, plus that path under `PathTemplates.Projects`. A literal path or placeholder in `Solution` does not resolve.
    - Default: The shipped single example.
    - More detail: [`VisualStudioSolutions`](../../configuration-reference.md#visual-studio-solutions)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `VisualStudioSolutions` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `Universal`
2. Set `VisualStudioSolutions`
3. Reload and confirm the merge landed

## Step 1: Set `Universal`

The Visual Studio executable. `Universal` is a hashtable and deep-merges, so setting only this key keeps the rest of `Universal`.

```powershell
Universal = @{
    VisualStudio2026Exe = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\devenv.exe"
}
```

## Step 2: Set `VisualStudioSolutions`

The solutions `Open-VisualStudio` offers, and what `Close-Project` closes. Each `Solution` names a path under `PathTemplates`, so define the `.sln` there first (`PathTemplates` deep-merges). `VisualStudioSolutions` is an array, so restate the shipped entries you keep.

```powershell
PathTemplates         = @{
    Projects = @{
        MyProject = @{ Solution = "{Dev}\MyProject\MyProject.sln" }
    }
}
VisualStudioSolutions = @(
    @{ Name = "MyProject"; Solution = "Projects.MyProject.Solution" }
)
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.VisualStudio2026Exe
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
Test-Path $global:Configuration.Universal.VisualStudio2026Exe
$global:Configuration.VisualStudioSolutions | Format-Table Name, Solution
$global:MachineSpecificPaths.Projects.MyProject.Solution
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal             = @{
        VisualStudio2026Exe = "C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\devenv.exe"
    }
    PathTemplates         = @{
        Projects = @{
            MyProject = @{ Solution = "{Dev}\MyProject\MyProject.sln" }
        }
    }
    VisualStudioSolutions = @(
        @{ Name = "MyProject"; Solution = "Projects.MyProject.Solution" }
    )
}
```

## Related

- [`Open-VisualStudio` in the Application module reference](../../../modules/application.md#open-visualstudio) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Close-Project`](../workflow/Close-Project.md) - reads the same `VisualStudioSolutions`
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
