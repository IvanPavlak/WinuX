# Get-AiSkillManifest

Reads the `UPSTREAM.md` manifest that `Update-AiSkills` writes into a vendored skills source folder, returning the pinned upstream commit and the vendored skill names.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-AiSkillManifest -Path "C:\Repo\AI\Skills\mattpocock\UPSTREAM.md"
(Get-AiSkillManifest -Path "C:\Repo\AI\Skills\mattpocock\UPSTREAM.md").Skills
```

## Related

- [`Get-AiSkillManifest` in the AI module reference](../../../modules/ai.md#get-aiskillmanifest)
- [AI configuration guides](README.md)
