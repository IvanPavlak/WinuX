function Upgrade-All {
	<#
	.SYNOPSIS
		Upgrades all packages across the package managers WinuX actually uses.

	.DESCRIPTION
		Upgrades packages in the package managers that are in play on this machine, resolved by
		`Resolve-PackageManagers`: listed in `PackageManagers` in Configuration.psd1 AND holding at
		least one app for this machine type. A manager WinuX has no apps for is not upgraded, the
		same way it is not installed - running its CLI anyway would only produce a failure for a
		manager the machine deliberately does not have.

		Version-pinned apps are never upgraded. Every manager is handled identically: `Sync-AppPins`
		reconciles that manager's own pin mechanism with the app list first - `winget pin`, `scoop hold`
		or `choco pin`, pinning version-locked apps and clearing pins for apps back to tracking the
		latest - and the manager then skips what it has pinned during its bulk upgrade. Pins honour the
		machine-local `<name>.local.csv` overlay, since the lists are read through `Import-AppCsv`.

		With `-PackageManager`, upgrades exactly the named manager(s) and skips resolution from
		configuration - an explicit request is honoured as given.

		Requires administrator privileges.

	.PARAMETER PackageManager
		Package manager(s) to upgrade: "WinGet", "Scoop", or "Chocolatey". Omit to upgrade every
		manager in play for this machine.

	.EXAMPLE
		Upgrade-All
		Upgrades every package manager in play on this machine.

	.EXAMPLE
		Upgrade-All -PackageManager "WinGet"
		Upgrades only WinGet packages.

	.EXAMPLE
		Upgrade-All -PackageManager "WinGet", "Scoop"
		Upgrades WinGet and Scoop, leaving Chocolatey alone.
	#>
	param (
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet("WinGet", "Scoop", "Chocolatey")]
		[string[]]$PackageManager
	)

	Test-AdminPrivileges

	# Splatted rather than passed straight through: -PackageManager carries a ValidateSet, which
	# rejects the null this parameter holds when the caller omitted it.
	$resolveParams = @{}
	if ($PackageManager) { $resolveParams.PackageManager = $PackageManager }

	$managers = @(Resolve-PackageManagers @resolveParams)

	if ($managers.Count -eq 0) {
		Write-LogWarning "No package managers to upgrade"
		return
	}

	# The CLI each manager is driven through, used to confirm it is actually present before its
	# branch runs.
	$commands = @{ WinGet = "winget"; Scoop = "scoop"; Chocolatey = "choco" }

	foreach ($manager in $managers) {
		if (-not (Get-Command $commands[$manager] -ErrorAction SilentlyContinue)) {
			Write-LogWarning "[$manager] is not installed on this machine - skipping its upgrade"
			continue
		}

		Write-LogTitle "Upgrading all $manager Software"

		# Reset per manager so a branch whose CLI never sets one cannot inherit the previous manager's
		# exit code and report a failure that never happened.
		$exitCode = 0

		try {
			# Every manager follows the same two steps: reconcile its own pins with the app list, then
			# run its bulk upgrade. The manager itself skips what it has pinned, so the pin holds for a
			# hand-run upgrade too - not just for this function.
			Sync-AppPins -PackageManager $manager

			switch ($manager) {
				"WinGet" {
					winget upgrade --all --silent --include-unknown --accept-source-agreements --accept-package-agreements --disable-interactivity
					$exitCode = $LASTEXITCODE
				}
				"Scoop" {
					scoop update *
					$exitCode = $LASTEXITCODE
				}
				"Chocolatey" {
					choco upgrade all -y
					$exitCode = $LASTEXITCODE
				}
			}

			if ($exitCode -eq 0) {
				Write-LogSuccess "Upgrading all $manager Software completed"
			}
			else {
				Write-LogError "Upgrading all $manager Software failed with exit code [$exitCode]"
			}
		}
		catch {
			Write-LogError "An error occurred during the upgrade process: $_"
		}
	}
}
