function Resolve-RepositoryTargets {
	<#
	.SYNOPSIS
		Expands repository names, group names, or every configured group into resolved repository targets.

	.DESCRIPTION
		The single place that turns a selection into concrete repositories. `RepositoryGroups`
		is an ordered list of single-key hashtables whose keys are freely configurable group
		names; nothing in code knows a group name, so every caller states what it wants by
		name (-Repositories), by group (-Group), or by asking for everything (-All).

		Each repository is resolved through `Resolve-ProjectPath -ForRepository`, which turns
		the configured `UrlPath` / `LocalPath` dot-notation into a real URL and a real path for
		this machine. Order follows the configuration: groups in the order they were requested
		(config order for -All), repositories in the order the group lists them - never sorted.

		Group matching is case-insensitive, and the returned `Group` carries the spelling from
		the configuration so callers can echo it back. If any requested group is unknown, the
		whole call fails before a single repository is resolved: one error listing every
		configured group name, then $null.

		The result is deduplicated by `LocalPath` (case-insensitive, first occurrence wins), so
		a repository listed in two groups is still only updated once.

	.PARAMETER Repositories
		Repository names as defined in RepositoryGroups. Null or whitespace entries are skipped.

	.PARAMETER Group
		One or more group names from RepositoryGroups. Matched case-insensitively.

	.PARAMETER All
		Expands every configured group, in configuration order.

	.OUTPUTS
		[object[]] - one PSCustomObject per repository: Name, Group, RepositoryUrl, LocalPath.
		The array is returned comma-wrapped, so an empty selection stays an empty array;
		$null is reserved for a requested group name that is not configured.

	.EXAMPLE
		Resolve-RepositoryTargets -Group Work
		Every repository in the "Work" group, in the order the configuration lists them.

	.EXAMPLE
		Resolve-RepositoryTargets -Group Work, OpenSource
		Both groups, Work first, with repositories shared between them listed once.

	.EXAMPLE
		Resolve-RepositoryTargets -All
		Every configured repository, groups in configuration order.
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param(
		[Parameter(Mandatory = $false)]
		[string[]]$Repositories,

		[Parameter(Mandatory = $false)]
		[string[]]$Group,

		[Parameter(Mandatory = $false)]
		[switch]$All
	)

	$repositoryGroups = @(Get-ConfigSetting -Path 'RepositoryGroups' -Default @())
	$configuredGroups = @()
	foreach ($repositoryGroup in $repositoryGroups) {
		$configuredGroups += @($repositoryGroup.Keys)[0]
	}

	$groupsToExpand = @()

	if ($All) {
		$groupsToExpand = $configuredGroups
	}
	elseif ($Group) {
		# Validate every requested name first: a typo must not update half the repositories
		# before the error surfaces. -eq on strings is case-insensitive, and the matched
		# element is the CONFIGURED spelling, which is what callers put in their titles.
		$unknownGroups = @()

		foreach ($requestedGroup in $Group) {
			$matchedGroup = @($configuredGroups | Where-Object { $_ -eq $requestedGroup })[0]

			if ($matchedGroup) { $groupsToExpand += $matchedGroup }
			else { $unknownGroups += $requestedGroup }
		}

		if ($unknownGroups.Count -gt 0) {
			Write-LogError "Unknown repository group [$($unknownGroups -join ', ')]. Configured groups => [$($configuredGroups -join ', ')]"
			return $null
		}
	}

	# Flatten the selection into name/group pairs before resolving anything, so the resolution
	# loop below stays a single pass over a single list regardless of how the caller selected.
	$targets = @()

	foreach ($groupName in $groupsToExpand) {
		foreach ($repositoryGroup in $repositoryGroups) {
			if (@($repositoryGroup.Keys)[0] -ne $groupName) { continue }

			foreach ($repository in $repositoryGroup[$groupName]) {
				$targets += @{ Name = $repository.Name; Group = $groupName }
			}
		}
	}

	foreach ($repositoryName in $Repositories) {
		if ([string]::IsNullOrWhiteSpace($repositoryName)) { continue }

		$owningGroup = $null
		foreach ($repositoryGroup in $repositoryGroups) {
			$groupName = @($repositoryGroup.Keys)[0]

			foreach ($repository in $repositoryGroup[$groupName]) {
				if ($repository.Name -eq $repositoryName) {
					$owningGroup = $groupName
					break
				}
			}

			if ($owningGroup) { break }
		}

		$targets += @{ Name = $repositoryName.Trim(); Group = $owningGroup }
	}

	$resolvedTargets = @()
	$seenLocalPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

	foreach ($target in $targets) {
		$resolvedRepo = Resolve-ProjectPath -ProjectName $target.Name -ForRepository
		if ($null -eq $resolvedRepo) { continue }

		# A repository listed in two groups resolves to the same LocalPath; updating it twice
		# would stash, pull and unstash the same working tree again for no reason.
		if (-not $seenLocalPaths.Add([string]$resolvedRepo.LocalPath)) { continue }

		$resolvedTargets += [PSCustomObject]@{
			Name          = $target.Name
			Group         = $target.Group
			RepositoryUrl = $resolvedRepo.RepositoryUrl
			LocalPath     = $resolvedRepo.LocalPath
		}
	}

	# Comma operator: an empty result must stay an empty array, because $null is how this
	# function reports an unknown group name.
	return , $resolvedTargets
}
