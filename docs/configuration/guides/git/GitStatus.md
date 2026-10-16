# GitStatus

Shows the working tree status using the configured `git status` arguments (default `--short`). Alias: `gs`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships the default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`GitStatusArguments`](../../configuration-reference.md#git-status-arguments) | array of strings | `@('--short')` | The arguments `GitStatus` passes to `git status` when called with none. One element per git argument. An empty array runs a plain `git status`. Arguments given on the call replace these entirely. |

## Decisions

1. What should a plain `gs` show?
    - Options: `@('--short')` for the compact two-column listing, `@('-sb')` to add the branch line, `@('-v', '-v', '-u')` for the full diff of staged changes plus all untracked files (what `GitStatus` showed before it became configurable), or `@()` for the plain `git status`.
    - Default: `@('--short')`.
    - More detail: [`GitStatusArguments`](../../configuration-reference.md#git-status-arguments)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. `GitStatusArguments` is an array: list every argument you want, not only the ones you add.

## Steps Overview

1. Optionally set `GitStatusArguments`
2. Reload and confirm the merge landed

## Step 1: Optionally set `GitStatusArguments`

Skip this to keep `--short`. To change what a plain `gs` shows, give the full argument list, one element per argument.

```powershell
GitStatusArguments = @('-v', '-v', '-u')
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.GitStatusArguments
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.GitStatusArguments
gs
```

If the value reads back as the default after you set your own, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and the key placed inside another hashtable instead of at the top level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    GitStatusArguments = @('-sb')
}
```

## Usage

```powershell
GitStatus
gs
gs -v -v -u    # explicit arguments replace the configured ones
```

## Related

- [`GitStatus` in the Git module reference](../../../modules/git.md#gitstatus) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
