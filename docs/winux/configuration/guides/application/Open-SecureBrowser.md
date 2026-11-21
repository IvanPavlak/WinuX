# Open-SecureBrowser

Establishes a VPN-protected Tor Browser session with IP verification. It reads nothing itself, but needs `Universal.RiseupVpnExe` (through [Open-RiseupVPN](Open-RiseupVPN.md)) and the `Universal.Browsers.Tor` entry (through [Open-Browser](Open-Browser.md)).

> [!WARNING]
> **Deprecated since 2.17.0, removed in 3.0.0.** `Open-SecureBrowser` serves one personal setup rather than the framework. To keep it, copy the function file (and its test) into your fork's Custom area under `Windows/PowerShell/Modules/Custom/<Module>/Functions/`, list it in `Custom.psd1`, and keep its keys in `Configuration.local.psd1`, where the copy goes on reading them. The function keeps working until 3.0.0 and warns once per session.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Open-SecureBrowser
```

## Related

- [`Open-SecureBrowser` in the Application module reference](../../../modules/application.md#open-securebrowser) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
