function Install-ChocolateyApps {
	<#
	.SYNOPSIS
		Installs Chocolatey-managed apps from the WinuX CSV, filtered by machine type.

	.DESCRIPTION
		Reads the app list from the CSV file at `BootstrapConfig.DataFiles.ChocolateyApps`
		in Configuration.psd1. Each row specifies an app ID and the machine types it applies
		to ("All", "PC", "Laptop", etc.). Apps for the current machine type and All-type apps
		are installed; others are skipped.

		Requires administrator privileges. Called automatically by Bootstrap.

	.EXAMPLE
		Install-ChocolateyApps
		Installs all Chocolatey apps applicable to the current machine type.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Installing software with Chocolatey Package Manager"

	$MachineType = DetermineMachineType

	$csvPath = Join-Path -Path $MachineSpecificPaths.Projects.Self.Root -ChildPath $global:Configuration.BootstrapConfig.DataFiles.ChocolateyApps
	$chocoApps = Import-Csv $csvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#') }

	foreach ($app in $chocoApps) {
		if (-not (Test-MachineTypeScope -Scope "$($app.Machine)" -MachineType $MachineType -Context "ChocolateyApps.csv [$($app.App)]")) { continue }

		$appName = $app.App
		Write-LogTitle "$appName"

		$params = if ($app.Params) { "--params=`"$($app.Params)`"" } else { "" }
		$version = if ($app.Version) { "--version=$($app.Version)" } else { "" }
		$force = if ($app.Force -eq "true") { "--force" } else { "" }

		& choco install $appName $version $params $force -y | Out-Null
	}
}
