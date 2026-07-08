function Configure-NuGetConfig {
	<#
    .SYNOPSIS
        Configures NuGet package source settings.

    .DESCRIPTION
        Copies a NuGet.config file from the WinuX repository to the user's AppData NuGet
        folder. The source and destination paths are read from `MachineSpecificPaths.NuGetConfig`.
        Skips the copy if the destination already exists unless `-Override` is set.

    .PARAMETER Override
        Force reconfiguration of NuGet settings even if already configured.

    .EXAMPLE
        Configure-NuGetConfig
        Configures NuGet settings if not already done.

    .EXAMPLE
        Configure-NuGetConfig -Override
        Reconfigures NuGet settings.
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Override
	)

	Write-LogTitle "NuGet Config Setup"

	$sourceConfigPath = $MachineSpecificPaths.NuGetConfig.SourcePath
	$destinationPath = $MachineSpecificPaths.NuGetConfig.DestinationPath

	$needsReconfiguration = $false

	if ((Test-Path $destinationPath) -and -not $Override) {
		Write-LogWarning "NuGet config already exists at => [$destinationPath]"

		if (Test-Path $sourceConfigPath) {
			try {
				[xml]$sourceXml = Get-Content $sourceConfigPath
				[xml]$destXml = Get-Content $destinationPath

				$sourceSources = $sourceXml.configuration.packageSources.add
				$destSources = $destXml.configuration.packageSources.add

				$mismatch = $false

				foreach ($source in $sourceSources) {
					$matchingDest = $destSources | Where-Object { $_.key -eq $source.key }

					if (-not $matchingDest) {
						Write-LogError "Package source [$($source.key)] is missing in the existing config!"
						$mismatch = $true
					}
					elseif ($matchingDest.value -ne $source.value) {
						Write-LogError "Package source [$($source.key)] has different URL:"
						Write-LogError "   Repository => [$($source.value)]"
						Write-LogError "   Actual => [$($matchingDest.value)]"
						$mismatch = $true
					}
				}

				foreach ($dest in $destSources) {
					$matchingSource = $sourceSources | Where-Object { $_.key -eq $dest.key }

					if (-not $matchingSource) {
						Write-LogWarning "Package source [$($dest.key)] exists in actual config but not in repository!"
						$mismatch = $true
					}
				}

				if ($mismatch) {
					Write-LogWarning "Package sources differ between repository and actual config!"
					Write-LogWarning "Proceeding to reconfigure with correct settings..."
					$needsReconfiguration = $true
				}
				else {
					Write-LogSuccess "NuGet config is already correctly configured (package sources match)"
					return
				}
			}
			catch {
				Write-LogWarning "Could not validate config contents => $($_.Exception.Message)"
				Write-LogWarning "Proceeding to reconfigure..."
				$needsReconfiguration = $true
			}
		}
		else {
			Write-LogWarning "Use [-Override] flag to overwrite existing configuration!"
			return
		}
	}

	if ($needsReconfiguration -or $Override) {
		if (Test-Path $destinationPath) {
			Write-LogStep "=> Overriding existing NuGet config at => [$destinationPath]"
		}
	}

	if (-not (Test-Path $sourceConfigPath)) {
		Write-LogError "Source nuget.config not found at => [$sourceConfigPath]"
		return
	}

	$username = ""
	while ([string]::IsNullOrWhiteSpace($username)) {
		$username = Custom-ReadHost "`nEnter GitHub username: " -AddNewLine:$false
		if ([string]::IsNullOrWhiteSpace($username)) {
			Write-LogError "Username cannot be empty! Try again!"
		}
	}

	$token = ""
	while ([string]::IsNullOrWhiteSpace($token)) {
		$secureToken = Custom-ReadHost "`nEnter GitHub Personal Access Token (PAT): " -AsSecureString -AddNewLine:$false

		$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
		try {
			$token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)

			if ([string]::IsNullOrWhiteSpace($token)) {
				Write-LogError "Token cannot be empty! Try again!"
			}
		}
		finally {
			[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
		}
	}

	$configContent = Get-Content $sourceConfigPath -Raw

	$configContent = $configContent -replace '\[Username\]', $username
	$configContent = $configContent -replace '\[Token\]', $token

	$destinationDir = Split-Path $destinationPath -Parent
	if (-not (Test-Path $destinationDir)) {
		New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
	}

	$configContent | Set-Content -Path $destinationPath -Encoding UTF8

	Write-LogSuccess "NuGet config successfully created at => [$destinationPath]"
}
