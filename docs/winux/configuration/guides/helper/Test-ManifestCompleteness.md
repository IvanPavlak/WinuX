# Test-ManifestCompleteness

Startup integrity check that warns about function files not exported by their module manifest, for every module under the WinuX `Modules` folder and the fork-owned `Custom` area.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.Projects.Self.Modules`](../../configuration-reference.md#path-templates--placeholder-system) | string (placeholder path) | `"{RepoRoot}\Windows\PowerShell\Modules"` | The modules root, read through `$global:MachineSpecificPaths.Projects.Self.Modules`. Every subfolder that ships a `<Name>.psd1` and a `Functions\` folder is checked, plus `Custom\`. An unset or missing path logs an error and checks nothing. |

## Decisions

1. Should the manifest check look somewhere other than this repository's own `Modules` folder?
    - Options: Leave it - `{RepoRoot}` already resolves the running checkout. Override `PathTemplates.Projects.Self.Modules` only when the modules live elsewhere.
    - Default: `{RepoRoot}\Windows\PowerShell\Modules`.
    - More detail: [`PathTemplates`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `PathTemplates.Projects.Self.Modules` (rarely needed)
2. Reload and confirm the merge landed

## Step 1: Set `PathTemplates.Projects.Self.Modules` (rarely needed)

`PathTemplates`, `Projects` and `Self` are hashtables, so only the field you change needs to be written; `Root`, `Docs` and the other `Self` fields stay as shipped.

```powershell
PathTemplates = @{
    Projects = @{
        Self = @{ Modules = "{RepoRoot}\Windows\PowerShell\Modules" }
    }
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:MachineSpecificPaths` after a reload is the ground truth for expanded `PathTemplates` - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.Projects.Self.Modules
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.Projects.Self.Modules
Test-Path $global:MachineSpecificPaths.Projects.Self.Modules
Test-ManifestCompleteness
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        Projects = @{
            Self = @{ Modules = "{RepoRoot}\Windows\PowerShell\Modules" }
        }
    }
}
```

## Related

- [`Test-ManifestCompleteness` in the Helper module reference](../../../modules/helper.md#test-manifestcompleteness) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
