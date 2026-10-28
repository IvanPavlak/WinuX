# Get-ChassisType

Returns the machine's SMBIOS chassis type codes (`Win32_SystemEnclosure.ChassisTypes` - 3 for a desktop, 9 or 10 for a laptop), read from the hardware once and then from a per-machine cache file, because the CIM query was the largest part of `Test-PowerPlan`'s cost on every shell start and a machine does not change its chassis.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

The cache lives outside the repository, at `%LOCALAPPDATA%\WinuX\ChassisTypes.txt` (`-CachePath` overrides it). Delete it or call with `-Refresh` to re-read the hardware.

## Usage

```powershell
Get-ChassisType
Get-ChassisType -Refresh
```

## Related

- [`Get-ChassisType` in the System module reference](../../../modules/system.md#get-chassistype) - parameters, usage and behaviour
- [`Test-PowerPlan`](Test-PowerPlan.md) - decides the expected power plan from these codes and `LaptopChassisTypes`
- [System configuration guides](README.md) - every guide for this module
