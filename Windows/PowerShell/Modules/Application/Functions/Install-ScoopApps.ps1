function Install-ScoopApps {
	<#
	.SYNOPSIS
		Installs Scoop-managed apps from the WinuX CSV, filtered by machine type.

	.DESCRIPTION
		Reads the app list through `Import-AppCsv`, which parses the committed CSV named by
		`BootstrapConfig.DataFiles.ScoopApps` in Configuration.psd1 and layers the machine-local
		`ScoopApps.local.csv` over it. Each row specifies an app name, optional bucket, and the
		machine types it applies to. Apps for the current machine type and All-type apps are
		installed; others are skipped.

		Requires administrator privileges. Called automatically by Bootstrap.

	.EXAMPLE
		Install-ScoopApps
		Installs all Scoop apps applicable to the current machine type.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Installing software with Scoop Package Manager"

	$MachineType = DetermineMachineType

	# Import-AppCsv layers the machine-local ScoopApps.local.csv over the committed list, so a fork's
	# own app choices apply without the tracked CSV ever being edited.
	$scoopApps = @(Import-AppCsv -DataFileKey ScoopApps)

	$installedApps = @()
	try {
		$scoopExport = scoop export | ConvertFrom-Json
		$installedApps = $scoopExport.apps | ForEach-Object { $_.Name }
	}
 catch {
		Write-LogWarning "Could not get list of installed apps!"
	}

	foreach ($app in $scoopApps) {
		if (-not (Test-MachineTypeScope -Scope "$($app.Machine)" -MachineType $MachineType -Context "ScoopApps.csv [$($app.App)]")) { continue }

		$global = if ($app.Global -eq "true") { "--global" } else { "" }
		$version = if ($app.Version -and $app.Version -ne "latest") { "@$($app.Version)" } else { "" }

		$appName = $app.App
		$isInstalled = $installedApps -contains $appName

		Write-LogTitle "$appName$(if ($app.Version -ne "latest"){" ($($app.Version))"})"

		if ($isInstalled) {
			if ($app.Version -and $app.Version -ne "latest") {
				Write-LogWarning "Already installed with pinned version - skipping"
			}
			else {
				Invoke-Expression "scoop update $appName $global"
			}
		}
		else {
			Invoke-Expression "scoop install $appName$version $global"
		}
	}
}
