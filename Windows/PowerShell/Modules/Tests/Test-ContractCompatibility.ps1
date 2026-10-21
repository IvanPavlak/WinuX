function Test-ContractCompatibility {
	<#
	.SYNOPSIS
		Lists every way the working tree's contract breaks the one recorded at the last release,
		unless the break is a sanctioned removal.

	.DESCRIPTION
		Compares a current snapshot (Get-ContractSnapshot) with the committed baseline taken at the
		last release, and returns one violation string per break:

		- an exported function that is no longer exported (as a function or an exported alias);
		- a parameter of a still-exported function that is gone (by name and by [Alias()]);
		- a parameter that is mandatory now but was optional or absent in the baseline;
		- a key of the shipped Configuration.psd1 (two levels deep) that is gone.

		Additions are never violations. A break is sanctioned, and not reported, in three cases, all
		read from the changelog's [Unreleased] section. The first two are what make the next release
		a MAJOR:

		- Removal of a deprecated item: the item is listed in the baseline's Deprecated map with a
		  version no later than the baseline's own (so the deprecation has shipped in a release),
		  and [Unreleased] has a "### Removed" subsection naming it in backticks.
		- An immediate break: [Unreleased] has a "### Breaking" subsection naming it in backticks.
		- A withdrawn item: [Unreleased] has a "### Withdrawn" subsection naming it in backticks.
		  Withdrawn is for an item that was never meant to be shared engine code (a fork's personal
		  function or key that shipped by mistake); it needs no deprecation and makes the release at
		  least a MINOR (Test-ChangelogVersionBumps), not a MAJOR.

		Items are named `FunctionName` for a function, `FunctionName -Parameter` for a parameter and
		`Top.Child` for a configuration key.

	.PARAMETER Baseline
		The baseline: Version, Functions, Aliases, ConfigurationKeys and Deprecated (Functions,
		Parameters and ConfigurationKeys maps of item to the version that deprecated it), as read
		from ContractBaseline.json.

	.PARAMETER Current
		The working tree's snapshot.

	.PARAMETER Unreleased
		The changelog's [Unreleased] subsections (Get-ChangelogReleases).

	.OUTPUTS
		[string[]] - the violations; empty when the contract holds.
	#>
	[CmdletBinding()]
	[OutputType([string[]])]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Baseline,

		[Parameter(Mandatory = $true)]
		[System.Collections.IDictionary]$Current,

		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[hashtable]$Unreleased
	)

	$violations = [System.Collections.Generic.List[string]]::new()
	$baselineVersion = [version](($Baseline.Version -replace '-.*$', ''))
	$removedText = [string]$Unreleased['Removed']
	$breakingText = [string]$Unreleased['Breaking']
	$withdrawnText = [string]$Unreleased['Withdrawn']

	$deprecatedIn = {
		param([string]$Kind, [string]$Item)
		$map = if ($Baseline.Deprecated) { $Baseline.Deprecated.$Kind } else { $null }
		if (-not $map) { return $null }
		$value = $map.$Item
		if (-not $value) { return $null }
		return [version](([string]$value) -replace '-.*$', '')
	}

	$sanctioned = {
		param([string]$Kind, [string]$Item)
		$token = '`' + $Item + '`'
		if ($breakingText.Contains($token)) { return $true }
		if ($withdrawnText.Contains($token)) { return $true }
		$since = & $deprecatedIn $Kind $Item
		return ($null -ne $since -and $since -le $baselineVersion -and $removedText.Contains($token))
	}

	$currentNames = @($Current.Functions.Keys) + @($Current.Aliases)
	foreach ($property in $Baseline.Functions.PSObject.Properties) {
		$name = $property.Name
		if ($currentNames -notcontains $name) {
			if (-not (& $sanctioned 'Functions' $name)) {
				$violations.Add("Exported function [$name] was removed. Keep it working and deprecate it first (VERSIONING.md, Deprecation policy); it can be removed in the next MAJOR.")
			}
			continue
		}
		if (-not $Current.Functions.Contains($name)) { continue }

		$now = $Current.Functions[$name].Parameters
		$knownNow = [System.Collections.Generic.List[string]]::new()
		foreach ($parameterName in $now.Keys) {
			$knownNow.Add($parameterName)
			foreach ($alias in @($now[$parameterName].Aliases)) { $knownNow.Add([string]$alias) }
		}

		$before = $property.Value.Parameters
		foreach ($parameter in @($before.PSObject.Properties)) {
			if ($knownNow -notcontains $parameter.Name) {
				if (-not (& $sanctioned 'Parameters' "$name -$($parameter.Name)")) {
					$violations.Add("Parameter [-$($parameter.Name)] of [$name] was removed or renamed. Keep it working (an [Alias()] keeps a renamed one) and deprecate it first.")
				}
			}
		}
		foreach ($parameterName in $now.Keys) {
			if (-not $now[$parameterName].Mandatory) { continue }
			$old = $before.$parameterName
			if ($null -eq $old -or -not $old.Mandatory) {
				if (-not (& $sanctioned 'Parameters' "$name -$parameterName")) {
					$violations.Add("Parameter [-$parameterName] of [$name] is mandatory now, which breaks every existing call that omits it. Make it optional with a default.")
				}
			}
		}
	}

	foreach ($key in @($Baseline.ConfigurationKeys)) {
		if (@($Current.ConfigurationKeys) -notcontains $key) {
			if (-not (& $sanctioned 'ConfigurationKeys' $key)) {
				$violations.Add("Configuration key [$key] is no longer in the shipped Configuration.psd1. Keep reading it and deprecate it first; it can be removed in the next MAJOR.")
			}
		}
	}

	return [string[]]$violations.ToArray()
}
