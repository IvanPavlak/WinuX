function Add-SymbolicLink {
	<#
	.SYNOPSIS
		Adds a symbolic link entry to Configuration.psd1.
	.DESCRIPTION
		Creates a new SymbolicLinks entry with Path and Target.
		Supports both simple (single link) and nested (multiple files) entries.
	.PARAMETER Name
		Name for the symbolic link entry (typically the app name).
	.PARAMETER Path
		The symlink path (where the link should be created). Use placeholders.
	.PARAMETER Target
		The actual file path (target of the link). Use placeholders.
	.PARAMETER Links
		For nested entries: array of hashtables with Name, Path, and Target keys.
	.PARAMETER ConfigurationFilePath
		Override the Configuration.psd1 path (for testing).
	.EXAMPLE
		Add-SymbolicLink -Name "MyApp" -Path "{AppData}\MyApp\config.json" -Target "{RepoRoot}\MyApp\config.json"
	.EXAMPLE
		Add-SymbolicLink -Name "MyApp" -Links @(
			@{ Name = "Settings"; Path = "{AppData}\MyApp\settings.json"; Target = "{RepoRoot}\MyApp\settings.json" }
			@{ Name = "Config"; Path = "{AppData}\MyApp\config.yaml"; Target = "{RepoRoot}\MyApp\config.yaml" }
		)
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory, Position = 0)]
		[string]$Name,

		[Parameter(Mandatory, ParameterSetName = "Simple")]
		[string]$Path,

		[Parameter(Mandatory, ParameterSetName = "Simple")]
		[string]$Target,

		[Parameter(Mandatory, ParameterSetName = "Nested")]
		[hashtable[]]$Links,

		[string]$ConfigurationFilePath
	)

	$configPath = if ($ConfigurationFilePath) { $ConfigurationFilePath } else { $script:ConfigurationPath }
	if (-not $configPath -or -not (Test-Path $configPath)) {
		Write-LogError "Error: Configuration file not found at '$configPath'!"
		return
	}

	$lines = @(Get-Content -Path $configPath)
	$section = Find-ConfigurationSection -Lines $lines -SectionName "SymbolicLinks"
	if (-not $section) {
		Write-LogError "Error: SymbolicLinks section not found in Configuration.psd1!"
		return
	}

	$t = "`t"
	$base = $section.Indent + $t
	$padded = $Name.PadRight(21)
	$entryLines = @()

	if ($PSCmdlet.ParameterSetName -eq "Simple") {
		$entryLines += "$base$padded= @{"
		$entryLines += "$base${t}Path   = `"$Path`""
		$entryLines += "$base${t}Target = `"$Target`""
		$entryLines += "$base}"
	}
	else {
		$entryLines += "$base$padded= @{"
		foreach ($link in $Links) {
			$linkPadded = $link.Name.PadRight(14)
			$entryLines += "$base$t$linkPadded= @{"
			$entryLines += "$base$t${t}Path   = `"$($link.Path)`""
			$entryLines += "$base$t${t}Target = `"$($link.Target)`""
			$entryLines += "$base$t}"
		}
		$entryLines += "$base}"
	}

	$newLines = [System.Collections.ArrayList]::new($lines)
	$insertIndex = $section.EndIndex
	for ($i = 0; $i -lt $entryLines.Count; $i++) {
		$newLines.Insert($insertIndex + $i, $entryLines[$i])
	}

	Set-Content -Path $configPath -Value $newLines
	Write-LogSuccess "Symbolic link '$Name' added to Configuration.psd1"

	if (Test-LogVerbose) {
		Write-LogDebug "[Add-SymbolicLink] Inserted at line $insertIndex"
		$entryLines | ForEach-Object { Write-LogDebug "  $_" }
	}
}
