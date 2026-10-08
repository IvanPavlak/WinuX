function Update-Repositories {
	<#
	.SYNOPSIS
		Clones or updates one or more git repositories defined in Configuration.psd1.

	.DESCRIPTION
		Reads repository URL and local path mappings from `RepositoryGroups` in
		Configuration.psd1. Repositories are organized into named groups (for example
		"Private" and "Work"); the group names are defined in configuration, not in code,
		so -Group takes whatever names the configuration defines.

		When called with no parameters, shows an interactive menu grouped by group name.
		Otherwise selection is by repository name, by group name, by -All, or by an
		explicit URL/path pair - the modes are mutually exclusive, enforced by parameter sets.

		Repositories are updated in the order the configuration lists them, and a repository
		that appears in more than one selected group is still updated only once.

		Each existing repository is updated by Update-Repository: local changes are stashed, the
		checked-out branch is fast-forwarded, and the stash is popped. With
		-IncludeDefaultBranch (or RepositoryUpdate.IncludeDefaultBranch in configuration) the
		default branch is fast-forwarded too, without checking it out.

		A repository missing locally is cloned via Initialize-Repository, unless -NoClone is
		given, in which case it is reported and skipped.

		Archive mode: downloads repository contents without the `.git` directory, via
		`git clone --depth 1` followed by `.git` directory removal.

		Administrator privileges are required only to clone: in archive mode, and when a
		selected repository is missing locally and -NoClone is not given. Updating repositories
		that already exist works in any shell.

	.PARAMETER Repositories
		One or more repository names to update by name, as defined in RepositoryGroups.

	.PARAMETER RepositoryUrl
		HTTPS URL of a specific repository to update. Must be paired with -LocalPath.

	.PARAMETER LocalPath
		Absolute local path for the repository. Must be paired with -RepositoryUrl.

	.PARAMETER Group
		One or more group names from RepositoryGroups (for example "Private", "Work").
		Matched case-insensitively; an unknown name lists the configured groups and
		updates nothing.

	.PARAMETER All
		Updates all repositories in RepositoryGroups regardless of group.

	.PARAMETER InCurrentDirectory
		Clones repositories into the current working directory instead of the configured paths.

	.PARAMETER Archive
		Downloads repository contents without git history. Targets the Desktop by default;
		combine with -InCurrentDirectory to use the current folder.

	.PARAMETER IncludeDefaultBranch
		Also fast-forward each repository's default branch when another branch is checked out.
		When not passed, RepositoryUpdate.IncludeDefaultBranch decides (default $false);
		-IncludeDefaultBranch:$false turns it off for one call even when configuration has it on.

	.PARAMETER NoClone
		Report and skip repositories that are missing locally instead of cloning them, so the
		call never needs Administrator.

	.PARAMETER Quiet
		One line per repository plus a totals line, and git silenced - the compact form the
		startup update prints. A run spanning several groups shows a heading per group. The
		totals line colors each count (Write-LogSegments): updated blue, up to date green, need
		attention red, skipped yellow.

	.EXAMPLE
		Update-Repositories
		Opens the interactive repository selection menu.

	.EXAMPLE
		Update-Repositories -Group Work
		Updates every repository in the "Work" group.

	.EXAMPLE
		Update-Repositories -All
		Updates every repository defined in RepositoryGroups.

	.EXAMPLE
		Update-Repositories -RepositoryUrl "https://github.com/user/repo" -LocalPath "C:\Dev\repo"
		Updates or clones a specific repository.

	.EXAMPLE
		Update-Repositories -Group Work, OpenSource -Archive -InCurrentDirectory
		Downloads both groups without git history into the current directory.

	.EXAMPLE
		Update-Repositories -All -IncludeDefaultBranch
		Updates every repository and also fast-forwards each one's default branch.

	.EXAMPLE
		Update-Repositories -All -NoClone -Quiet
		Updates every repository already on disk, one line each, without asking for Administrator.
	#>
	[CmdletBinding(DefaultParameterSetName = 'Interactive')]
	param(
		[Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByName')]
		[string[]]$Repositories,

		[Parameter(Mandatory = $true, ParameterSetName = 'Custom')]
		[string]$RepositoryUrl,

		[Parameter(Mandatory = $true, ParameterSetName = 'Custom')]
		[string]$LocalPath,

		[Parameter(Mandatory = $true, ParameterSetName = 'ByGroup')]
		[string[]]$Group,

		[Parameter(Mandatory = $true, ParameterSetName = 'All')]
		[switch]$All,

		[Parameter(Mandatory = $false)]
		[switch]$InCurrentDirectory,

		[Parameter(Mandatory = $false)]
		[switch]$Archive,

		[Parameter(Mandatory = $false)]
		[switch]$IncludeDefaultBranch,

		[Parameter(Mandatory = $false)]
		[switch]$NoClone,

		[Parameter(Mandatory = $false)]
		[switch]$Quiet
	)

	# An explicitly bound switch (including -IncludeDefaultBranch:$false) wins over configuration.
	$includeDefaultBranch = if ($PSBoundParameters.ContainsKey('IncludeDefaultBranch')) {
		[bool]$IncludeDefaultBranch
	}
	else {
		[bool](Get-ConfigSetting -Path 'RepositoryUpdate.IncludeDefaultBranch' -Default $false)
	}

	$repositoriesToUpdate = @()

	switch ($PSCmdlet.ParameterSetName) {
		'Custom' {
			Write-LogTitle "Updating Specified Repository"
			$repositoriesToUpdate += @{
				RepositoryUrl = $RepositoryUrl
				LocalPath     = $LocalPath
			}
		}

		'ByName' {
			Write-LogTitle "Updating Selected Repositories"
			# No @() around the call: the resolver returns its array comma-wrapped so an empty
			# result stays distinguishable from $null, and @() would nest it instead of flatten it.
			$resolvedTargets = Resolve-RepositoryTargets -Repositories $Repositories
			$repositoriesToUpdate += $resolvedTargets
		}

		'ByGroup' {
			$resolvedTargets = Resolve-RepositoryTargets -Group $Group

			# $null means an unknown group name - Resolve-RepositoryTargets already listed the
			# configured ones, and deliberately resolved nothing.
			if ($null -eq $resolvedTargets) { return }

			# Echo the configured spelling of the groups that actually carry repositories;
			# fall back to what was asked for when every requested group turned out empty.
			$groupNames = @()
			foreach ($target in $resolvedTargets) {
				if ($target.Group -and $groupNames -notcontains $target.Group) { $groupNames += $target.Group }
			}
			if ($groupNames.Count -eq 0) { $groupNames = $Group }

			Write-LogTitle "Updating [$($groupNames -join ', ')] Repositories"
			$repositoriesToUpdate += $resolvedTargets
		}

		'All' {
			Write-LogTitle "Updating All Repositories"
			$resolvedTargets = Resolve-RepositoryTargets -All
			$repositoriesToUpdate += $resolvedTargets
		}

		default {
			# The menu is built from the same resolver the direct modes use, so its entries
			# carry the real repository URL rather than a stand-in.
			$repoGroups = @()
			$allTargets = Resolve-RepositoryTargets -All

			foreach ($target in $allTargets) {
				$existingGroup = $null
				foreach ($entry in $repoGroups) {
					if (@($entry.Keys)[0] -eq $target.Group) {
						$existingGroup = $entry
						break
					}
				}

				if ($null -eq $existingGroup) {
					$repoGroups += @{ $target.Group = @(@{ Name = $target.Name; Url = $target.RepositoryUrl }) }
				}
				else {
					$groupKey = @($existingGroup.Keys)[0]
					$existingGroup[$groupKey] = @($existingGroup[$groupKey]) + @{ Name = $target.Name; Url = $target.RepositoryUrl }
				}
			}

			$resolveParams = @{
				GroupsConfig            = $repoGroups
				MenuTitle               = "[Available Repositories]"
				PromptMessage           = "Enter repository/repositories by number or name"
				AllowMultipleSelections = $true
			}

			$selectedRepos = Resolve-Selection @resolveParams

			if (-not $selectedRepos) {
				Write-LogWarning "No repositories selected"
				return
			}

			$selectedGroups = @()
			$selectedNames = @()

			foreach ($selection in $selectedRepos) {
				if ($selection.IsParent) { $selectedGroups += $selection.PathNames[-1] }
				else { $selectedNames += $selection.PathNames[-1] }
			}

			$message = "Updating Selected Repositories"
			if ($selectedRepos.Count -eq 1 -and $selectedRepos[0].IsParent) {
				$message = "Updating [$($selectedGroups[0])] Repositories"
			}
			Write-LogTitle $message

			$selectedTargets = @()
			if ($selectedGroups.Count -gt 0) { $selectedTargets += Resolve-RepositoryTargets -Group $selectedGroups }
			if ($selectedNames.Count -gt 0) { $selectedTargets += Resolve-RepositoryTargets -Repositories $selectedNames }

			# A group and one of its own repositories can both be picked in the same menu run;
			# each resolver call dedupes itself, so only the overlap across the two is left.
			$seenLocalPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
			foreach ($target in $selectedTargets) {
				if ($seenLocalPaths.Add([string]$target.LocalPath)) { $repositoriesToUpdate += $target }
			}
		}
	}

	if ($Archive) {
		$baseDirectory = if ($InCurrentDirectory) {
			(Get-Location).Path
		}
		else {
			[Environment]::GetFolderPath('Desktop')
		}

		foreach ($repo in $repositoriesToUpdate) {
			$repositoryName = Get-RepositoryName -RepositoryUrl $repo.RepositoryUrl
			$repo.LocalPath = Join-Path -Path $baseDirectory -ChildPath $repositoryName
		}
	}
	elseif ($InCurrentDirectory) {
		$baseDirectory = (Get-Location).Path

		foreach ($repo in $repositoriesToUpdate) {
			$repositoryName = Get-RepositoryName -RepositoryUrl $repo.RepositoryUrl
			$newLocalPath = Join-Path -Path $baseDirectory -ChildPath $repositoryName
			$repo.LocalPath = $newLocalPath
		}
	}

	if ($Archive) {
		# Archive mode only ever clones.
		Test-AdminPrivileges

		foreach ($repo in $repositoriesToUpdate) {
			$RepositoryName = Get-RepositoryName -RepositoryUrl $repo.RepositoryUrl
			$targetPath = $repo.LocalPath

			if ([string]::IsNullOrWhiteSpace($RepositoryName)) {
				Write-LogWarning "Skipping repository => Could not determine name!"
				continue
			}

			if (Test-Path $targetPath) {
				Write-LogWarning "Skipping [$RepositoryName] => Already exists at [$targetPath]"
				continue
			}

			Write-LogStep " Archiving [$RepositoryName] to [$targetPath]"

			$url = $repo.RepositoryUrl
			if (-not [string]::IsNullOrWhiteSpace($global:GithubPat)) {
				$cleanToken = $global:GithubPat.Trim()
				$sanitizedUrl = $url -replace 'https:\/\/.*@', 'https://'
				$url = $sanitizedUrl.Replace("https://", "https://$($cleanToken)@")
			}

			# A shallow clone with the .git directory removed, deliberately NOT
			# `git archive --remote`: that asks the server to run the git-upload-archive
			# service, which GitHub serves on no protocol (HTTP 422, git exits 128). Every
			# URL this function builds is a GitHub URL, so the attempt could never succeed -
			# it only cost two failed round trips per repository (one for `main`, one for
			# `master`) and printed a "git archive not supported" warning every single time.
			git clone --depth 1 $url $targetPath
			if ($LASTEXITCODE -ne 0) {
				Write-LogError "Failed to download [$RepositoryName]!"
				continue
			}

			$gitDir = Join-Path $targetPath ".git"
			if (Test-Path $gitDir) {
				Remove-Item -Path $gitDir -Recurse -Force
				Write-LogStep " Removed .git directory"
			}

			Write-LogSuccess "Downloaded [$RepositoryName] without git history!"
		}
		return
	}

	# Administrator is needed to clone (Initialize-Repository takes ownership of the new folder),
	# never to update a repository that is already on disk - so ask once, and only when this run
	# is actually going to clone something.
	if (-not $NoClone) {
		foreach ($repo in $repositoriesToUpdate) {
			if (-not [string]::IsNullOrWhiteSpace($repo.LocalPath) -and -not (Test-Path $repo.LocalPath)) {
				Test-AdminPrivileges
				break
			}
		}
	}

	# A run that spans several groups is printed under one heading per group, in the order the
	# targets were resolved (configuration order). A single-group run already names its group in
	# the title, and a custom URL/path target has no group at all.
	$distinctGroups = @($repositoriesToUpdate | ForEach-Object { $_.Group } | Where-Object { $_ } | Select-Object -Unique)
	$showGroups = $distinctGroups.Count -gt 1
	$currentGroup = $null
	$firstLineAfterHeading = $false

	$counts = [ordered]@{ Updated = 0; UpToDate = 0; Attention = 0; Skipped = 0 }
	foreach ($repo in $repositoriesToUpdate) {
		$RepositoryName = Get-RepositoryName -RepositoryUrl $repo.RepositoryUrl
		# A URL that yields no name (a local path, a typo) must not stop the whole run.
		if ([string]::IsNullOrWhiteSpace($RepositoryName)) { $RepositoryName = if ($repo.Name) { $repo.Name } elseif ($repo.LocalPath) { Split-Path $repo.LocalPath -Leaf } else { "(unnamed)" } }

		if ($showGroups -and $repo.Group -and $repo.Group -ne $currentGroup) {
			$currentGroup = $repo.Group
			Write-LogTitle $currentGroup
			$firstLineAfterHeading = $true
		}

		if ([string]::IsNullOrWhiteSpace($repo.LocalPath)) {
			if (-not $Quiet) { Write-LogWarning "Skipping [$RepositoryName] => LocalPath not configured for this machine!" }
			$result = [pscustomobject]@{ Name = $RepositoryName; LocalPath = $null; Branch = $null; Outcome = "NotConfigured"; DefaultBranch = $null; DefaultBranchOutcome = $null; StashName = $null }
		}
		elseif (-not (Test-Path $repo.LocalPath)) {
			if ($NoClone) {
				if (-not $Quiet) { Write-LogWarning "Repository [$RepositoryName] not found at [$($repo.LocalPath)] - not cloned (-NoClone)" }
				$result = [pscustomobject]@{ Name = $RepositoryName; LocalPath = $repo.LocalPath; Branch = $null; Outcome = "NotCloned"; DefaultBranch = $null; DefaultBranchOutcome = $null; StashName = $null }
			}
			else {
				Write-LogWarning "Repository [$RepositoryName] not found at [$($repo.LocalPath)]"
				Initialize-Repository -RepositoryUrl $repo.RepositoryUrl -LocalPath $repo.LocalPath -Token $global:GithubPat
				$result = [pscustomobject]@{ Name = $RepositoryName; LocalPath = $repo.LocalPath; Branch = $null; Outcome = "Cloned"; DefaultBranch = $null; DefaultBranchOutcome = $null; StashName = $null }
			}
		}
		else {
			$result = Update-Repository -Name $RepositoryName -LocalPath $repo.LocalPath -IncludeDefaultBranch:$includeDefaultBranch -Quiet:$Quiet
		}

		$line = Format-RepositoryUpdateResult -Result $result
		$counts[$line.Category]++
		if ($Quiet) {
			# A blank line separates a group heading from its first repository; the rest of the
			# group's lines follow without one.
			$noLead = -not $firstLineAfterHeading
			if ($line.Level -eq "Success") { Write-LogSuccess $line.Message -NoLeadingNewline:$noLead }
			else { Write-LogWarning $line.Message -NoLeadingNewline:$noLead }
		}
		$firstLineAfterHeading = $false
	}

	if ($Quiet) {
		# Each count in its own color, whatever its value: updated blue, up to date green, need
		# attention red, skipped yellow.
		Write-LogSegments @(
			@{ Text = "=> Repositories => " }
			@{ Text = "$($counts.Updated) updated"; Style = "Info" }
			@{ Text = ", " }
			@{ Text = "$($counts.UpToDate) up to date"; Style = "Success" }
			@{ Text = ", " }
			@{ Text = "$($counts.Attention) need attention"; Style = "Error" }
			@{ Text = ", " }
			@{ Text = "$($counts.Skipped) skipped"; Style = "Warning" }
		)
	}
}
