function Add-BrowserGroup {
	<#
	.SYNOPSIS
		Adds a browser group to Configuration.psd1.
	.DESCRIPTION
		Creates a new BrowserGroups entry in Configuration.psd1.
		Supports named URLs (recommended) and simple URL lists.
	.PARAMETER GroupName
		Unique name for the browser group.
	.PARAMETER Urls
		Array of URL hashtables: @{ Name = "Label"; Url = "https://..." }
	.PARAMETER SimpleUrls
		Array of URL strings for simple groups without labels.
	.PARAMETER ConfigurationFilePath
		Override the Configuration.psd1 path (for testing).
	.EXAMPLE
		Add-BrowserGroup -GroupName "DevTools" -Urls @(
			@{ Name = "GitHub"; Url = "https://github.com" }
			@{ Name = "StackOverflow"; Url = "https://stackoverflow.com" }
		)
	.EXAMPLE
		Add-BrowserGroup -GroupName "Google" -SimpleUrls @("https://www.google.com/")
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$GroupName,

		[Parameter(Mandatory, ParameterSetName = "Named")]
		[hashtable[]]$Urls,

		[Parameter(Mandatory, ParameterSetName = "Simple")]
		[string[]]$SimpleUrls,

		[string]$ConfigurationFilePath
	)

	$configPath = if ($ConfigurationFilePath) { $ConfigurationFilePath } else { $script:ConfigurationPath }
	if (-not $configPath -or -not (Test-Path $configPath)) {
		Write-LogError "Error: Configuration file not found at '$configPath'!"
		return
	}

	$lines = @(Get-Content -Path $configPath)
	$section = Find-ConfigurationSection -Lines $lines -SectionName "BrowserGroups"
	if (-not $section) {
		Write-LogError "Error: BrowserGroups section not found in Configuration.psd1!"
		return
	}

	$t = "`t"
	$base = $section.Indent + $t
	$entryLines = @()

	if ($PSCmdlet.ParameterSetName -eq "Simple") {
		$entryLines += "$base@{ $GroupName = @("
		foreach ($url in $SimpleUrls) {
			$entryLines += "$base$t$t`"$url`""
		}
		$entryLines += "$base$t)"
		$entryLines += "$base}"
	}
	else {
		$entryLines += "$base@{ $GroupName = @("
		foreach ($url in $Urls) {
			$entryLines += "$base$t$t@{ Name = `"$($url.Name)`"; Url = `"$($url.Url)`" }"
		}
		$entryLines += "$base$t)"
		$entryLines += "$base}"
	}

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $section.EndIndex
	$newLines.Insert($insertIndex, "")
	for ($i = 0; $i -lt $entryLines.Count; $i++) {
		$newLines.Insert($insertIndex + 1 + $i, $entryLines[$i])
	}

	Set-Content -Path $configPath -Value $newLines
	Write-LogSuccess "Browser group '$GroupName' added to Configuration.psd1"

	if (Test-LogVerbose) {
		Write-LogDebug "[Add-BrowserGroup] Inserted at line $insertIndex"
		$entryLines | ForEach-Object { Write-LogDebug "  $_" }
	}
}
