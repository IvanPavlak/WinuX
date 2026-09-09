# Get-AiSkillDescription

Extracts the `description:` from a `SKILL.md` YAML frontmatter as one line of Markdown table text, for the skill table `Update-AiSkills` writes into `UPSTREAM.md`.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-AiSkillDescription -SkillFile "C:\Repo\AI\Skills\mattpocock\grill-me\SKILL.md"
```

## Related

- [`Get-AiSkillDescription` in the AI module reference](../../../modules/ai.md#get-aiskilldescription)
- [AI configuration guides](README.md)
