function Install-WinGetApps {
	<#
	.SYNOPSIS
		Installs WinGet-managed apps from the WinuX CSV, filtered by machine type.

	.DESCRIPTION
		Reads the app list from the CSV file at `BootstrapConfig.DataFiles.WinGetApps` in
		Configuration.psd1. Each row specifies an app ID, installation scope (machine/user/default),
		and the machine types it applies to. Apps for the current machine type and All-type apps
		are installed; others are skipped.

		Requires administrator privileges. Called automatically by Bootstrap.

	.EXAMPLE
		Install-WinGetApps
		Installs all WinGet apps applicable to the current machine type.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Installing software with WinGet"

	$MachineType = DetermineMachineType

	$csvPath = Join-Path -Path $MachineSpecificPaths.Projects.Self.Root -ChildPath $global:Configuration.BootstrapConfig.DataFiles.WinGetApps
	$wingetApps = Import-Csv $csvPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_.App) -and -not $_.App.TrimStart().StartsWith('#') }

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
		winget search "winux-source-agreement-prime" --source $wingetSource --accept-source-agreements --disable-interactivity *> $null
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

		if (-not $app.Version -or $app.Version -eq "Latest") {
			$pinOutput = winget pin list --id $appName --accept-source-agreements --disable-interactivity 2>$null
			if ($pinOutput | Where-Object { $_ -match [regex]::Escape($appName) }) {
				Write-LogWarning "Removing existing pin for $appName..."
				winget pin remove --id $appName --disable-interactivity
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
			winget list --id $appName -e --accept-source-agreements --disable-interactivity *> $null
			if ($LASTEXITCODE -ne 0) {
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
