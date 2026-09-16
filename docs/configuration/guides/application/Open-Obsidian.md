# Open-Obsidian

Opens Obsidian for the configured vault and, when a workspace resolves, loads that Obsidian workspace through the official Obsidian command line interface - switching a running Obsidian in place, or launching it detached from the shell and loading the workspace once the CLI answers.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.ObsidianDirectory`](../../configuration-reference.md#path-templates--placeholder-system) | path template | `""` (empty) | The vault root. Its leaf folder is the vault name the CLI is addressed with, and `.obsidian\workspaces.json` under it is where the saved workspace names are read from. Required. |
| [`Obsidian.DefaultWorkspace`](../../configuration-reference.md#obsidian-configuration) | string | `""` (empty) | The Obsidian workspace to load on a cold start when neither `-Workspace` nor a same-named match applies. Empty leaves Obsidian where it was, or to plugins such as Homepage. |
| [`Obsidian.Vault`](../../configuration-reference.md#obsidian-configuration) | string | `""` (empty) | The vault name for the CLI when it is not the leaf folder of `ObsidianDirectory`. |
| [`AutoPathAdditions`](../../configuration-reference.md#more-sections-quick-reference) | array of directory paths | `@()` (empty) | Optional. Persisting `%LOCALAPPDATA%\Programs\obsidian` on the User PATH keeps the `obsidian` command available in every new shell; the function also probes that folder directly. |

## How a Workspace Is Chosen

`Open-Obsidian` resolves at most one Obsidian workspace per call, in this order:

1. `-Workspace <Name>`.
2. `-CurrentWorkspace <Name>` - the WinuX workspace being opened, injected by `Open-Workspace` into every action - when the vault has an Obsidian workspace of exactly that name. So a bare `@{ Action = "Open-Obsidian" }` under `WorkspaceActions.Server` loads the Obsidian workspace `Server` as soon as you save one in the vault, with no configuration change.
3. Without either, and without `-Default`, a `Resolve-Selection` menu of the saved workspaces - the same pattern as `Open-VSCode` and `Open-VisualStudio`. A bare `Open-Obsidian` by hand picks one; `[Enter]` skips. The injected `CurrentWorkspace` suppresses the menu, so a workspace open never prompts; an action list without that injection (`ProjectActions`) must pass `Parameters = @{ Default = $true }` or a `Workspace`. Inside a workspace action `Default = $true` is optional (the injected `CurrentWorkspace` already suppresses the menu) and it never disables the same-named match - it only removes the prompt, so it is safe belt-and-braces for any unattended open.
4. `Obsidian.DefaultWorkspace`, on a cold start only. A running Obsidian is never switched to the default.
5. Nothing - Obsidian opens, or stays, wherever it is.

With Obsidian already running and a workspace resolved, the running instance is switched in place. With no workspace resolved a running Obsidian is left alone, exactly as before.

## Decisions

1. Where is the vault?
    - Options: The vault root, normally `{Dev}\Obsidian`. The leaf folder doubles as the vault name.
    - Default: Empty - the function reports the missing configuration and does nothing.
    - More detail: [`PathTemplates.ObsidianDirectory`](../../configuration-reference.md#path-templates--placeholder-system)
2. Should a cold start land on a particular Obsidian workspace when nothing else resolves?
    - Options: A saved workspace name from the vault, or empty. If the Homepage plugin already opens a workspace on startup, leave this empty and let it.
    - Default: Empty.
    - More detail: [`Obsidian.DefaultWorkspace`](../../configuration-reference.md#obsidian-configuration)
3. Is the vault name the folder name?
    - Options: Empty when they match (the usual case); the vault name as Obsidian shows it otherwise.
    - Default: Empty - derived from `ObsidianDirectory`.
    - More detail: [`Obsidian.Vault`](../../configuration-reference.md#obsidian-configuration)
4. Should the Obsidian CLI folder be on PATH permanently?
    - Options: Add `%LOCALAPPDATA%\Programs\obsidian` to `AutoPathAdditions`. Registering the CLI inside Obsidian adds it too, but only for shells opened afterwards.
    - Default: Not added. The function still finds `Obsidian.com` beside `Obsidian.exe`.
    - More detail: [`AutoPathAdditions`](../../configuration-reference.md#more-sections-quick-reference)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `AutoPathAdditions` - that key is an array, so whatever you write is the complete value. `Obsidian` is a hashtable and deep-merges, so `@{ DefaultWorkspace = "Empty" }` alone keeps the shipped `Vault`.

## Steps Overview

1. Enable the Obsidian command line interface
2. Set `PathTemplates.ObsidianDirectory`
3. Set `Obsidian`
4. Set `AutoPathAdditions`
5. Reload and confirm the merge landed

## Step 1: Enable the Obsidian command line interface

The workspace switch needs the CLI that ships with Obsidian 1.12.4 and later (installer 1.12.7 or newer), and it must be switched on. The toggle is Obsidian application state, kept as `"cli": true` in `%APPDATA%\obsidian\obsidian.json` next to the vault list - not in the vault's `.obsidian` folder, so syncing the vault to a second machine does not carry it. It is a one-time step per machine, and there are two ways to take it:

- With Obsidian closed, run `Enable-ObsidianCli`. It sets the flag and leaves everything else in the file alone.
- Or in Obsidian open Settings > General > Advanced > Command line interface (Settings > General > Command line interface before 1.13), enable it and accept the register prompt, which also puts the install folder on your User PATH for new shells.

`Obsidian.com` sits beside `Obsidian.exe` either way, so `Get-ObsidianCliPath` returning a path does not prove the toggle is on - the CLI answers `Command line interface is not enabled` until it is.

```powershell
Get-Command obsidian
obsidian vault=Obsidian workspaces
```

Without the CLI `Open-Obsidian` still opens Obsidian; a requested workspace is reported with these registration steps instead of loaded. With the CLI present but the toggle off, the load is reported as refused (`Obsidian workspace [Name] not loaded => Command line interface is not enabled ...`) and points at `Enable-ObsidianCli`; it is never claimed as a success.

## Step 2: Set `PathTemplates.ObsidianDirectory`

The vault root. Its leaf folder is the vault name, and `.obsidian\workspaces.json` under it is read for the saved workspace names.

```powershell
PathTemplates = @{
    ObsidianDirectory = "{Dev}\Obsidian"
}
```

## Step 3: Set `Obsidian`

Both keys are optional. `DefaultWorkspace` is only used on a cold start when neither `-Workspace` nor a same-named match resolves; `Vault` is only needed when the vault name differs from the folder name.

```powershell
Obsidian = @{
    DefaultWorkspace = "Empty"
    Vault            = ""
}
```

## Step 4: Set `AutoPathAdditions`

Optional. Copy the whole base array first - it replaces wholesale - and add the Obsidian install folder so `obsidian` resolves in every shell `Set-EnvironmentVariables -Auto` has run for.

```powershell
AutoPathAdditions = @(
    "%LOCALAPPDATA%\Programs\obsidian"
)
```

## Step 5: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Obsidian
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.ObsidianDirectory
$global:Configuration.Obsidian
Get-ObsidianCliPath
Get-ObsidianWorkspaceNames -VaultDirectory $global:MachineSpecificPaths.ObsidianDirectory
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

Then the behaviour itself: with Obsidian closed, `Open-Obsidian -Workspace <Name>` opens it on that workspace; with Obsidian open, the same call switches it in place; a bare `Open-Obsidian` lists the saved workspaces and `Open-Obsidian -Default` opens without asking; and closing the terminal you ran it from leaves Obsidian standing. If instead you get `Obsidian workspace [Name] not loaded => Command line interface is not enabled`, Step 1 was skipped on this machine: close Obsidian, run `Enable-ObsidianCli`, start Obsidian again.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        ObsidianDirectory = "{Dev}\Obsidian"
    }
    Obsidian = @{
        DefaultWorkspace = "Empty"
    }
    AutoPathAdditions = @(
        "%LOCALAPPDATA%\Programs\obsidian"
    )
    WorkspaceActions = @{
        Server = @(
            @{ Action = "Open-Obsidian"; Parameters = @{ Default = $true } }     # loads the Obsidian workspace "Server" if the vault has one, never prompts
        )
        Research = @(
            @{ Action = "Open-Obsidian"; Parameters = @{ Workspace = "Papers" } } # always loads "Papers"
        )
    }
}
```

## Legacy Startup Script

Before 0.1.61 `Open-Obsidian` ran `ObsidianStartupScript.pyw` through `pythonw`, resolved from `PathTemplates.ObsidianStartupScript`. The script only started `Obsidian.exe`; the `pythonw` hop existed because a GUI process launched from a console-owning parent attaches to that console and dies with the terminal, and `pythonw` owns no console. `Start-ObsidianDetached` achieves the same through WMI without Python, so the key is deprecated: it is still accepted and still parses, but nothing reads it and it can be removed from a local file. Should the need for a custom startup script ever return, `Start-Application -StartMethod DirectPath -ExecutablePath pythonw -Arguments <script>` with `-SkipPathValidation` is the call the old function made.

## Related

- [`Open-Obsidian` in the Application module reference](../../../modules/application.md#open-obsidian) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Get-ObsidianCliPath`](Get-ObsidianCliPath.md), [`Get-ObsidianExecutablePath`](Get-ObsidianExecutablePath.md), [`Get-ObsidianWorkspaceNames`](Get-ObsidianWorkspaceNames.md), [`Invoke-ObsidianCli`](Invoke-ObsidianCli.md), [`Start-ObsidianDetached`](Start-ObsidianDetached.md), [`Wait-ObsidianCli`](Wait-ObsidianCli.md) - the helpers this function is built from
- [`Open-Workspace`](../workflow/Open-Workspace.md) - injects `CurrentWorkspace` into every action
- [`Set-EnvironmentVariables`](../system/Set-EnvironmentVariables.md) - persists `AutoPathAdditions`
- [`Git-Obsidian`](../git/Git-Obsidian.md) - reads the same `ObsidianDirectory`
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
