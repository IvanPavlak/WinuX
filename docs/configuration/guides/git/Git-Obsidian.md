# Git-Obsidian

Commits and pushes all pending changes in the Obsidian vault repository, providing a quick vault backup to GitHub without opening Obsidian.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`PathTemplates.ObsidianDirectory`](../../configuration-reference.md#path-templates--placeholder-system) | path template | `""` (empty) | The vault root - a git working tree whose upstream is where the backup is pushed. `Git-Obsidian` changes into the expanded `$global:MachineSpecificPaths.ObsidianDirectory` and runs every git command there. Required. |

> [!WARNING]
> Set `ObsidianDirectory` before running `Git-Obsidian`. The function does not check for an empty value: an empty path makes `Set-Location` land in your home folder, and the git commands (including `git add .`, `git commit` and `git push`) then run there instead of in a vault.

## Decisions

1. Where is the vault repository?
    - Options: The vault root, normally `{Dev}\Obsidian`. It must be a git clone with an upstream branch, because the function commits there and pushes to that upstream.
    - Default: Empty - there is no vault to back up.
    - More detail: [`PathTemplates.ObsidianDirectory`](../../configuration-reference.md#path-templates--placeholder-system)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

`PathTemplates` is a hashtable, so `ObsidianDirectory` alone deep-merges and every shipped path template stays.

## Steps Overview

1. Set `PathTemplates.ObsidianDirectory`
2. Reload and confirm the merge landed

## Step 1: Set `PathTemplates.ObsidianDirectory`

The vault root. `{Dev}` and `{User}` expand per machine, so one value serves every machine that keeps the vault in the same place relative to its base paths.

```powershell
PathTemplates = @{
    ObsidianDirectory = "{Dev}\Obsidian"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.ObsidianDirectory
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:MachineSpecificPaths.ObsidianDirectory
Test-GitRepository -Path $global:MachineSpecificPaths.ObsidianDirectory
git -C $global:MachineSpecificPaths.ObsidianDirectory status --short --branch
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    PathTemplates = @{
        ObsidianDirectory = "{Dev}\Obsidian"
    }
}
```

## When A Push Fails

The function commits first and pushes second, so a push that fails (no network, remote unreachable) leaves the vault committed locally with a clean working tree. It reports that as an error, never as `Obsidian updated!`, and the next `Git-Obsidian` finds the commit the remote is missing and pushes it:

```text
[Git-Obsidian]

Found [1] unpushed commit(s) from an earlier run. Pushing...

=> Obsidian updated!
```

`No changes to update!` is reported only when the working tree is clean **and** the branch has nothing its upstream lacks.

## Related

- [`Git-Obsidian` in the Git module reference](../../../modules/git.md#git-obsidian) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [`Open-Obsidian`](../application/Open-Obsidian.md) - reads the same `ObsidianDirectory`
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
