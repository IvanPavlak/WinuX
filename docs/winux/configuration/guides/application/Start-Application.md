# Start-Application

Common (DRY) helper to start applications with standardized error handling, process checking, and user feedback.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`Universal.<ConfigKey>`](../../configuration-reference.md#application-executables) | string (path) | per key: `DockerExe` and `OutlookLauncherExe` ship set; `DbeaverExe`, `FoundryVTTExe`, `NotepadPlusPlusExe`, `RiseupVpnExe`, `TeamViewerExe` and `VirtualBoxExe` ship `""` (empty) | The executable the `ConfigPath` start method launches, named by `-ConfigKey`. Empty or missing, the launch warns (`[<ConfigKey>] is not configured (Universal section)`) and returns; the path itself is not checked before `Start-Process`. Placeholders such as `{User}` expand. The other start methods read no configuration. |

The `ConfigPath` launchers and the key each needs: `Open-DBeaver` (`DbeaverExe`), `Open-Docker` (`DockerExe`), `Open-FoundryVTT` (`FoundryVTTExe`), `Open-NotepadPlusPlus` without a file (`NotepadPlusPlusExe`), `Open-Outlook` (`OutlookLauncherExe`), `Open-RiseupVPN` (`RiseupVpnExe`), `Open-TeamViewer` (`TeamViewerExe`), `Open-VirtualBox` (`VirtualBoxExe`).

## Decisions

1. Which of the `ConfigPath` launchers do you use, and where are their applications installed?
    - Options: Set `Universal.<App>Exe` for each one you use, to the full path of its executable. Correct `DockerExe` or `OutlookLauncherExe` only when the shipped value is wrong on this machine.
    - Default: Empty for the personal applications, so their launchers warn and open nothing; `DockerExe` and `OutlookLauncherExe` ship their default install locations.
    - More detail: [`Universal`](../../configuration-reference.md#application-executables)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `Universal`
2. Reload and confirm the merge landed

## Step 1: Set `Universal`

The executables of the launchers you use. `Universal` is a hashtable and deep-merges, so set only the keys you need.

```powershell
Universal = @{
    DbeaverExe    = "{User}\AppData\Local\DBeaver\dbeaver.exe"
    VirtualBoxExe = "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.Universal.DbeaverExe
$global:Configuration.Universal.VirtualBoxExe
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    Universal = @{
        DbeaverExe    = "{User}\AppData\Local\DBeaver\dbeaver.exe"
        VirtualBoxExe = "C:\Program Files\Oracle\VirtualBox\VirtualBox.exe"
    }
}
```

## Related

- [`Start-Application` in the Application module reference](../../../modules/application.md#start-application) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
- [`Open-NotepadPlusPlus`](Open-NotepadPlusPlus.md) - reads `NotepadPlusPlusExe` itself as well
- The `ConfigPath` launchers, whose key lives here: [`Open-DBeaver`](Open-DBeaver.md), [`Open-Docker`](Open-Docker.md), [`Open-FoundryVTT`](Open-FoundryVTT.md), [`Open-Outlook`](Open-Outlook.md), [`Open-RiseupVPN`](Open-RiseupVPN.md), [`Open-TeamViewer`](Open-TeamViewer.md), [`Open-VirtualBox`](Open-VirtualBox.md)
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
