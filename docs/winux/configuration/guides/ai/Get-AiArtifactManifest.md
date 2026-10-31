# Get-AiArtifactManifest

Reads an AI artifact manifest - the tab-separated list of pinned third-party items (`name`, `kind`, `scope`, `source`, `ref`, `path`, `install`) a manifest source names - and reports every row that breaks the format with its line number. Which manifest files are read is `AiArtifacts.Manifests`, configured on the [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) page.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$manifest = Get-AiArtifactManifest -Path "C:\Users\You\Development\GitHub\MySkills\third-party\manifest.tsv"
$manifest.Rows | Select-Object Name, Kind, Scope, Ref
$manifest.Problems
```

## Related

- [`Get-AiArtifactManifest` in the AI module reference](../../../modules/ai.md#get-aiartifactmanifest)
- [AI configuration guides](README.md)
