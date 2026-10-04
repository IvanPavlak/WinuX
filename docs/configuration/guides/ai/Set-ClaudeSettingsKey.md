# Set-ClaudeSettingsKey

Sets one key, at any depth, of a Claude Code `settings.json` by its dotted path, creating the file and the objects along the path when they are missing and keeping every other key.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-ClaudeSettingsKey -Path "extraKnownMarketplaces.my-marketplace" -Value @{ source = @{ source = "github"; repo = "MyOrg/MyMarketplace" } }
Set-ClaudeSettingsKey -Path "pluginConfigs.my-plugin.options" -Value @{ theme = "light" } -WhatIf
Set-ClaudeSettingsKey -Path "enabledPlugins.my-plugin@my-marketplace" -Value $true -SettingsPath "\\wsl.localhost\Ubuntu\home\you\.claude\settings.json"
```

## Related

- [`Set-ClaudeSettingsKey` in the AI module reference](../../../modules/ai.md#set-claudesettingskey)
- [AI configuration guides](README.md)
