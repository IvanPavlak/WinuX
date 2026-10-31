# Deploy-AiManagedSettings

Writes the `managed-settings` destination of a harness as an administrator-owned copy - the rendered `managed-settings.json`, the rules item's `hooks\` folder, and with an AI profile the ownership guard, the repository policy hook and `ai-profile.conf` - on Windows and, as root, in WSL. `Deploy-AiArtifacts` calls it with the plan destination; the keys behind it are on the [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) and [`Resolve-AiProfile`](Resolve-AiProfile.md) pages.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$destination = (Get-AiArtifactPlan -Kind Rules).Destinations | Where-Object { $_.Hooks -contains "managed-settings" } | Select-Object -First 1
Deploy-AiManagedSettings -Destination $destination -AiProfile (Resolve-AiProfile) -WhatIf
```

## Related

- [`Deploy-AiManagedSettings` in the AI module reference](../../../modules/ai.md#deploy-aimanagedsettings)
- [AI configuration guides](README.md)
