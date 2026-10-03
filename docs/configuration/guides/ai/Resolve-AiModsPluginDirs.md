# Resolve-AiModsPluginDirs

Computes the new `CLAUDE_CODE_PLUGIN_DIRS` value from the current one and the mods `Deploy-AiMods` just linked: the deployed links first, then every entry added by hand, with entries under the harness that no longer have a mod dropped.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Resolve-AiModsPluginDirs -Existing "D:\Plugins\other" -Deployed "C:\Users\You\.claude\mods\my-mod" -Harness "C:\Users\You\.claude\mods" -Separator ';'
Resolve-AiModsPluginDirs -Existing "/opt/plugins/x" -Deployed "/home/you/.claude/mods/my-mod" -Harness "/home/you/.claude/mods" -Separator ':'
```

## Related

- [`Resolve-AiModsPluginDirs` in the AI module reference](../../../modules/ai.md#resolve-aimodsplugindirs)
- [AI configuration guides](README.md)
