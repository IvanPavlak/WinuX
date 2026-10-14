# Rebuild-IconCache

Clears the Windows icon cache and restarts Explorer to fix missing or corrupted desktop/taskbar icons.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.IconCacheDb`](../../configuration-reference.md#universal-paths) | string (placeholder path) | `"{User}\AppData\Local\IconCache.db"` | The legacy icon cache database deleted while Explorer is stopped. Skipped when the file does not exist. Expanded by `Load-PathConfiguration`, so `{User}` works here. |
| [`Universal.IconCacheFolder`](../../configuration-reference.md#universal-paths) | string (placeholder path) | `"{User}\AppData\Local\Microsoft\Windows\Explorer"` | The folder whose `iconcache*` files are deleted. Skipped when empty or missing. |

## Decisions

1. Are the shipped icon cache locations the right ones on this machine?
    - Options: Override `Universal.IconCacheDb` and/or `Universal.IconCacheFolder` with an absolute or placeholder path. Only `IconCache.db` and the `iconcache*` files in the folder are deleted, so point the folder at Explorer's cache directory only.
    - Default: The standard Windows locations under `{User}\AppData\Local`.
    - More detail: [`Universal`](../../configuration-reference.md#universal-paths)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal.IconCacheDb` and `Universal.IconCacheFolder`
2. Reload and confirm the merge landed

## Step 1: Set `Universal.IconCacheDb` and `Universal.IconCacheFolder`

Only needed when the shipped paths are wrong on this machine. `Universal` is a hashtable, so these keys merge over the base and every other `Universal` key stays as shipped.

```powershell
Universal = @{
    IconCacheDb     = "{User}\AppData\Local\IconCache.db"
    IconCacheFolder = "{User}\AppData\Local\Microsoft\Windows\Explorer"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.IconCacheDb
$global:Configuration.Universal.IconCacheFolder
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.IconCacheDb
$global:Configuration.Universal.IconCacheFolder
Get-ChildItem $global:Configuration.Universal.IconCacheFolder -Filter "iconcache*"
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        IconCacheDb     = "{User}\AppData\Local\IconCache.db"
        IconCacheFolder = "{User}\AppData\Local\Microsoft\Windows\Explorer"
    }
}
```

## Related

- [`Rebuild-IconCache` in the System module reference](../../../modules/system.md#rebuild-iconcache) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
