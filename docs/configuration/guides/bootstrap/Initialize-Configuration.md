# Initialize-Configuration

First-run writer that captures your personal identity and paths into a sibling `Configuration.local.psd1` override - never into the committed `Configuration.psd1`.

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
