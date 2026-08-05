function Resolve-PackageManagers {
	<#
	.SYNOPSIS
		Returns the package managers actually in play on this machine, in canonical order.

	.DESCRIPTION
		The single gate deciding which of WinGet, Scoop and Chocolatey WinuX installs and upgrades.
		A manager is in play when BOTH of these hold:

		- It is listed in `PackageManagers` in Configuration.psd1. That list is the opt-in: a manager
		  absent from it is never installed and never upgraded.
		- Its effective app list holds at least one row applicable to this machine type. The list is
		  read through `Import-AppCsv`, so the machine-local `<name>.local.csv` overlay counts, and
		  each row's `Machine` column is checked with `Test-MachineTypeScope`, so a manager whose
		  only apps target other machines counts as empty here.

		The second condition is what keeps a package manager off a machine that has no use for it.
		Installing one is not free - it is a download, a PATH entry and a shim directory that then
		sit there managing nothing - and the base WinuX Scoop and Chocolatey lists ship empty, so a
		vanilla bootstrap used to install two managers for zero apps. Deriving it from the data
		rather than from the list alone also means the two cannot drift: a fork that empties its
		Scoop overlay stops installing Scoop without having to remember to also edit
		`PackageManagers`.

		Names are matched case-insensitively and returned in canonical spelling and canonical order
		(WinGet, Scoop, Chocolatey - the order Bootstrap installs them in), so callers can switch on
		the returned strings directly. Unknown entries are reported through `Write-LogError` with the
		valid values, the same way `Test-MachineTypeScope` reports a misspelled machine scope, so a
		typo like "Chocolatley" is surfaced instead of silently dropping a manager.

	.PARAMETER PackageManager
		Explicit manager(s) to use instead of resolving from configuration. An explicit request is
		honoured as given - neither the opt-in list nor the empty-list check second-guesses a caller
		who named the managers - and is returned in canonical order. This is what backs
		`Upgrade-All -PackageManager`.

	.PARAMETER MachineType
		Machine type the app lists are filtered against. Defaults to $global:MachineType.

	.EXAMPLE
		Resolve-PackageManagers
		Returns e.g. @("WinGet") on the base configuration, whose Scoop and Chocolatey lists are empty.

	.EXAMPLE
		Resolve-PackageManagers -PackageManager "Chocolatey"
		Returns @("Chocolatey") regardless of configuration - an explicit request is honoured.

	.NOTES
		Rows with an invalid `Machine` token are reported here and again by the installer that reads
		the same list later in Bootstrap. The duplicate line is deliberate: the alternative is a
		second, non-validating scope matcher, and one gate for machine scope is exactly what
		`Test-MachineTypeScope` exists to be.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter(Mandatory = $false, Position = 0)]
		[ValidateSet('WinGet', 'Scoop', 'Chocolatey')]
		[string[]]$PackageManager,

		[Parameter(Mandatory = $false)]
		[string]$MachineType = $global:MachineType
	)

	# Canonical spelling, in Bootstrap's install order, each mapped to the DataFiles key its app
	# list is resolved through.
	$canonical = [ordered]@{
		WinGet     = 'WinGetApps'
		Scoop      = 'ScoopApps'
		Chocolatey = 'ChocolateyApps'
	}

	if ($PackageManager) {
		return [string[]]@($canonical.Keys | Where-Object { $_ -in $PackageManager })
	}

	$configured = @($global:Configuration.PackageManagers |
		Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
		ForEach-Object { "$_".Trim() })

	if ($configured.Count -eq 0) {
		Write-LogWarning "No package managers configured (PackageManagers in Configuration.psd1) - no package manager will be installed or upgraded"
		return [string[]]@()
	}

	foreach ($name in $configured) {
		if ($name -notin @($canonical.Keys)) {
			Write-LogError "Unknown package manager [$name] in PackageManagers - valid values: $(@($canonical.Keys) -join ', ')"
		}
	}

	$inPlay = foreach ($name in $canonical.Keys) {
		if ($name -notin $configured) { continue }

		$dataFileKey = $canonical[$name]

		$apps = @(Import-AppCsv -DataFileKey $dataFileKey | Where-Object {
				Test-MachineTypeScope -Scope "$($_.Machine)" -MachineType $MachineType -Context "$dataFileKey [$($_.App)]"
			})

		if ($apps.Count -eq 0) {
			Write-LogWarning "[$name] is configured but its app list has no entries for machine type [$MachineType] - not installing or upgrading it"
			continue
		}

		$name
	}

	$resolved = [string[]]@($inPlay)

	Write-LogDebug "Package managers in play for [$MachineType]: $(if ($resolved.Count) { $resolved -join ', ' } else { '<none>' })"

	return $resolved
}
