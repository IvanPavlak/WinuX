# ConvertTo-AiManagedSettings

Renders a rules item's `managed-settings.json` for one managed-settings folder (`{ManagedDir}` replaced, the AI profile's Plan pinned through `forceLoginOrgUUID`, the ownership guard wired into `UserPromptSubmit` and `PreToolUse`, the repository policy hook into `PreToolUse`) and the `ai-profile.conf` both read next to it. It takes everything as parameters - the AI profile comes from `Resolve-AiProfile`, configured on its own page.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$rendered = ConvertTo-AiManagedSettings -Template (Get-Content -Raw "C:\Repo\AI\Rules\own\MyRules\managed-settings.json") -ManagedDir "C:\Program Files\ClaudeCode" -AiProfile (Resolve-AiProfile)
$rendered.Settings
$rendered.ProfileConf
```

## Related

- [`ConvertTo-AiManagedSettings` in the AI module reference](../../../modules/ai.md#convertto-aimanagedsettings)
- [AI configuration guides](README.md)
