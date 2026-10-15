# Docker-Cleanup

Menu-driven Docker maintenance that lists what each action would stop or remove before one confirmation, has an `All` option, and offers to start Docker (through `DockerWizard`) when the daemon is not running.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DockerCleanupActions`](../../configuration-reference.md#more-sections-quick-reference) | array of `@{ Name; Description; Command; PreviewCommand; ConfirmationMessage }` | array of 5 | The menu `Docker-Cleanup` offers, in run order; the menu adds `All`. `PreviewCommand` output is listed before the confirmation and an empty list skips the action. An entry carrying a `ConfirmationMessage` only runs after an explicit "Yes" on a red prompt, and Enter defaults to "No". |
| [`DockerCleanupStartMode`](../../configuration-reference.md#more-sections-quick-reference) | string | `"Ask"` | What happens when the Docker daemon is not running: `"Ask"` asks whether to start it (Enter means Yes), `"Always"` starts it without asking, `"Never"` warns and returns. An empty or unknown value behaves like `"Ask"`. |

## Decisions

1. Which Docker cleanup actions do you want in the menu?
    - Options: One entry per action: `Name` (menu label), `Command` (the PowerShell command line), optional `Description` (one sentence shown before the confirmation), optional `PreviewCommand` (a command whose output lists what the action would touch; without one the action is never skipped), optional `ConfirmationMessage` for anything irreversible. List them in the order they should run - `All` and multi-selections follow this order.
    - Default: The shipped five: stop all containers, delete all containers, delete all images, delete all volumes, prune unused networks and the build cache. Together, via `All`, they wipe Docker completely.
    - More detail: [`DockerCleanupActions`](../../configuration-reference.md#more-sections-quick-reference)
2. Should any shipped action be removed?
    - Options: Supply the whole array without it - arrays replace wholesale, so your local array is the complete menu.
    - Default: Keep all five.
    - More detail: [`DockerCleanupActions`](../../configuration-reference.md#more-sections-quick-reference)
3. Should `Docker-Cleanup` start Docker when the daemon is not running?
    - Options: `"Ask"` (prompt, Enter means Yes), `"Always"` (start without asking), `"Never"` (warn and return, the behavior before this key existed).
    - Default: `"Ask"`. Docker is started through `DockerWizard`, so a slow machine may also need a higher `DockerTimeouts.StartSeconds` (see [DockerWizard](DockerWizard.md)).
    - More detail: [`DockerCleanupStartMode`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `DockerCleanupActions` - that key is an array, so whatever you write is the complete value. `DockerCleanupStartMode` is a scalar and replaces too, which is what you want.

## Steps Overview

1. Set `DockerCleanupActions`
2. Set `DockerCleanupStartMode`
3. Reload and confirm the merge landed

## Step 1: Set `DockerCleanupActions`

The menu `Docker-Cleanup` offers, in the order the actions run. The preview of each selected action is listed before the one confirmation; an action whose `PreviewCommand` prints nothing is skipped. An entry carrying a `ConfirmationMessage` only runs after an explicit "Yes" on a red prompt, and Enter defaults to "No".

```powershell
DockerCleanupActions = @(
    @{ Name = "Stop all containers"; Description = "Stops every running container."
       Command = 'docker ps -q | ForEach-Object { docker stop $_ }'
       PreviewCommand = 'docker ps --format "{{.Names}} ({{.Image}})"' }
    @{ Name = "Delete all volumes"; Description = "Removes every volume, with the data in it."
       Command = 'docker volume ls -q | ForEach-Object { docker volume rm $_ }'
       PreviewCommand = 'docker volume ls --format "{{.Name}}"'
       ConfirmationMessage = "Are you sure you want to delete ALL volumes?" }
)
```

## Step 2: Set `DockerCleanupStartMode`

What happens when the Docker daemon is not running. Leave it out to keep the shipped `"Ask"`.

```powershell
DockerCleanupStartMode = "Always"
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerCleanupActions
$global:Configuration.DockerCleanupStartMode
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DockerCleanupActions
$global:Configuration.DockerCleanupActions | Format-Table Name, Command, PreviewCommand
$global:Configuration.DockerCleanupStartMode
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DockerCleanupActions = @(
        @{ Name = "Stop all containers"; Description = "Stops every running container."
           Command = 'docker ps -q | ForEach-Object { docker stop $_ }'
           PreviewCommand = 'docker ps --format "{{.Names}} ({{.Image}})"' }
        @{ Name = "Delete all volumes"; Description = "Removes every volume, with the data in it."
           Command = 'docker volume ls -q | ForEach-Object { docker volume rm $_ }'
           PreviewCommand = 'docker volume ls --format "{{.Name}}"'
           ConfirmationMessage = "Are you sure you want to delete ALL volumes?" }
    )
    DockerCleanupStartMode = "Always"
}
```

## Related

- [`Docker-Cleanup` in the Workflow module reference](../../../modules/workflow.md#docker-cleanup) - parameters, usage and behaviour
- [Workflow configuration guides](README.md) - every guide for this module
- [DockerWizard](DockerWizard.md) - starts Docker for `Docker-Cleanup`; its `DockerTimeouts.StartSeconds` bounds the wait
- [Add New Project](add-new-project.md) - the full 9-step walk for a new project
- [Add New Workspace](add-new-workspace.md) - workspaces, action ordering and layouts
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
