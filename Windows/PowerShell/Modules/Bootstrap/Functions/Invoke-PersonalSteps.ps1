function Invoke-PersonalSteps {
	<#
	.SYNOPSIS
		Runs the fork-defined personal install steps from BootstrapConfig.PersonalSteps, machine-gated.

	.DESCRIPTION
		Executes the optional, fork-defined bootstrap steps listed in BootstrapConfig.PersonalSteps
		(set in Configuration.local.psd1). When nothing applies - the list is empty (the base
		configuration ships it empty) or every entry is gated to other machine types - it reports
		so with a warning naming the current machine type. Called automatically by Bootstrap right
		after Upgrade-All.

		Each entry is either a plain function name (runs on every machine type) or a hashtable
		@{ Function = "Name"; Machine = "PC/Laptop" } gated per machine type exactly like the app
		CSVs' Machine column - scope tokens are validated by Test-MachineTypeScope, so unknown
		machine types are reported instead of silently never matching.

		Entries without a Function name and entries that do not resolve to an exported command are
		skipped with a warning. Entries whose machine scope does not cover the current machine type
		are skipped silently (a debug line records the skip).

		Requires administrator privileges - personal steps install software. The check runs up
		front via Test-AdminPrivileges, so a non-elevated invocation fails fast (offering the
		elevated rerun) instead of aborting mid-run inside a step.

	.EXAMPLE
		Invoke-PersonalSteps
		Runs every configured personal step applicable to the current machine type.
	#>
	[CmdletBinding()]
	param()

	Test-AdminPrivileges

	Write-LogTitle "Invoking Personal Steps"

	$personalSteps = @($global:Configuration.BootstrapConfig.PersonalSteps | Where-Object { $_ })

	# Set once any entry's machine scope covers this machine (resolvable or not). When nothing
	# applies - empty list, or every entry gated to other machine types - say so, instead of
	# ending silently under the title (out-of-scope skips only log at debug level).
	$anyStepInScope = $false

	foreach ($personalStep in $personalSteps) {
		$stepName = if ($personalStep -is [System.Collections.IDictionary]) { "$($personalStep['Function'])" } else { "$personalStep" }
		$stepScope = if ($personalStep -is [System.Collections.IDictionary] -and $null -ne $personalStep['Machine']) { "$($personalStep['Machine'])" } else { "All" }

		if (-not $stepName) {
			Write-LogWarning "Personal step entry has no Function name - skipping"
			continue
		}

		if (-not (Test-MachineTypeScope -Scope $stepScope -Context "PersonalSteps [$stepName]")) {
			Write-LogDebug "Personal step [$stepName] skipped (machine scope => [$stepScope])"
			continue
		}

		$anyStepInScope = $true

		if (Get-Command $stepName -ErrorAction SilentlyContinue) {
			& $stepName
		}
		else {
			Write-LogWarning "Personal step [$stepName] not found - skipping"
		}
	}

	if (-not $anyStepInScope) {
		Write-LogWarning "No personal steps configured for this [$global:MachineType] machine!"
	}
}
