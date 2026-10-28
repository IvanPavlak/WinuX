# Initialize-OhMyPosh

Resolves the `oh-my-posh` binary and initializes the prompt theme for the current session - the robust form of the classic profile one-liner `oh-my-posh init pwsh --config <theme> | Invoke-Expression`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.OhMyPoshThemeFile`](../../configuration-reference.md#universal-paths) | string (placeholder path) | `"{User}\AppData\Local\Programs\oh-my-posh\themes\WinuX.omp.json"` | The theme passed to `oh-my-posh init pwsh --config`. Expanded by `Load-PathConfiguration`, so `{User}` works here. Its file name is also what `Initialize-WSLEnvironment` wires into WSL. |

## Decisions

1. Which Oh My Posh theme should the prompt use?
    - Options: Override `Universal.OhMyPoshThemeFile` with the path of any `.omp.json` theme file, absolute or with placeholders.
    - Default: `WinuX.omp.json` in the Oh My Posh themes folder of the user profile.
    - More detail: [`Universal`](../../configuration-reference.md#universal-paths)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal.OhMyPoshThemeFile`
2. Reload and confirm the merge landed

## Step 1: Set `Universal.OhMyPoshThemeFile`

The theme file the prompt is initialized with. `Universal` is a hashtable, so this one key merges over the base and every other `Universal` key stays as shipped.

```powershell
Universal = @{
    OhMyPoshThemeFile = "{User}\AppData\Local\Programs\oh-my-posh\themes\MyTheme.omp.json"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.OhMyPoshThemeFile
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.OhMyPoshThemeFile
Test-Path $global:Configuration.Universal.OhMyPoshThemeFile
(Get-Command oh-my-posh -ErrorAction SilentlyContinue).Source
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        OhMyPoshThemeFile = "{User}\AppData\Local\Programs\oh-my-posh\themes\MyTheme.omp.json"
    }
}
```

## Related

- [`Initialize-OhMyPosh` in the System module reference](../../../modules/system.md#initialize-ohmyposh) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Initialize-WSLEnvironment`](Initialize-WSLEnvironment.md) - reads the same key, for the WSL prompt
- [`Initialize-PSReadLine`](Initialize-PSReadLine.md) - runs before this function on every shell start
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
