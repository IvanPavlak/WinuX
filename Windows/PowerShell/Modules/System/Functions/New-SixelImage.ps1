function New-SixelImage {
	<#
	.SYNOPSIS
		Encodes an image as a cached sixel file, scaled to fit a pixel box.

	.DESCRIPTION
		Runs ImageMagick to convert any image it can read into DEC sixel graphics - the one
		inline-image protocol Windows Terminal renders - and caches the result so the conversion
		is paid once per distinct size rather than on every shell start.

		The image is fitted INSIDE the given pixel box with its aspect ratio preserved, never
		stretched and never cropped, so the caller can reserve a fixed block of character cells
		and know the image cannot spill out of it. Transparency is preserved: the encoder writes
		the sixel background-select parameter that leaves untouched pixels showing whatever is
		behind them, so a logo with an alpha channel does not arrive on a black rectangle.

		Caching is keyed on the box AND on the source file's last-write time and length, so
		editing or replacing the source image invalidates the cache without any bookkeeping. A
		cache hit costs two file stats; a miss costs one ImageMagick invocation, around 120ms for
		a small logo. ImageMagick is looked for only on a miss, so a warm cache keeps working on a
		machine that does not have it installed.

		Returns the path of the sixel file, or $null - never throws - when ImageMagick is not
		installed, the source image is missing, or the conversion produces nothing. Every caller
		is expected to treat $null as "fall back to text".

	.PARAMETER Path
		The source image. Anything ImageMagick can decode (PNG, JPEG, SVG, ICO, WEBP).

	.PARAMETER MaxPixelWidth
		Width of the box to fit the image into, in pixels.

	.PARAMETER MaxPixelHeight
		Height of the box to fit the image into, in pixels.

	.PARAMETER CachePath
		Directory to hold the generated sixel files, created if missing. Defaults to
		`$env:LOCALAPPDATA\WinuX\SixelCache`.

	.PARAMETER Force
		Re-encode even when a valid cache entry exists.

	.EXAMPLE
		New-SixelImage -Path "C:\Logos\Flag.png" -MaxPixelWidth 360 -MaxPixelHeight 320
		Returns the path of a sixel rendering of Flag.png fitted inside 360x320 pixels.

	.EXAMPLE
		New-SixelImage -Path $logo -MaxPixelWidth 360 -MaxPixelHeight 320 -Force
		Re-encodes even if the cache already holds that size.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Path,

		[Parameter(Mandatory)]
		[ValidateRange(1, 20000)]
		[int]$MaxPixelWidth,

		[Parameter(Mandatory)]
		[ValidateRange(1, 20000)]
		[int]$MaxPixelHeight,

		[string]$CachePath = (Join-Path $env:LOCALAPPDATA "WinuX\SixelCache"),

		[switch]$Force
	)

	$source = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
	if (-not $source) {
		Write-LogDebug "[New-SixelImage] source image not found [$Path]"
		return $null
	}

	# The stamp makes the cache self-invalidating: a different box, or a source that was edited or
	# swapped, produces a different file name, so a stale entry is never read and never has to be
	# deleted. Truncated to 8 hex characters - collisions across one user's logo files are not a
	# concern, and a full hash makes for an unreadable file name.
	$fingerprint = "$($source.FullName)|$($source.Length)|$($source.LastWriteTimeUtc.Ticks)"
	$hash = [BitConverter]::ToString(
		[Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint))
	) -replace '-', ''
	$stamp = $hash.Substring(0, 8).ToLower()
	$target = Join-Path $CachePath "$($source.BaseName)_${MaxPixelWidth}x${MaxPixelHeight}_$stamp.six"

	if (-not $Force) {
		$cached = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
		if ($cached -and $cached.Length -gt 0) {
			Write-LogDebug "[New-SixelImage] cache hit [$target]"
			return $cached.FullName
		}
	}

	# Discovered only on a miss, so a warm cache renders the logo on a machine without ImageMagick.
	$magick = Get-Command -Name magick -CommandType Application -ErrorAction SilentlyContinue |
		Select-Object -First 1
	if (-not $magick) {
		Write-LogDebug "[New-SixelImage] ImageMagick (magick) not on PATH - cannot encode sixel"
		return $null
	}

	try {
		if (-not (Test-Path -LiteralPath $CachePath)) {
			New-Item -ItemType Directory -Path $CachePath -Force | Out-Null
		}

		# -resize WxH fits inside the box and preserves the aspect ratio (no '!' or '^'), and
		# -background none keeps the alpha channel so the sixel is written with transparency.
		& $magick.Source $source.FullName -resize "${MaxPixelWidth}x${MaxPixelHeight}" -background none "sixel:$target" 2>&1 |
			ForEach-Object { Write-LogDebug "[New-SixelImage] magick => $_" }

		$written = Get-Item -LiteralPath $target -ErrorAction SilentlyContinue
		if (-not $written -or $written.Length -eq 0) {
			Write-LogDebug "[New-SixelImage] encoding produced no output for [$($source.FullName)]" -Style Warning
			return $null
		}

		Write-LogDebug "[New-SixelImage] encoded [$($source.Name)] into ${MaxPixelWidth}x${MaxPixelHeight}px sixel [$target] ($([math]::Round($written.Length / 1KB))KB)"
		return $written.FullName
	}
	catch {
		Write-LogDebug "[New-SixelImage] encoding failed => $($_.Exception.Message)" -Style Warning
		return $null
	}
}
