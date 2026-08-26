# Initialize-Configuration

First-run writer that captures your personal identity and paths into a sibling `Configuration.local.psd1` override - never into the committed `Configuration.psd1`.

> [!NOTE]
> **An existing `Configuration.local.psd1` is never replaced.** If the file is there at all, this function leaves it alone and returns, whatever it contains - so re-running `Bootstrap -WithInitialSetup`, or double-clicking `WinuX.exe` inside an existing clone, can never regenerate your override down to the three keys it writes. `-Force` rewrites it anyway, but first copies the current file into the unified backup sink (`Backups/Windows/Config/Configuration.local/<timestamp>/`, see [Backups](../../../reference/backups.md)) and aborts if that copy fails.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Initialize-Configuration
Initialize-Configuration -GitName "Jane Doe" -GitEmail "jane@example.com" -DevPath "D:\Dev"
```

## Related

- [`Initialize-Configuration` in the Bootstrap module reference](../../../modules/bootstrap.md#initialize-configuration) - parameters, usage and behaviour
- [Bootstrap configuration guides](README.md) - every guide for this module
