# New-SixelImage

Encodes an image as a cached DEC sixel file scaled to fit a pixel box, so a terminal that renders sixel can display it inside a fixed block of character cells.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

Requires ImageMagick on PATH for the first encode of each size (`winget install ImageMagick.ImageMagick`). A warm cache needs nothing installed.

## Usage

```powershell
New-SixelImage -Path $logo -MaxPixelWidth 360 -MaxPixelHeight 320
New-SixelImage -Path $logo -MaxPixelWidth 360 -MaxPixelHeight 320 -Force
New-SixelImage -Path $logo -MaxPixelWidth 360 -MaxPixelHeight 320 -CachePath "D:\SixelCache"
```

## Related

- [`New-SixelImage` in the System module reference](../../../modules/system.md#new-sixelimage) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
- [`Get-FastfetchLogoArgument`](Get-FastfetchLogoArgument.md) - the caller that needs this encoder
