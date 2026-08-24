# Docker-Cleanup

Menu-driven Docker maintenance with per-action confirmation safeguards.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DockerCleanupActions`](../../configuration-reference.md#more-sections-quick-reference) | array of `@{ Name; Command; ConfirmationMessage }` | array of 3 | The menu `Docker-Cleanup` offers. An entry carrying a `ConfirmationMessage` only runs after an explicit "Yes" on a red prompt, and Enter defaults to "No". |

## Decisions

1. Which Docker cleanup actions do you want in the menu?
    - Options: One entry per action: `Name` (menu label), `Command` (the PowerShell command line), optional `ConfirmationMessage` for anything irreversible.
    - Default: The shipped three: stop all containers, system prune, delete all volumes.
    - More detail: [`DockerCleanupActions`](../../configuration-reference.md#more-sections-quick-reference)
2. Should any shipped action be removed?
    - Options: Supply the whole array without it - arrays replace wholesale, so your local array is the complete menu.
    - Default: Keep all three.
    - More detail: [`DockerCleanupActions`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `DockerCleanupActions` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `DockerCleanupActions`
2. Reload and confirm the merge landed

## Step 1: Set `DockerCleanupActions`

The menu `Docker-Cleanup` offers. An entry carrying a `ConfirmationMessage` only runs after an explicit "Yes" on a red prompt, and Enter defaults to "No".

```powershell
DockerCleanupActions = @(
    @{ Name = "Stop all containers"; Command = "docker stop `$(docker ps -q)" }
    @{ Name = "Prune everything";    Command = "docker system prune -a --volumes -f"; ConfirmationMessage = "This deletes all unused images and volumes. Continue?" }
)
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerCleanupActions
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerCleanupActions
$global:Configuration.DockerCleanupActions | Format-Table Name, Command
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DockerCleanupActions = @(
        @{ Name = "Stop all containers"; Command = "docker stop `$(docker ps -q)" }
        @{ Name = "Prune everything";    Command = "docker system prune -a --volumes -f"; ConfirmationMessage = "This deletes all unused images and volumes. Continue?" }
    )
}
```

## Related

- [`Docker-Cleanup` in the Workflow module reference](../../../modules/workflow.md#docker-cleanup) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
