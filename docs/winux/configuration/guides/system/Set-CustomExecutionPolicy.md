# Set-CustomExecutionPolicy

Sets the PowerShell execution policy to `Bypass` for a specified scope by calling `Set-ExecutionPolicy -ExecutionPolicy Bypass`, allowing unsigned scripts to run within that scope without user prompts.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-CustomExecutionPolicy
Set-CustomExecutionPolicy -Scope CurrentUser
```

## Related

- [`Set-CustomExecutionPolicy` in the System module reference](../../../modules/system.md#set-customexecutionpolicy) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
