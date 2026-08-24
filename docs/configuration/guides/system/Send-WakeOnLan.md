# Send-WakeOnLan

Sends Wake-on-LAN magic packets to one or more machines configured in `WakeOnLanConfig` in `Configuration.psd1`.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`DefaultWakeOnLanMachine`](../../configuration-reference.md#wake-on-lan-configuration) | string | empty string | Which entry from `WakeOnLanMachines` `Send-WakeOnLan` targets with no argument. |
| [`WakeOnLanConfig`](../../configuration-reference.md#wake-on-lan-configuration) | hashtable of settings | `@{}` (empty) | Wake-on-LAN transport settings `Send-WakeOnLan` and `Test-MachineOnline` use - broadcast address, port, and reachability timeouts. Ships empty and falls back to sensible built-ins. |
| [`WakeOnLanMachines`](../../configuration-reference.md#wake-on-lan-configuration) | array of `@{ Name; Mac; ... }` | `@()` (empty) | The machines `Send-WakeOnLan` can wake. Each entry needs a name and a MAC address. |

## Decisions

1. Which machine should Wake-on-LAN target by default?
    - Options: A `Name` from your `WakeOnLanMachines` array.
    - Default: Empty - `Send-WakeOnLan` asks or reports that nothing is configured.
    - More detail: [`DefaultWakeOnLanMachine`](../../configuration-reference.md#wake-on-lan-configuration)
2. Does your network need non-default Wake-on-LAN settings?
    - Options: Broadcast address, UDP port and timeouts.
    - Default: Empty - built-in defaults.
    - More detail: [`WakeOnLanConfig`](../../configuration-reference.md#wake-on-lan-configuration)
3. Which machines do you want to wake over the LAN?
    - Options: One entry per machine: a name you will type, and its MAC address. Optionally an IP for `Test-MachineOnline`.
    - Default: Empty - `Send-WakeOnLan` has nothing to target.
    - More detail: [`WakeOnLanMachines`](../../configuration-reference.md#wake-on-lan-configuration)
4. MAC addresses are machine-specific and this is a real network identifier. Do you want it in your fork configuration?
    - Options: It goes in `Configuration.local.psd1`, which upstream never tracks. If your fork commits that file, the MAC is committed with it.
    - Default: Add it - the local file is the right place for machine-specific values.
    - More detail: [`WakeOnLanMachines`](../../configuration-reference.md#wake-on-lan-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

On this page that bites on `WakeOnLanMachines` - that key is an array, so whatever you write is the complete value.

## Steps Overview

1. Set `DefaultWakeOnLanMachine`
2. Set `WakeOnLanConfig`
3. Set `WakeOnLanMachines`
4. Reload and confirm the merge landed

## Step 1: Set `DefaultWakeOnLanMachine`

Which entry from `WakeOnLanMachines` `Send-WakeOnLan` targets with no argument.

```powershell
DefaultWakeOnLanMachine = "HomeServer"
```

## Step 2: Set `WakeOnLanConfig`

Wake-on-LAN transport settings `Send-WakeOnLan` and `Test-MachineOnline` use - broadcast address, port, and reachability timeouts. Ships empty and falls back to sensible built-ins.

```powershell
WakeOnLanConfig = @{
    BroadcastAddress = "192.168.1.255"
    Port             = 9
}
```

## Step 3: Set `WakeOnLanMachines`

The machines `Send-WakeOnLan` can wake. Each entry needs a name and a MAC address.

```powershell
WakeOnLanMachines = @(
    @{ Name = "HomeServer"; Mac = "00:11:22:33:44:55"; Ip = "192.168.1.50" }
)
```

## Step 4: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWakeOnLanMachine
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.DefaultWakeOnLanMachine
$global:Configuration.WakeOnLanConfig
$global:Configuration.WakeOnLanMachines
$global:Configuration.WakeOnLanMachines | Format-Table Name, Ip
Test-MachineOnline -Machine "HomeServer" -Quiet
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    DefaultWakeOnLanMachine = "HomeServer"
    WakeOnLanConfig = @{
        BroadcastAddress = "192.168.1.255"
        Port             = 9
    }
    WakeOnLanMachines = @(
        @{ Name = "HomeServer"; Mac = "00:11:22:33:44:55"; Ip = "192.168.1.50" }
    )
}
```

## Related

- [`Send-WakeOnLan` in the System module reference](../../../modules/system.md#send-wakeonlan) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Test-MachineOnline`](Test-MachineOnline.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
