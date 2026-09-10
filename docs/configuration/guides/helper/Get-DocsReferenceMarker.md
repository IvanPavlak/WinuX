# Get-DocsReferenceMarker

Reads the reference marker a documentation page declares about its own entries, so `List-Functions` and the Infrastructure function-reference test agree on which sovereign pages are a function reference.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Get-DocsReferenceMarker -Path "C:\Repo\docs\custom\application.md"
(Get-DocsReferenceMarker -Path "C:\Repo\docs\custom\ai.md").Kind
```

What it reads is a convention rather than a setting: an HTML comment at the top of each page in `docs/custom/`, one of `<!-- reference: functions windows/Custom -->`, `<!-- reference: skills -->`, `<!-- reference: guide -->` or `<!-- reference: none -->`. A page with no valid marker fails the Infrastructure function-reference test on purpose, so a page cannot opt itself out of checking by omission or by a typo. The [Custom area docs](../../../custom/README.md) is the page-author's view of the same convention.

## Related

- [`Get-DocsReferenceMarker` in the Helper module reference](../../../modules/helper.md#get-docsreferencemarker)
- [`List-Functions`](List-Functions.md) - the caller whose `docs/custom/` parsing this gates
- [Custom area docs](../../../custom/README.md) - what to write at the top of a sovereign page
- [Helper configuration guides](README.md)
