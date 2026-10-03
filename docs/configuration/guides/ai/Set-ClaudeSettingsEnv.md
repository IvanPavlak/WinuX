# Set-ClaudeSettingsEnv

Sets one variable in the `env` block of a Claude Code `settings.json`, creating the file when it is missing and keeping every other key, nested object and `env` variable.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Set-ClaudeSettingsEnv -Name CLAUDE_CODE_PLUGIN_DIRS -Value "C:\Users\You\.claude\mods\my-mod"
Set-ClaudeSettingsEnv -Name CLAUDE_CODE_PLUGIN_DIRS -Value "/home/you/.claude/mods/my-mod" -SettingsPath "\\wsl.localhost\Ubuntu\home\you\.claude\settings.json"
Set-ClaudeSettingsEnv -Name CLAUDE_CODE_PLUGIN_DIRS -Value "" -WhatIf
```

## Related

- [`Set-ClaudeSettingsEnv` in the AI module reference](../../../modules/ai.md#set-claudesettingsenv)
- [AI configuration guides](README.md)
