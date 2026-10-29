# Invoke-ProcessWithTimeout

Runs a program with no window, captures its output, and stops it after a time limit.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Invoke-ProcessWithTimeout -FilePath "choco" -ArgumentList "pin", "list", "-r"
(Invoke-ProcessWithTimeout -FilePath "git" -ArgumentList "fetch" -TimeoutSeconds 10).TimedOut
```

## Related

- [`Invoke-ProcessWithTimeout` in the Helper module reference](../../../modules/helper.md#invoke-processwithtimeout) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
