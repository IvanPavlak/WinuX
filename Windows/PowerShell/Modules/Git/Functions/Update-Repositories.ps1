function Update-Repositories {
	<#
	.SYNOPSIS
		Clones or updates one or more git repositories defined in Configuration.psd1.

	.DESCRIPTION
		Reads repository URL and local path mappings from `RepositoryGroups` in
		Configuration.psd1. Repositories are organized into named groups (for example
		"Private" and "Work"); the group names are defined in configuration, not in code.

		When called with no parameters, shows an interactive menu grouped by group name.
		When called with switches, updates the corresponding repository group directly.

		Archive mode: downloads repository contents without the `.git` directory.
		Tries `git archive` first (requires server-side support); falls back to
		`git clone --depth 1` followed by `.git` directory removal.

		Requires administrator privileges.

	.PARAMETER Repositories
		One or more repository names to update by name, as defined in RepositoryGroups.

	.PARAMETER RepositoryUrl
		HTTPS URL of a specific repository to update. Must be paired with -LocalPath.

	.PARAMETER LocalPath
		Absolute local path for the repository. Must be paired with -RepositoryUrl.

	.PARAMETER Private
		Updates all repositories in the "Private" group in RepositoryGroups.

	.PARAMETER Work
		Updates all repositories in the "Work" group in RepositoryGroups.

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
		Update-Repositories -Private
		Updates all private repositories.

	.EXAMPLE
		Update-Repositories -All
		Updates every repository defined in RepositoryGroups.

	.EXAMPLE
		Update-Repositories -RepositoryUrl "https://github.com/user/repo" -LocalPath "C:\Dev\repo"
		Updates or clones a specific repository.

	.EXAMPLE
		Update-Repositories -Private -Archive -InCurrentDirectory
		Downloads all private repositories without git history into the current directory.
	#>
	param(
		[Parameter(Mandatory = $false, Position = 0)]
		[string[]]$Repositories,

		[Parameter(Mandatory = $false)]
		[string]$RepositoryUrl,

		[Parameter(Mandatory = $false)]
		[string]$LocalPath,

		[Parameter(Mandatory = $false)]
		[switch]$Private,

		[Parameter(Mandatory = $false)]
		[switch]$Work,

		[Parameter(Mandatory = $false)]
		[switch]$All,

		[Parameter(Mandatory = $false)]
		[switch]$InCurrentDirectory,

		[Parameter(Mandatory = $false)]
		[switch]$Archive
	)

	Test-AdminPrivileges

	$repositoriesToUpdate = @()

	$isCustomUrl = $RepositoryUrl -and $LocalPath
	$isByType = $Private -or $Work -or $All
	$isByName = $Repositories -and $Repositories.Count -gt 0

	if ($isCustomUrl) {
		Write-LogTitle "Updating Specified Repository"
		$repositoriesToUpdate += @{
			RepositoryUrl = $RepositoryUrl
			LocalPath     = $LocalPath
		}
	}
	elseif ($isByName) {
		Write-LogTitle "Updating Selected Repositories"

		foreach ($repoName in $Repositories) {
			if ([string]::IsNullOrWhiteSpace($repoName)) { continue }

			$resolvedRepo = Resolve-ProjectPath -ProjectName $repoName -ForRepository
			if ($null -ne $resolvedRepo) {
				$repositoriesToUpdate += $resolvedRepo
			}
		}
	}
	elseif ($isByType) {
		$repositoryType = if ($Private) { "Private" }
		elseif ($Work) { "Work" }
		else { "All" }

		Write-LogTitle "Updating $repositoryType Repositories"

		foreach ($repositoryGroup in $Configuration.RepositoryGroups) {
			$groupName = @($repositoryGroup.Keys)[0]

			if ($repositoryType -ne 'All' -and $groupName -ne $repositoryType) { continue }

			foreach ($repository in ($repositoryGroup[$groupName] | Sort-Object { $_.Name })) {
				$resolvedRepo = Resolve-ProjectPath -ProjectName $repository.Name -ForRepository
				if ($null -ne $resolvedRepo) {
					$repositoriesToUpdate += $resolvedRepo
				}
			}
		}
	}
	else {
		$repoGroups = @()

		foreach ($repositoryGroup in $Configuration.RepositoryGroups) {
			$groupName = @($repositoryGroup.Keys)[0]

			$groupRepos = @()
			foreach ($repository in ($repositoryGroup[$groupName] | Sort-Object { $_.Name })) {
				$groupRepos += @{ Name = $repository.Name; Url = $repository.Name }
			}

			if ($groupRepos.Count -gt 0) {
				$repoGroups += @{ $groupName = $groupRepos }
			}
		}

		$resolveParams = @{
			GroupsConfig            = $repoGroups
			MenuTitle               = "[Available Repositories]"
			OptionList              = $optionList
			PromptMessage           = "Enter repository/repositories by number or name"
			AllowMultipleSelections = $true
		}

		$selectedRepos = Resolve-Selection @resolveParams

		if (-not $selectedRepos) {
			Write-LogWarning "No repositories selected"
			return
		}

		$message = "Updating Selected Repositories"
		if ($selectedRepos.Count -eq 1 -and $selectedRepos[0].IsParent) {
			$groupType = $selectedRepos[0].PathNames[-1]
			$message = "Updating [$groupType] Repositories"
		}
		Write-LogTitle $message

		foreach ($selection in $selectedRepos) {
			$pathNames = $selection.PathNames
			$isParent = $selection.IsParent

			if ($isParent) {
				$groupType = $pathNames[-1]

				foreach ($repositoryGroup in $Configuration.RepositoryGroups) {
					$groupName = @($repositoryGroup.Keys)[0]
					if ($groupName -ne $groupType) { continue }

					foreach ($repository in ($repositoryGroup[$groupName] | Sort-Object { $_.Name })) {
						$resolvedRepo = Resolve-ProjectPath -ProjectName $repository.Name -ForRepository
						if ($null -ne $resolvedRepo) {
							$repositoriesToUpdate += $resolvedRepo
						}
					}
				}
			}
			else {
				$repoName = $pathNames[-1]
				$resolvedRepo = Resolve-ProjectPath -ProjectName $repoName -ForRepository
				if ($null -ne $resolvedRepo) {
					$repositoriesToUpdate += $resolvedRepo
				}
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

			# Try git archive first (requires server-side support)
			$archiveSuccess = $false
			$archivePath = Join-Path ([System.IO.Path]::GetTempPath()) "$RepositoryName.zip"

			if (Test-Path $archivePath) {
				Remove-Item -Path $archivePath -Force
			}

			foreach ($branch in @('main', 'master')) {
				Write-LogStep " Trying git archive (branch: $branch)..."
				git archive --remote="$url" --format=zip --output="$archivePath" $branch 2>$null
				if ($LASTEXITCODE -eq 0 -and (Test-Path $archivePath)) {
					$null = New-Item -ItemType Directory -Path $targetPath -Force
					Expand-Archive -Path $archivePath -DestinationPath $targetPath -Force
					Remove-Item -Path $archivePath -Force
					$archiveSuccess = $true
					Write-LogSuccess "Archived [$RepositoryName] successfully!"
					break
				}
			}

			if (-not $archiveSuccess) {
				Write-LogWarning "git archive not supported, falling back to shallow clone..."

				if (Test-Path $archivePath) {
					Remove-Item -Path $archivePath -Force
				}

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

				Write-LogSuccess "Downloaded [$RepositoryName] via shallow clone!"
			}
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
