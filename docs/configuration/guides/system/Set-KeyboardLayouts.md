# Set-KeyboardLayouts

Configures keyboard layouts from predefined layout sets read from `KeyboardLayoutSets` in `Configuration.psd1` (e.g. "Gaming", "Development").

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultKeyboardLayoutSet`](../../configuration-reference.md#keyboard-layouts) | string | empty string | Which named set from `KeyboardLayoutSets` `Set-KeyboardLayouts` applies by default. Ships empty, so the function no-ops. |
| [`KeyboardLayouts`](../../configuration-reference.md#keyboard-layouts) | hashtable of friendly name to layout id | `@{}` (empty) | The individual keyboard layouts available to `KeyboardLayoutSets`. |
| [`KeyboardLayoutSets`](../../configuration-reference.md#keyboard-layouts) | hashtable of set name to array of layout names | `@{}` (empty) | Named combinations of `KeyboardLayouts` entries. `Set-KeyboardLayouts` applies one set at a time; order is the order Windows cycles them. |

## Decisions

1. Which keyboard layout set should be the default?
    - Options: A key from your `KeyboardLayoutSets` map.
    - Default: Empty - `Set-KeyboardLayouts` no-ops.
    - More detail: [`DefaultKeyboardLayoutSet`](../../configuration-reference.md#keyboard-layouts)
2. Which keyboard layouts do you use?
    - Options: Friendly name to Windows input-language id, e.g. `English = "0409:00000409"`.
    - Default: Empty - `Set-KeyboardLayouts` no-ops.
    - More detail: [`KeyboardLayouts`](../../configuration-reference.md#keyboard-layouts)
3. Which layout combinations do you want to switch between?
    - Options: Set name to an ordered array of `KeyboardLayouts` keys. The first is the default input language.
    - Default: Empty.
    - More detail: [`KeyboardLayoutSets`](../../configuration-reference.md#keyboard-layouts)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `DefaultKeyboardLayoutSet`
2. Set `KeyboardLayouts`
3. Set `KeyboardLayoutSets`
4. Reload and confirm the merge landed

## Step 1: Set `DefaultKeyboardLayoutSet`

Which named set from `KeyboardLayoutSets` `Set-KeyboardLayouts` applies by default. Ships empty, so the function no-ops.

```powershell
DefaultKeyboardLayoutSet = "Standard"
```

## Step 2: Set `KeyboardLayouts`

The individual keyboard layouts available to `KeyboardLayoutSets`.

```powershell
KeyboardLayouts = @{
    English = "0409:00000409"
}
```

## Step 3: Set `KeyboardLayoutSets`

Named combinations of `KeyboardLayouts` entries. `Set-KeyboardLayouts` applies one set at a time; order is the order Windows cycles them.

```powershell
KeyboardLayoutSets = @{
    Standard = @("English")
}
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultKeyboardLayoutSet
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultKeyboardLayoutSet
$global:Configuration.KeyboardLayouts
$global:Configuration.KeyboardLayoutSets
Display-SystemLanguageSettings
$global:Configuration.KeyboardLayoutSets
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultKeyboardLayoutSet = "Standard"
    KeyboardLayouts = @{
        English = "0409:00000409"
    }
    KeyboardLayoutSets = @{
        Standard = @("English")
    }
}
```

## Related

- [`Set-KeyboardLayouts` in the System module reference](../../../modules/system.md#set-keyboardlayouts) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Bootstrap`](../bootstrap/Bootstrap.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
