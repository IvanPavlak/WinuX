function Sync-AppPins {
	<#
	.SYNOPSIS
		Reconciles a package manager's own version pins with the effective app list, in both directions.

	.DESCRIPTION
		Makes the package manager's own pin state match the app list before an upgrade runs, so a bulk
		upgrade cannot move a version-locked app. All three managers are handled the same way, through
		each one's native pin mechanism:

		| Manager    | Pin                              | Unpin                        | Current state read       |
		| ---------- | -------------------------------- | ---------------------------- | ------------------------ |
		| WinGet     | `winget pin add --blocking`      | `winget pin remove`          | `winget pin list --id`   |
		| Scoop      | `scoop hold`                     | `scoop unhold`               | `scoop export` (Info)    |
		| Chocolatey | `choco pin add`                  | `choco pin remove`           | `choco pin list -r`      |

		Both halves of the lifecycle matter:

		- Every row carrying a real version is PINNED. This is the half that stops an upgrade from
		  walking straight past a deliberate version lock.
		- Every row back to "track the latest" that is still pinned from an earlier run has its pin
		  REMOVED. Without this half a pin outlives the decision behind it: unpinning an app in the CSV
		  leaves the manager's own pin in place and the app frozen forever, with nothing in WinuX left
		  to explain why it stopped updating. `Install-WinGetApps` already reconciles this way per app
		  at install time; this is the same reconciliation for the upgrade path.

		Recording the pin in the manager itself - rather than merely excluding the app from the list
		WinuX passes to the upgrade - is what makes the lock hold outside WinuX too: a hand-run
		`winget upgrade --all`, `scoop update *` or `choco upgrade all` respects it as well.

		Only apps WinuX manages are touched: the removal side considers exactly the apps in the
		effective list that are not pinned. A pin somebody added by hand for an app outside the list
		was not WinuX's to make and is not WinuX's to drop.

		The list is read through `Get-PinnedApps` / `Import-AppCsv`, so a version pinned in a
		machine-local `<name>.local.csv` overlay counts as a pin and an app the overlay removed is not
		treated as managed.

	.PARAMETER PackageManager
		Which manager's pins to reconcile: "WinGet", "Scoop" or "Chocolatey".

	.EXAMPLE
		Sync-AppPins -PackageManager WinGet
		Pins every version-locked WinGet app and clears pins for apps that are back to "Latest".

	.EXAMPLE
		Sync-AppPins -PackageManager Scoop
		The same through `scoop hold` / `scoop unhold`, so a later `scoop update *` skips the held apps.

	.NOTES
		Scoop can only hold an installed app, so a version-locked row that is not installed yet is
		reported and left for the installer - unlike WinGet and Chocolatey, whose pin commands are
		accepted ahead of installation.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[ValidateSet('WinGet', 'Scoop', 'Chocolatey')]
		[string]$PackageManager
	)

	$dataFileKey = @{ WinGet = 'WinGetApps'; Scoop = 'ScoopApps'; Chocolatey = 'ChocolateyApps' }[$PackageManager]

	# The Version value that means "not pinned", per manager: WinGet spells it "Latest", Scoop writes
	# it lower case, and Chocolatey leaves the cell empty - so for Chocolatey any version at all counts
	# as a pin.
	$versionExcludeValue = @{ WinGet = 'Latest'; Scoop = 'latest'; Chocolatey = $null }[$PackageManager]

	$pinnedApps = @(Get-PinnedApps -DataFileKey $dataFileKey -VersionExcludeValue $versionExcludeValue)

	# The apps WinuX manages but does not pin - the only ones whose leftover pin may be removed.
	$managedApps = @(Import-AppCsv -DataFileKey $dataFileKey | ForEach-Object { "$($_.App)".Trim() } | Where-Object { $_ })
	$unpinnedApps = @($managedApps | Where-Object { $_ -notin $pinnedApps })

	# Current pin state, read once per manager where the CLI can report it in bulk. WinGet has no
	# machine-readable bulk pin list, so it is queried per app in the removal loop instead.
	$pinnedNow = @()
	$scoopInstalled = @()
	$scoopIsGlobal = @{}

	switch ($PackageManager) {
		'Scoop' {
			# `scoop export` returns exactly what `scoop list` produces, whose Info column is a
			# comma-joined set of markers including 'Held package' and 'Global install'. That makes one
			# call enough to learn what is installed, what is held, and which scope each app lives in -
			# and the installed scope, not the CSV's Global column, is what hold/unhold must follow,
			# since an app may have been installed the other way by hand.
			try {
				$scoopApps = @((scoop export | ConvertFrom-Json).apps)
			}
			catch {
				Write-LogWarning "Could not read the installed Scoop apps - skipping Scoop pin reconciliation!"
				return
			}

			foreach ($scoopApp in $scoopApps) {
				$name = "$($scoopApp.Name)".Trim()
				if (-not $name) { continue }

				$scoopInstalled += $name
				$scoopIsGlobal[$name] = "$($scoopApp.Info)" -like '*Global install*'
				if ("$($scoopApp.Info)" -like '*Held package*') { $pinnedNow += $name }
			}
		}
		'Chocolatey' {
			# `choco pin list -r` reports every pin as "name|version" in one call.
			$pinnedNow = @(choco pin list -r 2>$null | ForEach-Object { ("$_" -split '\|')[0].Trim() } | Where-Object { $_ })
		}
	}

	foreach ($app in $unpinnedApps) {
		switch ($PackageManager) {
			'WinGet' {
				# Queried per app rather than parsed out of a bare `winget pin list` table, matching
				# what Install-WinGetApps does: the table's columns shift with terminal width and the
				# installed locale, and a mis-parse here would silently unpin the wrong app.
				$pinOutput = winget pin list --id $app --accept-source-agreements --disable-interactivity 2>$null
				if (-not ($pinOutput | Where-Object { $_ -match [regex]::Escape($app) })) { continue }

				Write-LogWarning "Removing stale pin for [$app] - it is no longer version-pinned"
				winget pin remove --id $app --disable-interactivity | Out-Null
			}
			'Scoop' {
				if ($app -notin $pinnedNow) { continue }

				Write-LogWarning "Removing stale hold for [$app] - it is no longer version-pinned"
				$scoopArgs = @('unhold')
				if ($scoopIsGlobal[$app]) { $scoopArgs += '-g' }
				scoop @scoopArgs $app | Out-Null
			}
			'Chocolatey' {
				if ($app -notin $pinnedNow) { continue }

				Write-LogWarning "Removing stale pin for [$app] - it is no longer version-pinned"
				choco pin remove --name=$app | Out-Null
			}
		}
	}

	if ($pinnedApps.Count -eq 0) { return }

	Show-PinnedAppsWarning -PinnedApps $pinnedApps -Message "Pinning version-specific packages to prevent upgrades"

	foreach ($app in $pinnedApps) {
		switch ($PackageManager) {
			'WinGet' {
				winget pin add --id $app --blocking --accept-source-agreements --disable-interactivity | Out-Null
			}
			'Scoop' {
				# Unlike a WinGet or Chocolatey pin, a hold only exists on an installed app.
				if ($app -notin $scoopInstalled) {
					Write-LogWarning "[$app] is version-pinned but not installed - Install-ScoopApps installs it at the pinned version"
					continue
				}

				$scoopArgs = @('hold')
				if ($scoopIsGlobal[$app]) { $scoopArgs += '-g' }
				scoop @scoopArgs $app | Out-Null
			}
			'Chocolatey' {
				choco pin add --name=$app | Out-Null
			}
		}
	}

	Write-Host ""
}
