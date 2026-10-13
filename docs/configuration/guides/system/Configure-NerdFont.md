# Configure-NerdFont

Installs and configures a Nerd Font.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultNerdFont`](../../configuration-reference.md#more-sections-quick-reference) | string | empty string | Which entry from `NerdFonts` Bootstrap installs and `Configure-NerdFont` applies. Ships empty, so the function no-ops. |
| [`NerdFonts`](../../configuration-reference.md#more-sections-quick-reference) | [ordered section](../../configuration-reference.md#ordered-sections): `@( @{ <FontName> = @{ FolderName; SearchPattern } } )` | `@()` (empty) | The repository-bundled Nerd Fonts `Configure-NerdFont` can install by name, in menu order. `FolderName` is the font folder relative to the repository root; `SearchPattern` is a file base-name wildcard (`.ttf`/`.otf` is appended) used to detect an existing install. Empty means the function warns and does nothing. |
| [`Universal.Fonts`](../../configuration-reference.md#universal-paths) | string (path) | `"C:\Windows\Fonts"` | The fonts directory the files are copied into and checked against. |

## Decisions

1. Which Nerd Font should be installed and used?
    - Options: A key from your `NerdFonts` map, e.g. `JetBrainsMono`.
    - Default: Empty - `Configure-NerdFont` no-ops.
    - More detail: [`DefaultNerdFont`](../../configuration-reference.md#more-sections-quick-reference)
2. Which bundled fonts should be installable?
    - Options: One `@{ <FontName> = @{ FolderName; SearchPattern } }` item per font, in the order the menu should list them. The repository ships the `JetBrainsMonoNerdFont` payload folder, matched by `SearchPattern = "*JetBrainsMono*Nerd*Font*"`.
    - Default: Empty - `Configure-NerdFont` no-ops.
    - More detail: [`NerdFonts`](../../configuration-reference.md#more-sections-quick-reference)
3. Is the Windows fonts directory somewhere other than `C:\Windows\Fonts`?
    - Options: Override `Universal.Fonts`. Almost never needed.
    - Default: `C:\Windows\Fonts`.
    - More detail: [`Universal`](../../configuration-reference.md#universal-paths)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `DefaultNerdFont`
2. Set `NerdFonts`
3. Set `Universal.Fonts` (only if needed)
4. Reload and confirm the merge landed

## Step 1: Set `DefaultNerdFont`

Which entry from `NerdFonts` Bootstrap installs and `Configure-NerdFont` applies. Ships empty, so the function no-ops.

```powershell
DefaultNerdFont = "JetBrainsMono"
```

## Step 2: Set `NerdFonts`

The repository-bundled Nerd Fonts `Configure-NerdFont` can install by name. An ordered section: an array of single-key hashtables, listed in menu order. Every `.ttf`/`.otf` in `FolderName` is installed; `SearchPattern` only detects an install that is already there.

```powershell
NerdFonts = @(
    @{ JetBrainsMono = @{ FolderName = "JetBrainsMonoNerdFont"; SearchPattern = "*JetBrainsMono*Nerd*Font*" } }
)
```

## Step 3: Set `Universal.Fonts` (only if needed)

The fonts directory. `Universal` is a hashtable, so this one key merges over the base and every other `Universal` key stays as shipped.

```powershell
Universal = @{
    Fonts = "C:\Windows\Fonts"
}
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultNerdFont
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultNerdFont
$global:Configuration.NerdFonts
$global:Configuration.Universal.Fonts
Get-OrderedNames $global:Configuration.NerdFonts
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultNerdFont = "JetBrainsMono"
    NerdFonts = @(
        @{ JetBrainsMono = @{ FolderName = "JetBrainsMonoNerdFont"; SearchPattern = "*JetBrainsMono*Nerd*Font*" } }
    )
    Universal = @{
        Fonts = "C:\Windows\Fonts"
    }
}
```

## Related

- [`Configure-NerdFont` in the System module reference](../../../modules/system.md#configure-nerdfont) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Bootstrap`](../bootstrap/Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
