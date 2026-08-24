# Open-Terminal

Opens Windows Terminal in a new window or in the current shell, optionally running one or more commands in separate tabs with custom tab titles. Alias: `t`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Open-Terminal
Open-Terminal -Administrator
Open-Terminal -Command "git status", "npm run dev"
```

## Related

- [`Open-Terminal` in the Application module reference](../../../modules/application.md#open-terminal) - parameters, usage and behaviour
- [Application configuration guides](README.md) - every guide for this module
