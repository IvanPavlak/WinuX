# Send-WakeOnLan

Sends Wake-on-LAN magic packets to one or more machines configured in `WakeOnLanConfig` in `Configuration.psd1`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultWakeOnLanMachine`](../../configuration-reference.md#wake-on-lan-configuration) | string | empty string | Which machine `Send-WakeOnLan` targets when you press [Enter] with no argument. |
| [`WakeOnLanConfig`](../../configuration-reference.md#wake-on-lan-configuration) | ordered list of machines (one single-key hashtable each) | `@()` (empty) | Every machine `Send-WakeOnLan` can wake: the machine name is the key, its MAC address, broadcast address, port and optional `Address` are the value. The menu follows the order you write them in. |

## Decisions

1. Which machines do you want to wake over the LAN, and in what order?
    - Options: One entry per machine: the name you will type, its MAC address, the subnet broadcast address and port. Optionally an `Address` (IP or hostname) so `Send-WakeOnLan` can skip a machine that is already up and confirm one that woke.
    - Default: Empty - `Send-WakeOnLan` has nothing to target.
    - More detail: [`WakeOnLanConfig`](../../configuration-reference.md#wake-on-lan-configuration)
2. Which machine should Wake-on-LAN target by default?
    - Options: A machine name from `WakeOnLanConfig`.
    - Default: Empty - `Send-WakeOnLan` asks or reports that nothing is configured.
    - More detail: [`DefaultWakeOnLanMachine`](../../configuration-reference.md#wake-on-lan-configuration)
3. MAC addresses are machine-specific and this is a real network identifier. Do you want it in your fork configuration?
    - Options: It goes in `Configuration.local.psd1`, which upstream never tracks. If your fork commits that file, the MAC is committed with it.
    - Default: Add it - the local file is the right place for machine-specific values.
    - More detail: [`WakeOnLanConfig`](../../configuration-reference.md#wake-on-lan-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `WakeOnLanConfig` - it is an ordered list, so whatever you write is the complete value.

## Steps Overview

1. Set `WakeOnLanConfig`
2. Set `DefaultWakeOnLanMachine`
3. Reload and confirm the merge landed

## Step 1: Set `WakeOnLanConfig`

Every machine `Send-WakeOnLan` can wake, in the order the menu offers them. Each entry is a single-key hashtable: the key is the machine name you will type, the value is how to reach it. Quote a name that contains spaces.

`Send-WakeOnLan` appends its own `All` and `None` options to the menu - they are not machines, so you never configure them.

```powershell
WakeOnLanConfig = @(
    @{ HomeServer = @{
            MacAddress                     = "00-11-22-33-44-55"
            SubNetSpecificBroadcastAddress = "192.168.1.255"
            Address                        = "192.168.1.50"
            Port                           = 9
        }
    }
)
```

## Step 2: Set `DefaultWakeOnLanMachine`

Which machine `Send-WakeOnLan` targets when you press [Enter] with no argument.

```powershell
DefaultWakeOnLanMachine = "HomeServer"
```

## Step 3: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.WakeOnLanConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWakeOnLanMachine
$global:Configuration.WakeOnLanConfig
Get-OrderedNames $global:Configuration.WakeOnLanConfig
Get-OrderedEntry $global:Configuration.WakeOnLanConfig "HomeServer"
Test-MachineOnline -Machine "HomeServer" -Quiet
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    WakeOnLanConfig = @(
        @{ HomeServer = @{
                MacAddress                     = "00-11-22-33-44-55"
                SubNetSpecificBroadcastAddress = "192.168.1.255"
                Address                        = "192.168.1.50"
                Port                           = 9
            }
        }
    )
    DefaultWakeOnLanMachine = "HomeServer"
}
```

## Related

- [`Send-WakeOnLan` in the System module reference](../../../modules/system.md#send-wakeonlan) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Test-MachineOnline`](Test-MachineOnline.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
