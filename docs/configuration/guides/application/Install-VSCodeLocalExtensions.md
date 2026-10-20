# Install-VSCodeLocalExtensions

Links the unpackaged VS Code extensions kept in the repository (a colour theme of your own, for example) into VS Code's extensions folder, so VS Code loads them straight from the repository with no VSIX and no Marketplace.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`VSCodeProfiles.Extensions`](../../configuration-reference.md#vs-code-profiles) | string | `{RepoRoot}\VSCode\Extensions` | The folder holding one local extension per subfolder. A missing folder links nothing. |
| [`BootstrapConfig.Steps.VSCodeProfiles`](../../configuration-reference.md#bootstrapconfig) | boolean | `$false` | Whether Bootstrap runs `Deploy-VSCodeProfiles`, which calls this function first. |

## Decisions

1. Do you keep VS Code extensions of your own in the repository?
    - Options: Put each one in its own folder under `Extensions`, with a `package.json` that names `publisher`, `name` and `version` and lists what it contributes. A colour theme needs nothing else but its theme JSON files.
    - Default: None - the folder does not exist in a fresh fork, so nothing is linked.
    - More detail: [`VSCodeProfiles.Extensions`](../../configuration-reference.md#vs-code-profiles)
2. Should they live somewhere other than `VSCode\Extensions`?
    - Options: Any folder; `{RepoRoot}`, `{User}` and `{AppData}` expand.
    - Default: `{RepoRoot}\VSCode\Extensions`.
    - More detail: [`VSCodeProfiles.Extensions`](../../configuration-reference.md#vs-code-profiles)
3. Should Bootstrap link them on every run?
    - Options: `$true` runs `Deploy-VSCodeProfiles` on every Bootstrap, which links the local extensions before it deploys the profiles; `$false` to run `Install-VSCodeLocalExtensions` or `Deploy-VSCodeProfiles` by hand.
    - Default: `$false`.
    - More detail: [`BootstrapConfig.Steps`](../../configuration-reference.md#bootstrapconfig)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you. The extension folders themselves go under `Extensions` in your fork.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Add the extension folder
2. Set `VSCodeProfiles.Extensions` (only to move it)
3. Enable `BootstrapConfig.Steps.VSCodeProfiles`
4. Reload, link and select the theme

## Step 1: Add the extension folder

A theme extension is a `package.json` plus the theme files it points at:

```text
VSCode\Extensions\MyThemes\
    package.json
    themes\Dark.json
    themes\Light.json
```

```json
{
    "name": "mythemes",
    "displayName": "My Themes",
    "publisher": "mypublisher",
    "version": "1.0.0",
    "engines": { "vscode": "^1.80.0" },
    "categories": ["Themes"],
    "contributes": {
        "themes": [
            { "label": "My Dark", "uiTheme": "vs-dark", "path": "./themes/Dark.json" },
            { "label": "My Light", "uiTheme": "vs", "path": "./themes/Light.json" }
        ]
    }
}
```

The link is named `mypublisher.mythemes-1.0.0` from these values. Bumping `version` later relinks it under the new name and removes the old link.

## Step 2: Set `VSCodeProfiles.Extensions` (only to move it)

```powershell
VSCodeProfiles = @{
    Extensions = "{RepoRoot}\VSCode\Extensions"
}
```

## Step 3: Enable `BootstrapConfig.Steps.VSCodeProfiles`

```powershell
BootstrapConfig = @{
    Steps = @{
        VSCodeProfiles = $true
    }
}
```

> [!WARNING]
> Never remove a linked extension with `code --uninstall-extension` or from VS Code's Extensions view: VS Code deletes the extension's folder, and through the link that is the repository copy. `Deploy-VSCodeProfiles` never installs or prunes a local extension for this reason. To retire one, delete its link under `%USERPROFILE%\.vscode\extensions` by hand (`Remove-Item` without `-Recurse`) and its folder in the repository.

## Step 4: Reload, link and select the theme

```powershell
Reload-PowerShellProfile
Install-VSCodeLocalExtensions
```

Then run `Developer: Reload Window` in VS Code and pick the theme under `Preferences: Color Theme`, or set it in a deployed profile's `settings.json` (`"workbench.colorTheme": "My Dark"`). A later edit to a theme file shows up on the next `Developer: Reload Window`.

## Verification

Read-only checks. None of these change anything.

```powershell
(Resolve-VSCodeProfilesConfig).Extensions
Get-VSCodeLocalExtensions -Root (Resolve-VSCodeProfilesConfig).Extensions
Get-ChildItem "$env:USERPROFILE\.vscode\extensions" | Where-Object LinkType | Select-Object Name, Target
Get-VSCodeInstalledExtensions -Command (Get-VSCodeCliPath) -ProfileName Default
```

## Complete Example

```powershell
# Configuration.local.psd1
@{
    VSCodeProfiles  = @{
        Extensions = "{RepoRoot}\VSCode\Extensions"
    }
    BootstrapConfig = @{
        Steps = @{
            VSCodeProfiles = $true
        }
    }
}
```

## Related

- [`Install-VSCodeLocalExtensions` in the Application module reference](../../../modules/application.md#install-vscodelocalextensions)
- [`Get-VSCodeLocalExtensions`](Get-VSCodeLocalExtensions.md) - what gets linked
- [`Deploy-VSCodeProfiles`](Deploy-VSCodeProfiles.md) - calls this first, then deploys the profiles
- [Application configuration guides](README.md)
- [WinuXConfigurator](../../winux-configurator.md)
