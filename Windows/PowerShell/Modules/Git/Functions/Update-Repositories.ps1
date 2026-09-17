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

		Archive mode: downloads repository contents without the `.git` directory, via
		`git clone --depth 1` followed by `.git` directory removal.

		Requires administrator privileges.

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
		[switch]$Archive
	)

	Test-AdminPrivileges

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

	foreach ($repo in $repositoriesToUpdate) {
		$RepositoryName = Get-RepositoryName -RepositoryUrl $repo.RepositoryUrl

		if ([string]::IsNullOrWhiteSpace($repo.LocalPath)) {
			Write-LogWarning "Skipping [$RepositoryName] => LocalPath not configured for this machine!"
			continue
		}

		if (-not (Test-Path $repo.LocalPath)) {
			Write-LogWarning "Repository [$RepositoryName] not found at [$($repo.LocalPath)]"
			Initialize-Repository -RepositoryUrl $repo.RepositoryUrl -LocalPath $repo.LocalPath -Token $global:GithubPat
			continue
		}

		Push-Location $repo.LocalPath
		try {
			Write-LogStep " Checking status of [$RepositoryName]"

			$currentBranch = git rev-parse --abbrev-ref HEAD
			Write-LogStep " Current branch => [$currentBranch]"

			$status = git status --porcelain
			$stashName = $null
			if ($status) {
				Write-LogWarning "Local changes detected. Creating stash..."

				$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
				$stashName = "${currentBranch}_$timestamp"

				# git stash creates commit objects, which git refuses without an author identity
				# ("fatal: empty ident name"). Supply an ephemeral identity for this command only,
				# so stashing works even before the machine's global identity is configured -
				# stash authorship is throwaway metadata and never lands in history.
				git -c user.name="WinuX" -c user.email="winux@localhost" stash push --include-untracked -m $stashName
				if ($LASTEXITCODE -ne 0) {
					Write-LogError "Failed to stash changes in [$RepositoryName]. Skipping update."
					continue
				}
				Write-LogSuccess "Changes stashed as [$stashName]"
			}

			Write-LogStep " Updating [$RepositoryName] on branch [$currentBranch]"

			Write-LogWarning "Fetching latest changes..."
			git fetch origin $currentBranch

			$behind = git rev-list HEAD..origin/$currentBranch --count
			if ($behind -eq 0) {
				Write-LogSuccess "Repository is already up to date!"
			}
			else {
				Write-LogWarning "Pulling latest changes..."

				git pull origin $currentBranch --ff-only
				if ($LASTEXITCODE -ne 0) {
					Write-LogError "Merge conflicts detected. Aborting!"
					git merge --abort

					if ($stashName) {
						Write-LogWarning "Restoring stashed changes..."
						git stash pop
						if ($LASTEXITCODE -ne 0) {
							Write-LogError "Failed to restore stashed changes!"
							Write-LogWarning "Changes are preserved in stash => [$stashName]"
							Write-LogWarning "Restore manually with => [git stash pop]" -NoLeadingNewline
						}
					}

					Write-LogWarning "Please resolve conflicts manually and try again"
					continue
				}

				Write-LogSuccess "Updated repository"
			}

			if ($stashName) {
				Write-LogWarning "Attempting to restore stashed changes..."
				git stash pop
				if ($LASTEXITCODE -ne 0) {
					Write-LogError "Conflicts occurred while restoring stashed changes in [$RepositoryName]"
					Write-LogWarning "Changes are preserved in stash: $stashName"
					Write-LogWarning "Please resolve conflicts manually with [git stash pop]" -NoLeadingNewline
					continue
				}
				Write-LogSuccess "Restored stashed changes!"
			}
		}
		catch {
			Write-LogError "An error occurred while updating [$RepositoryName]: $_"
		}
		finally {
			Pop-Location
		}
	}
}
