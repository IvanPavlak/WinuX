# Sync-AiManifestCache

Clones the pinned refs the manifest sources need into `%LOCALAPPDATA%\WinuX\ai-manifests\<owner>\<repo>\<ref>\`, makes the derived copies of `strip-invocation-guard` and `rename=` rows, and with `-Check` reports the rows whose upstream has moved on. It takes the resolved configuration as a parameter; the manifest sources are `AiArtifacts.Manifests`, configured on the [`Deploy-AiArtifacts`](Deploy-AiArtifacts.md) page.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Sync-AiManifestCache
(Sync-AiManifestCache -Check).Behind | Format-Table Manifest, Name, Ref, Head
```

## Related

- [`Sync-AiManifestCache` in the AI module reference](../../../modules/ai.md#sync-aimanifestcache)
- [AI configuration guides](README.md)
