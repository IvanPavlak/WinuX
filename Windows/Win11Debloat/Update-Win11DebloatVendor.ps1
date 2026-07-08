function Update-Win11DebloatVendor {
	<#
    .SYNOPSIS
        Downloads and vendors a Win11Debloat release into this repository.

    .DESCRIPTION
        Fetches Win11Debloat from GitHub as a zipball and replaces the local
        `Windows\Win11Debloat\vendor` folder contents.

        This keeps bootstrap execution fully local while still allowing easy,
        explicit updates to newer upstream releases.

    .PARAMETER ReleaseTag
        Release tag to vendor (example: 2026.05.11). Use `latest` (default)
        to fetch the newest GitHub release.

    .PARAMETER Repository
        GitHub repository in `owner/name` format.

    .EXAMPLE
        Update-Win11DebloatVendor
        Vendors the latest Win11Debloat release.

    .EXAMPLE
        Update-Win11DebloatVendor -ReleaseTag "2026.05.11"
        Vendors a specific Win11Debloat release tag.
    #>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$ReleaseTag = "latest",

		[Parameter()]
		[string]$Repository = "Raphire/Win11Debloat"
	)

	try {
		$scriptDirectory = Split-Path -Parent $PSCommandPath
		$vendorPath = Join-Path $scriptDirectory "vendor"

		$tempRoot = Join-Path $env:TEMP "win11debloat-vendor-update"
		$zipPath = Join-Path $tempRoot "win11debloat.zip"
		$extractPath = Join-Path $tempRoot "extract"

		if (Test-Path -Path $tempRoot) {
			Remove-Item -Path $tempRoot -Recurse -Force
		}

		New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

		$releaseApiUrl = if ($ReleaseTag -eq "latest") {
			"https://api.github.com/repos/$Repository/releases/latest"
		}
		else {
			"https://api.github.com/repos/$Repository/releases/tags/$ReleaseTag"
		}

		Write-Host -ForegroundColor White "`nDownloading Win11Debloat release metadata..."
		$release = Invoke-RestMethod -Uri $releaseApiUrl

		if (-not $release.zipball_url) {
			throw "Unable to resolve zipball URL for release '$ReleaseTag'."
		}

		Write-Host -ForegroundColor White "`nDownloading archive..."
		Invoke-WebRequest -Uri $release.zipball_url -OutFile $zipPath

		Write-Host -ForegroundColor White "`nExtracting archive..."
		Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

		$sourceRoot = (Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1).FullName
		if (-not $sourceRoot) {
			throw "Unable to locate extracted Win11Debloat folder."
		}

		if (Test-Path -Path $vendorPath) {
			Remove-Item -Path $vendorPath -Recurse -Force
		}

		New-Item -ItemType Directory -Path $vendorPath -Force | Out-Null
		Copy-Item -Path (Join-Path $sourceRoot "*") -Destination $vendorPath -Recurse -Force

		$metaPath = Join-Path $scriptDirectory "VENDORED_VERSION.txt"
		$metaContent = @(
			"SourceRepo: $Repository",
			"ReleaseTag: $($release.tag_name)",
			"PublishedAt: $($release.published_at)",
			"DownloadedAt: $((Get-Date).ToString('s'))",
			"ZipballUrl: $($release.zipball_url)"
		)

		Set-Content -Path $metaPath -Value $metaContent

		Write-Host -ForegroundColor Green "`n=> Win11Debloat vendor folder updated to release '$($release.tag_name)'"
	}
	catch {
		Write-Host -ForegroundColor Red "`n=> Error: $($_.Exception.Message)"
		throw
	}
	finally {
		$tempRoot = Join-Path $env:TEMP "win11debloat-vendor-update"
		if (Test-Path -Path $tempRoot) {
			Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}

Update-Win11DebloatVendor @PSBoundParameters
