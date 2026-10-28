# Wait-BrowserWindowReady

Polls the window list until at least one window of the given process (optionally narrowed by a title regex) is present, or the timeout expires.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Wait-BrowserWindowReady -ProcessName "brave"
Wait-BrowserWindowReady -ProcessName "msedge" -TitlePattern "Microsoft.{0,2}Edge" -TimeoutSeconds 10
```

## Related

- [`Wait-BrowserWindowReady` in the Application module reference](../../../modules/application.md#wait-browserwindowready) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
