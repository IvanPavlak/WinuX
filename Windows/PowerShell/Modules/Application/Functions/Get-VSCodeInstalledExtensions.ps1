function Get-VSCodeInstalledExtensions {
	<#
	.SYNOPSIS
		Lists the extensions a VS Code profile has installed, with their versions.

	.DESCRIPTION
		Runs `code --list-extensions --show-versions`, adding `--profile <ProfileName>` for any
		profile but Default (the Default profile is what the CLI addresses without the flag),
		and returns an ordered dictionary of extension id -> installed version. Ids are matched
		case-insensitively, as VS Code matches them.

		Returns $null when the command fails (a non-zero exit code - for instance a profile VS
		Code does not know, which the CLI reports as "Profile '<name>' not found"), so a caller
		can tell "nothing installed" (an empty dictionary) from "could not ask".

	.PARAMETER Command
		The VS Code command line to run (Get-VSCodeCliPath); tests pass a stub script.

	.PARAMETER ProfileName
		The VS Code profile name. Default addresses the Default profile.

	.EXAMPLE
		(Get-VSCodeInstalledExtensions -Command (Get-VSCodeCliPath) -ProfileName Default).Keys
		Returns the extension ids installed in the Default profile.
	#>
	[CmdletBinding()]
	[OutputType([System.Collections.Specialized.OrderedDictionary])]
	param(
		[Parameter(Mandatory)]
		[string]$Command,

		[Parameter(Mandatory)]
		[string]$ProfileName
	)

	$arguments = @("--list-extensions", "--show-versions")
	if ($ProfileName -ne 'Default') {
		$arguments += @("--profile", $ProfileName)
	}

	try {
		$global:LASTEXITCODE = 0
		$listing = @(& $Command @arguments 2>$null)
	}
	catch {
		Write-LogDebug "code --list-extensions threw => $($_.Exception.Message)"
		return $null
	}
	if ($LASTEXITCODE -ne 0) {
		Write-LogDebug "code --list-extensions exited with $LASTEXITCODE for profile [$ProfileName]"
		return $null
	}

	$installed = [ordered]@{}
	foreach ($line in $listing) {
		$text = ([string]$line).Trim()
		if (-not $text) { continue }
		$parts = $text -split '@', 2
		$installed[$parts[0]] = if ($parts.Count -gt 1) { $parts[1] } else { "" }
	}

	return $installed
}
