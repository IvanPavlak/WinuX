# Configure-Taskbar

Configures the Windows taskbar pins from configuration.

> [!NOTE]
> An existing **real** taskbar layout XML (which may encode your own hand-pinned arrangement) is copied into the unified [backup sink](../../../reference/backups.md) (`Backups/Windows/System/TaskbarLayout/<timestamp>/`) before it is overwritten; if the backup cannot be taken the write is skipped. A leftover symlink at the layout path is removed without a backup.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping) | hashtable of hostname to machine type | `@{ Test = "Test" }` | How `DetermineMachineType` turns this computer name into a machine type. A hostname that is not listed falls back to `DefaultMachineType`. |
| [`TaskbarConfiguration`](../../configuration-reference.md#taskbar-configuration) | array of `@{ Name; Type; Value; Machine; Aumid }` rows | `@()` (empty) | Which apps `Configure-Taskbar` pins, in order. `Type` is `AUMID` or `Path`; `Machine` (default `All`) scopes a row to machine types; `Aumid` (Path rows only) stamps a runtime AppUserModelID on the pin shortcut. Ships empty, so the taskbar is left alone until you configure it. |
| [`Universal.TaskbarPinFolder`](../../configuration-reference.md#universal-paths) | string (placeholder path) | `"{AppData}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"` | The folder whose `.lnk` pin shortcuts are deleted before the new layout is written. |
| [`PathTemplates.TaskbarLayoutFile`](../../configuration-reference.md#path-templates--placeholder-system) | string (path) | `"C:\ProgramData\provisioning\taskbar_layout.xml"` | Where the generated layout XML is written and what the `StartLayoutFile` policy points at. Machine-local, never versioned. `Path` rows with an `Aumid` get their generated shortcuts in a `TaskbarPins` folder beside it. |

## Decisions

1. What is this machine hostname, and which machine type should it map to?
    - Options: Hostname to machine type. The machine type must be in `ValidMachineTypes`. [Add New Machine](../bootstrap/add-new-machine.md) walks the whole set of keys a new type needs.
    - Default: Unmapped, so the machine resolves to `DefaultMachineType`.
    - More detail: [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping)
2. Do you have other machines to map now?
    - Options: One entry per hostname you own. Mapping several hostnames to the same type is normal.
    - Default: Just this machine.
    - More detail: [`HostnameToMachineType`](../../configuration-reference.md#hostname-to-machine-type-mapping)
3. Which apps should be pinned to the taskbar, in what order?
    - Options: One `@{ Name; Type; Value; Machine }` row per app, in pin order. `Type = "AUMID"` with the app's AppUserModelID as `Value` (find it with `Get-StartApps`), or `Type = "Path"` with an exe or `.lnk` path (`{User}` is expanded); add `Aumid` to a `Path` row for an app that opens as a second icon next to its pin. The array replaces wholesale.
    - Default: Empty - the taskbar is not touched.
    - More detail: [`TaskbarConfiguration`](../../configuration-reference.md#taskbar-configuration)
4. Should a pin appear on every machine, or only on some?
    - Options: A `Machine` scope per row - `All`, one machine type, or several joined with `/` (`PC/Laptop`). Every type named must be in `ValidMachineTypes`.
    - Default: `All` - a row without `Machine` pins on every machine.
    - More detail: [`TaskbarConfiguration`](../../configuration-reference.md#taskbar-configuration)
5. Do the shipped pin folder and layout path fit this machine?
    - Options: Override `Universal.TaskbarPinFolder` or `PathTemplates.TaskbarLayoutFile`. Almost never needed.
    - Default: The shipped Quick Launch pin folder and `C:\ProgramData\provisioning\taskbar_layout.xml`.
    - More detail: [`Universal`](../../configuration-reference.md#universal-paths)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `TaskbarConfiguration` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `HostnameToMachineType`
2. Set `TaskbarConfiguration`
3. Set `Universal.TaskbarPinFolder` / `PathTemplates.TaskbarLayoutFile` (only if needed)
4. Reload and confirm the merge landed

## Step 1: Set `HostnameToMachineType`

How `DetermineMachineType` turns this computer name into a machine type. A hostname that is not listed falls back to `DefaultMachineType`.

```powershell
HostnameToMachineType = @{
    Test             = "Test"
    "DESKTOP-GAMING" = "PC"   # "PC" must also be listed in ValidMachineTypes
}
```

## Step 2: Set `TaskbarConfiguration`

Which apps `Configure-Taskbar` pins, in order. Ships empty, so the taskbar is left alone until you configure it.

```powershell
TaskbarConfiguration = @(
    @{ Name = "WindowsTerminal"; Type = "AUMID"; Value = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"; Machine = "All" }
    @{ Name = "DBeaver";         Type = "Path";  Value = "{User}\AppData\Local\DBeaver\dbeaver.exe"; Aumid = "DBeaver"; Machine = "PC" }
)
```

## Step 3: Set `Universal.TaskbarPinFolder` / `PathTemplates.TaskbarLayoutFile` (only if needed)

Both ship with working values. `Universal` and `PathTemplates` are hashtables, so a single key merges over the base and everything else stays as shipped.

```powershell
Universal = @{
    TaskbarPinFolder = "{AppData}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
}
PathTemplates = @{
    TaskbarLayoutFile = "C:\ProgramData\provisioning\taskbar_layout.xml"
}
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.HostnameToMachineType
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.HostnameToMachineType
$global:Configuration.Universal.TaskbarPinFolder
$global:Configuration.TaskbarConfiguration | ForEach-Object { [pscustomobject]$_ } | Format-Table Name, Type, Value, Machine, Aumid
$global:MachineSpecificPaths.TaskbarLayoutFile
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    HostnameToMachineType = @{
        Test             = "Test"
        "DESKTOP-GAMING" = "PC"   # "PC" must also be listed in ValidMachineTypes
    }
    TaskbarConfiguration = @(
        @{ Name = "WindowsTerminal"; Type = "AUMID"; Value = "Microsoft.WindowsTerminal_8wekyb3d8bbwe!App"; Machine = "All" }
        @{ Name = "DBeaver";         Type = "Path";  Value = "{User}\AppData\Local\DBeaver\dbeaver.exe"; Aumid = "DBeaver"; Machine = "PC" }
    )
    Universal = @{
        TaskbarPinFolder = "{AppData}\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    }
    PathTemplates = @{
        TaskbarLayoutFile = "C:\ProgramData\provisioning\taskbar_layout.xml"
    }
}
```

## Related

- [`Configure-Taskbar` in the System module reference](../../../modules/system.md#configure-taskbar) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`DetermineMachineType`](../bootstrap/DetermineMachineType.md) - reads the same configuration
- [`Load-PathConfiguration`](../bootstrap/Load-PathConfiguration.md) - reads the same configuration
- [`Rename-Machine`](Rename-Machine.md) - reads the same configuration
- [`Unpin-TaskbarApps`](Unpin-TaskbarApps.md) - clears the pins before the new layout is applied
- [`Set-ShortcutAumid`](Set-ShortcutAumid.md) - stamps the `Aumid` of a `Path` row onto its pin shortcut
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
