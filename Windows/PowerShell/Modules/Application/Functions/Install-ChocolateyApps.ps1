function Install-ChocolateyApps {
	<#
	.SYNOPSIS
		Installs Chocolatey-managed apps from the WinuX CSV, filtered by machine type.

	.DESCRIPTION
		Reads the app list through `Import-AppCsv`, which parses the committed CSV named by
		`BootstrapConfig.DataFiles.ChocolateyApps` in Configuration.psd1 and layers the machine-local
		`ChocolateyApps.local.csv` over it. Each row specifies an app ID and the machine types it
		applies to ("All", "PC", "Laptop", etc.). Apps for the current machine type and All-type
		apps are installed; others are skipped.

		Requires administrator privileges. Called automatically by Bootstrap.

	.EXAMPLE
		Install-ChocolateyApps
		Installs all Chocolatey apps applicable to the current machine type.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Installing software with Chocolatey Package Manager"

	$MachineType = DetermineMachineType

	# Import-AppCsv layers the machine-local ChocolateyApps.local.csv over the committed list, so a
	# fork's own app choices apply without the tracked CSV ever being edited.
	$chocoApps = @(Import-AppCsv -DataFileKey ChocolateyApps)
	$failedApps = @()

	foreach ($app in $chocoApps) {
		if (-not (Test-MachineTypeScope -Scope "$($app.Machine)" -MachineType $MachineType -Context "ChocolateyApps.csv [$($app.App)]")) { continue }

		$appName = $app.App
		Write-LogTitle "$appName"

		# Build the argument list without empty strings, and treat "Latest" (any case) as no pin:
		# choco rejects --version=latest outright ("'latest' is not a valid version string").
		$chocoArgs = @("install", $appName, "-y")
		if ($app.Version -and $app.Version -ne "Latest") { $chocoArgs += "--version=$($app.Version)" }
		if ($app.Params) { $chocoArgs += "--params=`"$($app.Params)`"" }
		if ($app.Force -eq "true") { $chocoArgs += "--force" }

		& choco @chocoArgs | Out-Null
		$installExitCode = $LASTEXITCODE

		# 1641 and 3010 are choco's "succeeded, reboot required" codes.
		if ($installExitCode -notin 0, 1641, 3010) {
			Write-LogError "Install FAILED for [$appName] (choco exit code => $installExitCode)"
			$failedApps += [PSCustomObject]@{ App = $appName; ExitCode = $installExitCode }
		}
	}

	if ($failedApps.Count -gt 0) {
		Write-LogError "Chocolatey finished with [$($failedApps.Count)] failed install(s):"
		foreach ($failure in $failedApps) {
			Write-LogError "   $($failure.App) (exit code $($failure.ExitCode))" -NoLeadingNewline
		}
		Write-LogWarning "Re-run [Install-ChocolateyApps], or install manually => choco install <AppId> -y"
	}
	else {
		Write-LogSuccess "All Chocolatey apps for [$MachineType] installed successfully!"
	}
}
