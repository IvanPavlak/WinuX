#Requires -Modules Pester

BeforeAll {
	$SystemFunctionsPath = Join-Path (Get-RepositoryPath).Modules "System\Functions"
	. "$SystemFunctionsPath\New-SixelImage.ps1"
}

Describe "New-SixelImage" {
	BeforeEach {
		Mock Write-LogDebug { }

		$script:CacheDir = Join-Path $TestDrive "SixelCache"
		$script:SourceImage = Join-Path $TestDrive "Logo.png"
		Set-Content -LiteralPath $script:SourceImage -Value "not really a png, never decoded in these tests" -NoNewline
	}

	It "returns nothing when the source image does not exist" {
		New-SixelImage -Path (Join-Path $TestDrive "Absent.png") -MaxPixelWidth 360 -MaxPixelHeight 320 -CachePath $script:CacheDir |
		Should -BeNullOrEmpty
	}

	It "returns nothing when ImageMagick is not installed" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "magick" }

		New-SixelImage -Path $script:SourceImage -MaxPixelWidth 360 -MaxPixelHeight 320 -CachePath $script:CacheDir |
		Should -BeNullOrEmpty
	}

	It "reuses a cached rendering without needing ImageMagick at all" {
		# A warm cache is just a file read, so the logo still renders on a machine where
		# ImageMagick was never installed or has been removed.
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "magick" }

		$item = Get-Item -LiteralPath $script:SourceImage
		$fingerprint = "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
		$hash = [BitConverter]::ToString(
			[Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint))
		) -replace '-', ''
		$expected = Join-Path $script:CacheDir "Logo_360x320_$($hash.Substring(0, 8).ToLower()).six"

		New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
		Set-Content -LiteralPath $expected -Value "pretend sixel payload" -NoNewline

		New-SixelImage -Path $script:SourceImage -MaxPixelWidth 360 -MaxPixelHeight 320 -CachePath $script:CacheDir |
		Should -Be $expected
	}

	It "ignores a cache entry for a different pixel box" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "magick" }

		$item = Get-Item -LiteralPath $script:SourceImage
		$fingerprint = "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
		$hash = [BitConverter]::ToString(
			[Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint))
		) -replace '-', ''

		New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
		Set-Content -LiteralPath (Join-Path $script:CacheDir "Logo_360x320_$($hash.Substring(0, 8).ToLower()).six") -Value "payload" -NoNewline

		# Same image, different box - the 360x320 entry must not be handed back for a 200x180 request.
		New-SixelImage -Path $script:SourceImage -MaxPixelWidth 200 -MaxPixelHeight 180 -CachePath $script:CacheDir |
		Should -BeNullOrEmpty
	}

	It "invalidates the cache when the source image is edited" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "magick" }

		$item = Get-Item -LiteralPath $script:SourceImage
		$fingerprint = "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
		$hash = [BitConverter]::ToString(
			[Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint))
		) -replace '-', ''
		$stale = Join-Path $script:CacheDir "Logo_360x320_$($hash.Substring(0, 8).ToLower()).six"

		New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
		Set-Content -LiteralPath $stale -Value "payload for the old image" -NoNewline

		# Replace the source with different content, which changes both its length and its
		# last-write time - the two halves of the fingerprint.
		Set-Content -LiteralPath $script:SourceImage -Value "a different image entirely, longer than before" -NoNewline

		New-SixelImage -Path $script:SourceImage -MaxPixelWidth 360 -MaxPixelHeight 320 -CachePath $script:CacheDir |
		Should -BeNullOrEmpty
	}

	It "ignores an empty cache entry rather than handing back a zero-byte sixel" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "magick" }

		$item = Get-Item -LiteralPath $script:SourceImage
		$fingerprint = "$($item.FullName)|$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
		$hash = [BitConverter]::ToString(
			[Security.Cryptography.MD5]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($fingerprint))
		) -replace '-', ''
		$empty = Join-Path $script:CacheDir "Logo_360x320_$($hash.Substring(0, 8).ToLower()).six"

		New-Item -ItemType Directory -Path $script:CacheDir -Force | Out-Null
		New-Item -ItemType File -Path $empty -Force | Out-Null

		New-SixelImage -Path $script:SourceImage -MaxPixelWidth 360 -MaxPixelHeight 320 -CachePath $script:CacheDir |
		Should -BeNullOrEmpty
	}

	It "rejects a degenerate pixel box" {
		{ New-SixelImage -Path $script:SourceImage -MaxPixelWidth 0 -MaxPixelHeight 320 } | Should -Throw
		{ New-SixelImage -Path $script:SourceImage -MaxPixelWidth 360 -MaxPixelHeight 0 } | Should -Throw
	}

	It "never throws when it cannot produce a sixel" {
		Mock Get-Command { $null } -ParameterFilter { $Name -eq "magick" }

		{ New-SixelImage -Path $script:SourceImage -MaxPixelWidth 360 -MaxPixelHeight 320 -CachePath $script:CacheDir } |
		Should -Not -Throw
	}
}
