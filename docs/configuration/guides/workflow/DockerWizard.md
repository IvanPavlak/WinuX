# DockerWizard

Starts or stops Docker Desktop with loading-spinner feedback, daemon readiness detection, graceful Docker Desktop CLI integration, and Docker-owned WSL cleanup.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DockerTimeouts`](../../configuration-reference.md#more-sections-quick-reference) | hashtable, 3 keys | `@{ StartSeconds = 180; StopSeconds = 60; CleanupSeconds = 30 }` | How long `DockerWizard` waits for Docker Desktop to start, stop, and finish a cleanup before giving up. |

## Decisions

1. Are the Docker timeouts long enough on this machine?
    - Options: Seconds per phase. Raise `StartSeconds` on a slow disk.
    - Default: 180 / 60 / 30.
    - More detail: [`DockerTimeouts`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `DockerTimeouts`
2. Reload and confirm the merge landed

## Step 1: Set `DockerTimeouts`

How long `DockerWizard` waits for Docker Desktop to start, stop, and finish a cleanup before giving up.

```powershell
DockerTimeouts = @{ StartSeconds = 240; StopSeconds = 60; CleanupSeconds = 30 }
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerTimeouts
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerTimeouts
$global:Configuration.DockerTimeouts
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DockerTimeouts = @{ StartSeconds = 240; StopSeconds = 60; CleanupSeconds = 30 }
}
```

## Related

- [`DockerWizard` in the Workflow module reference](../../../modules/workflow.md#dockerwizard) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
