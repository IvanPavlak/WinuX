function Upgrade-All {
	<#
	.SYNOPSIS
		Upgrades all packages across WinGet, Scoop, and/or Chocolatey.

	.DESCRIPTION
		Upgrades packages in the specified package managers. Reads pinned (version-locked) apps
		from the configured CSV files and prevents them from being upgraded.

		Without `-PackageManager`, upgrades across all managers configured in `PackageManagers` in Configuration.psd1.
		With `-PackageManager`, upgrades only the specified manager.

		Requires administrator privileges.

	.PARAMETER PackageManager
		Package manager(s) to upgrade: "WinGet", "Scoop", or "Chocolatey".
		Omit to upgrade all configured managers.

	.EXAMPLE
		Upgrade-All
		Upgrades all packages across all configured managers.

	.EXAMPLE
		Upgrade-All -PackageManager "WinGet"
		Upgrades only WinGet packages.
	#>
	param (
		[Parameter(Mandatory = $false)]
		[ValidateSet("WinGet", "Scoop", "Chocolatey")]
		[string]$PackageManager
	)

	Test-AdminPrivileges

	$PackageManagers = if ($PackageManager) { @($PackageManager) } else { $global:Configuration.PackageManagers }

	foreach ($PackageManager in $PackageManagers) {
		Write-LogTitle "Upgrading all $PackageManager Software"

		try {
			switch ($PackageManager) {
				"WinGet" {
					$pinnedApps = Get-PinnedApps -CsvFileName $global:Configuration.BootstrapConfig.DataFiles.WinGetApps

					if ($pinnedApps.Count -gt 0) {
						Show-PinnedAppsWarning -PinnedApps $pinnedApps -Message "Pinning version-specific packages to prevent upgrades"

						foreach ($app in $pinnedApps) {
							winget pin add --id $app --blocking --accept-source-agreements --disable-interactivity | Out-Null
						}
						Write-Host ""
					}

					winget upgrade --all --silent --include-unknown --accept-source-agreements --accept-package-agreements --disable-interactivity
					$exitCode = $LASTEXITCODE
				}
				"Scoop" {
					$pinnedApps = Get-PinnedApps -CsvFileName $global:Configuration.BootstrapConfig.DataFiles.ScoopApps -VersionExcludeValue "latest"

					if ($pinnedApps.Count -gt 0) {
						Show-PinnedAppsWarning -PinnedApps $pinnedApps -Message "Pinning version-specific packages to prevent upgrades"

						try {
							$scoopExport = scoop export | ConvertFrom-Json
							$installedApps = $scoopExport.apps | ForEach-Object { $_.Name }
						}
						catch {
							Write-LogWarning "Could not get list of installed apps!"
							$installedApps = @()
						}

						$appsToUpdate = $installedApps | Where-Object { $_ -notin $pinnedApps }

						if ($appsToUpdate.Count -gt 0) {
							scoop update $appsToUpdate
						}
						else {
							Write-LogStep "All apps are version-pinned! Nothing to update!"
						}
					}
					else {
						scoop update *
					}
					$exitCode = $LASTEXITCODE
				}
				"Chocolatey" {
					$pinnedApps = Get-PinnedApps -CsvFileName $global:Configuration.BootstrapConfig.DataFiles.ChocolateyApps -VersionExcludeValue $null

					if ($pinnedApps.Count -gt 0) {
						Show-PinnedAppsWarning -PinnedApps $pinnedApps -Message "Pinning version-specific packages to prevent upgrades"

						foreach ($app in $pinnedApps) {
							choco pin add --name=$app | Out-Null
						}
					}

					choco upgrade all -y
					$exitCode = $LASTEXITCODE
				}
			}

			if ($exitCode -eq 0) {
				Write-LogSuccess "Upgrading all $PackageManager Software completed"
			}
			else {
				Write-LogError "Upgrading all $PackageManager Software failed with exit code [$exitCode]"
			}
		}
		catch {
			Write-LogError "An error occurred during the upgrade process: $_"
		}
	}
}
