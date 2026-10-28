# Open-RiseupVPN

Opens RiseupVPN via `Start-Application`, which reads the executable from `Universal.RiseupVpnExe` (ships empty - set it in `Configuration.local.psd1`, see [Start-Application](Start-Application.md)); this function itself reads nothing.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Open-RiseupVPN
```

## Related

- [`Open-RiseupVPN` in the Application module reference](../../../modules/application.md#open-riseupvpn) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
