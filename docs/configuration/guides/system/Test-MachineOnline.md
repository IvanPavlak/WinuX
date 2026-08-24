# Test-MachineOnline

Tests whether a machine is online (reachable via ICMP ping) and returns a boolean for use in conditional logic.

> [!NOTE]
> Every value on this page belongs in `Configuration.local.psd1`, never in the base `Configuration.psd1`. The base file is upstream's, it ships empty-by-default, and it is deep-merged with your local file at load time by `Load-PathConfiguration`. See [Fork Model](../../../contributing/fork-model.md).

## Configuration Keys

| Key | Type | Default (base) | What it controls |
| --- | ---- | -------------- | ---------------- |
| [`WakeOnLanConfig`](../../configuration-reference.md#wake-on-lan-configuration) | hashtable of settings | `@{}` (empty) | Wake-on-LAN transport settings `Send-WakeOnLan` and `Test-MachineOnline` use - broadcast address, port, and reachability timeouts. Ships empty and falls back to sensible built-ins. |

## Decisions

1. Does your network need non-default Wake-on-LAN settings?
    - Options: Broadcast address, UDP port and timeouts.
    - Default: Empty - built-in defaults.
    - More detail: [`WakeOnLanConfig`](../../configuration-reference.md#wake-on-lan-configuration)

## Where to Put Values

All of it goes in `Configuration.local.psd1`, at the repository's `Windows/PowerShell/` directory, beside the base `Configuration.psd1`. Create the file if it does not exist yet - a minimal one is a single `@{}` hashtable - or let `Initialize-Configuration` write the skeleton for you.

> [!WARNING]
> The merge is not uniform. **Hashtables deep-merge per key**, so adding one entry to a hashtable leaves every other entry alone. **Arrays and scalars replace wholesale**, so supplying an array key in your local file discards the entire base array. When you want to *add* to a shipped array, copy the whole base array out of `Configuration.psd1` first and add your entry to the copy.

## Steps Overview

1. Set `WakeOnLanConfig`
2. Reload and confirm the merge landed

## Step 1: Set `WakeOnLanConfig`

Wake-on-LAN transport settings `Send-WakeOnLan` and `Test-MachineOnline` use - broadcast address, port, and reachability timeouts. Ships empty and falls back to sensible built-ins.

```powershell
WakeOnLanConfig = @{
    BroadcastAddress = "192.168.1.255"
    Port             = 9
}
```

## Step 2: Reload and confirm the merge landed

Reload the profile, then read the merged value back. `$global:Configuration` after a reload is the ground truth - if what you set is not there, the local file did not parse or the key is nested one level away from where you put it.

```powershell
Reload-PowerShellProfile
$global:Configuration.WakeOnLanConfig
```

## Verification

Read-only checks. None of these change anything.

```powershell
Reload-PowerShellProfile
$global:Configuration.WakeOnLanConfig
Test-MachineOnline -Machine "HomeServer" -Quiet
```

If a value reads back as empty, the two usual causes are a parse error in `Configuration.local.psd1` (run `Test-ConfigurationSchema`) and a key placed at the wrong nesting level.

## Complete Example

A `Configuration.local.psd1` that configures everything on this page. Values are illustrative - substitute your own.

```powershell
# Configuration.local.psd1
@{
    WakeOnLanConfig = @{
        BroadcastAddress = "192.168.1.255"
        Port             = 9
    }
}
```

## Related

- [`Test-MachineOnline` in the System module reference](../../../modules/system.md#test-machineonline) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [Add Symbolic Link](add-symbolic-link.md) - link shapes, placeholders and the WSL cases
- [`Send-WakeOnLan`](Send-WakeOnLan.md) - reads the same configuration
- [WinuXConfigurator](../../winux-configurator.md) - have an AI assistant walk these decisions with you
- [Configuration reference](../../configuration-reference.md) - every key, section by section
