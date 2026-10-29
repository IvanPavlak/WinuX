function Install-WinGetApps {
	<#
	.SYNOPSIS
		Installs WinGet-managed apps from the WinuX CSV, filtered by machine type.

	.DESCRIPTION
		Reads the app list through `Import-AppCsv`, which parses the committed CSV named by
		`BootstrapConfig.DataFiles.WinGetApps` in Configuration.psd1 and layers the machine-local
		`WinGetApps.local.csv` over it. Each row specifies an app ID, installation scope
		(machine/user/default), and the machine types it applies to. Apps for the current machine
		type and All-type apps are installed; others are skipped.

		The short winget calls around the installs - priming the source agreements, reading and
		removing pins, the presence check after a failed install - go through
		`Invoke-PackageManagerCommand`, so a stalled winget is stopped after 60 seconds instead of
		holding up Bootstrap. The installs themselves run without a limit: a large install
		legitimately takes many minutes.

		Requires administrator privileges. Called automatically by Bootstrap.

	.EXAMPLE
		Install-WinGetApps
		Installs all WinGet apps applicable to the current machine type.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Installing software with WinGet"

	$MachineType = DetermineMachineType

	# Import-AppCsv layers the machine-local WinGetApps.local.csv over the committed list, so a fork's
	# own app choices apply without the tracked CSV ever being edited.
	$wingetApps = @(Import-AppCsv -DataFileKey WinGetApps)

	# Accept every WinGet source agreement up front, non-interactively, so no per-app call can block
	# on WinGet's first-run prompt. The `msstore` source shows a hard, one-time agreement (including a
	# geographic-region consent) the FIRST time that source is QUERIED - and only --accept-source-agreements
	# clears it (--disable-interactivity does NOT suppress this legal gate). A bare `winget list` does
	# not engage msstore on a fresh machine, so its agreement stays unaccepted and the first msstore
	# query hangs waiting for input. Querying each source directly forces the agreement to surface, and
	# --accept-source-agreements records the acceptance for every later install. The search token is a
	# no-op (matches nothing); acceptance happens before the query runs, so only the side effect matters.
	# Requires WinGet 1.6+ for --disable-interactivity, which ships with Windows 11.
	foreach ($wingetSource in @("winget", "msstore")) {
		try {
			Invoke-PackageManagerCommand -PackageManager WinGet -Arguments 'search', 'winux-source-agreement-prime', '--source', $wingetSource, '--accept-source-agreements', '--disable-interactivity' | Out-Null
		}
		catch {
			Write-LogWarning "Could not prime the [$wingetSource] source agreement => $_"
		}
	}

	# Every pin on an app back to "Latest" is read in one call, before the loop: a leftover pin from
	# an earlier version lock would block the install from moving the app. A listing that stalls
	# leaves the pins in place - the install then reports the blocked app - rather than stopping
	# every install.
	$latestApps = @($wingetApps | Where-Object { -not $_.Version -or $_.Version -eq "Latest" } | ForEach-Object { "$($_.App)".Trim() } | Where-Object { $_ })
	$pinnedLatestApps = @()
	try {
		$pinnedLatestApps = @(Get-WinGetPinnedIds -AppId $latestApps)
	}
	catch {
		Write-LogWarning "Could not read the WinGet pins - leaving them as they are => $_"
	}

	# A failed install must never scroll by invisibly inside the wall of bootstrap output -
	# a missing app then surfaces much later as a confusing runtime failure (e.g. the profile
	# reporting oh-my-posh absent). Collect failures and print a summary at the end.
	$failedApps = @()

	foreach ($app in $wingetApps) {
		if (-not (Test-MachineTypeScope -Scope "$($app.Machine)" -MachineType $MachineType -Context "WinGetApps.csv [$($app.App)]")) { continue }

		$scope = switch ($app.Scope) {
			"d" { "" }
			"m" { '--scope "machine"' }
			"u" { '--scope "user"' }
		}

		$version = if ($app.Version -and $app.Version -ne "Latest") { "--version $($app.Version)" } else { "" }

		$interactive = switch ($app.Interactive) {
			"n" { "" }
			"y" { "-i" }
		}

		$source = switch ($app.Source) {
			"s" { "-s msstore" }
			"w" { "-s winget" }
		}

		$appName = $app.App

		if ($appName -in $pinnedLatestApps) {
			Write-LogWarning "Removing existing pin for $appName..."
			try {
				Invoke-PackageManagerCommand -PackageManager WinGet -Arguments 'pin', 'remove', '--id', $appName, '--accept-source-agreements', '--disable-interactivity' | Out-Null
			}
			catch {
				Write-LogWarning "Could not remove the pin for [$appName] => $_"
			}
		}

		# --disable-interactivity keeps every install fully unattended, but it is mutually exclusive
		# with winget's -i (interactive) flag, so only add it when the app opted out of interactive.
		$nonInteractive = if ($interactive) { "" } else { "--disable-interactivity" }

		Write-LogTitle "$appName$(if ($app.Version -ne "Latest"){" ($($app.Version))"})"
		Invoke-Expression "winget install `"$appName`" $version $scope $interactive $source --accept-package-agreements --accept-source-agreements $nonInteractive"
		$installExitCode = $LASTEXITCODE

		if ($installExitCode -ne 0) {
			# winget's nonzero exit codes are not uniformly failures (e.g. "already installed" /
			# "no applicable update" variants), so check ground truth: is the package registered?
			$isInstalled = $false
			try {
				Invoke-PackageManagerCommand -PackageManager WinGet -Arguments 'list', '--id', $appName, '-e', '--accept-source-agreements', '--disable-interactivity' | Out-Null
				$isInstalled = $LASTEXITCODE -eq 0
			}
			catch {
				Write-LogWarning "Could not check whether [$appName] is installed => $_"
			}

			if (-not $isInstalled) {
				Write-LogError "Install FAILED for [$appName] (winget exit code => $installExitCode)"
				$failedApps += [PSCustomObject]@{ App = $appName; ExitCode = $installExitCode }
			}
			else {
				Write-LogWarning "[$appName] returned exit code $installExitCode but is installed (already present / no applicable update)"
			}
		}
	}

	if ($failedApps.Count -gt 0) {
		Write-LogError "WinGet finished with [$($failedApps.Count)] failed install(s):"
		foreach ($failure in $failedApps) {
			Write-LogError "   $($failure.App) (exit code $($failure.ExitCode))" -NoLeadingNewline
		}
		Write-LogWarning "Re-run [Install-WinGetApps] after Bootstrap completes, or install manually => winget install <AppId> -s winget"
	}
	else {
		Write-LogSuccess "All WinGet apps for [$MachineType] installed successfully!"
	}
}
