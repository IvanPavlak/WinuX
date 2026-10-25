# Update-AiSkills

Deprecated since 1.6.0, removed in 2.0.0: warns once per session, then runs `Update-AiArtifacts` with `-Source` and `-Check` forwarded.

> [!WARNING]
> Configure and call [`Update-AiArtifacts`](Update-AiArtifacts.md) instead. The deprecated keys this function used to read are read and mapped by [`Resolve-AiArtifactsConfig`](Resolve-AiArtifactsConfig.md) until 2.0.0; [Migrating from 1.5](../../../ai/artifacts.md#migrating-from-15) lists each one with its replacement.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Update-AiSkills
Update-AiSkills -Source mattpocock
Update-AiSkills -Check
```

## Related

- [`Update-AiSkills` in the AI module reference](../../../modules/ai.md#update-aiskills)
- [`Update-AiArtifacts`](Update-AiArtifacts.md) - the replacement
- [AI configuration guides](README.md)
