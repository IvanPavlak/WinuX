function Update-Repository {
	<#
	.SYNOPSIS
		Updates one cloned repository: the checked-out branch, optionally the default branch,
		with local changes preserved.

	.DESCRIPTION
		The per-repository step of Update-Repositories. In order:

		1. Reads the checked-out branch.
		2. Stashes local changes, untracked files included, as `<branch>_<timestamp>`. The stash
		   runs with an ephemeral identity, so it works before a global git identity exists.
		   When the stash fails the repository is left alone.
		3. Fetches the checked-out branch and fast-forwards it (`git pull --ff-only`) when it is
		   behind. A pull that cannot fast-forward is aborted and the stash is given back. A
		   branch origin does not have (never pushed) has nothing to pull; a fetch that fails
		   while origin has the branch (offline) pulls nothing and says so.
		4. With -IncludeDefaultBranch, fast-forwards the default branch too, without checking it
		   out (Resolve-RepositoryDefaultBranch, then Update-RepositoryDefaultBranch). It runs
		   whatever happened in step 3, because it never touches the working tree. When neither
		   configuration nor origin/HEAD names the default branch, it asks origin once
		   (`git remote set-head origin --auto`, which writes only that local ref) and resolves
		   again, so such a repository heals itself on its first run.
		5. Pops the stash after a successful pull. A conflicting pop keeps the stash.

		The repository must exist; cloning a missing one is Update-Repositories' job.

		Without -Quiet every step is logged and git's own output reaches the console, exactly
		as Update-Repositories always printed it. With -Quiet nothing is logged, git runs with
		--quiet and its stderr dropped, and the caller reports the returned result.

	.PARAMETER Name
		The repository's display name, used in messages and returned in the result.

	.PARAMETER LocalPath
		The repository's working-tree path. Must exist.

	.PARAMETER IncludeDefaultBranch
		Also fast-forward the default branch when another branch is checked out.

	.PARAMETER Quiet
		Log nothing and silence git; the caller prints the result.

	.OUTPUTS
		[pscustomobject] with Name, LocalPath, Branch, Outcome, DefaultBranch,
		DefaultBranchOutcome and StashName.
		Outcome: Updated, UpToDate, NoUpstream (the branch is not on origin), FetchFailed
		(offline or origin unreachable), Conflict (the pull could not fast-forward), StashFailed
		(local changes could not be stashed, nothing was done), StashConflict (updated, but the
		stash did not pop cleanly and is kept), or Error.
		DefaultBranchOutcome: $null when the step did not run, Unresolved when no default
		branch could be named, otherwise what Update-RepositoryDefaultBranch returned.

	.EXAMPLE
		Update-Repository -Name MyRepo -LocalPath "C:\Dev\MyRepo"
		Fast-forwards the checked-out branch, preserving local changes.

	.EXAMPLE
		Update-Repository -Name MyRepo -LocalPath "C:\Dev\MyRepo" -IncludeDefaultBranch -Quiet
		Also brings master up to date, logs nothing, and returns the result for a summary.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Name,

		[Parameter(Mandatory = $true)]
		[string]$LocalPath,

		[Parameter(Mandatory = $false)]
		[switch]$IncludeDefaultBranch,

		[Parameter(Mandatory = $false)]
		[switch]$Quiet
	)

	$result = [pscustomobject]@{
		Name                 = $Name
		LocalPath            = $LocalPath
		Branch               = $null
		Outcome              = $null
		DefaultBranch        = $null
		DefaultBranchOutcome = $null
		StashName            = $null
	}
	$quietFlag = @(if ($Quiet) { "--quiet" })

	Push-Location $LocalPath
	try {
		if (-not $Quiet) { Write-LogStep " Checking status of [$Name]" }

		$currentBranch = git rev-parse --abbrev-ref HEAD
		$result.Branch = "$currentBranch"
		if (-not $Quiet) { Write-LogStep " Current branch => [$currentBranch]" }

		$status = git status --porcelain
		$stashName = $null
		if ($status) {
			if (-not $Quiet) { Write-LogWarning "Local changes detected. Creating stash..." }

			$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
			$stashName = "${currentBranch}_$timestamp"

			# git stash creates commit objects, which git refuses without an author identity
			# ("fatal: empty ident name"). Supply an ephemeral identity for this command only,
			# so stashing works even before the machine's global identity is configured -
			# stash authorship is throwaway metadata and never lands in history.
			$stashArgs = @("-c", "user.name=WinuX", "-c", "user.email=winux@localhost", "stash", "push", "--include-untracked") + $quietFlag + @("-m", $stashName)
			if ($Quiet) { git @stashArgs 2>$null | Out-Null } else { git @stashArgs | Out-Host }
			if ($LASTEXITCODE -ne 0) {
				if (-not $Quiet) { Write-LogError "Failed to stash changes in [$Name]. Skipping update." }
				$result.Outcome = "StashFailed"
				return $result
			}
			$result.StashName = $stashName
			if (-not $Quiet) { Write-LogSuccess "Changes stashed as [$stashName]" }
		}

		if (-not $Quiet) {
			Write-LogStep " Updating [$Name] on branch [$currentBranch]"
			Write-LogWarning "Fetching latest changes..."
		}
		$fetchArgs = @("fetch") + $quietFlag + @("origin", $currentBranch)
		if ($Quiet) { git @fetchArgs 2>$null | Out-Null } else { git @fetchArgs | Out-Host }
		$fetchExitCode = $LASTEXITCODE

		# A branch origin does not have (never pushed) has nothing to pull, and a fetch that failed
		# while origin does have it (offline) must not be reported as up to date against a stale
		# remote-tracking ref. Both used to fall through to the pull and read as a merge conflict.
		git rev-parse --verify --quiet "refs/remotes/origin/$currentBranch" | Out-Null
		$hasUpstream = ($LASTEXITCODE -eq 0)

		$restoreStashAtEnd = $true
		$behind = if ($hasUpstream -and $fetchExitCode -eq 0) { git rev-list HEAD..origin/$currentBranch --count 2>$null } else { $null }
		if (-not $hasUpstream) {
			$result.Outcome = "NoUpstream"
			if (-not $Quiet) { Write-LogWarning "Branch [$currentBranch] is not on origin - nothing to pull" }
		}
		elseif ($fetchExitCode -ne 0) {
			$result.Outcome = "FetchFailed"
			if (-not $Quiet) { Write-LogError "Failed to fetch [$currentBranch] from origin - nothing was pulled" }
		}
		elseif ($behind -eq 0) {
			$result.Outcome = "UpToDate"
			if (-not $Quiet) { Write-LogSuccess "Repository is already up to date!" }
		}
		else {
			if (-not $Quiet) { Write-LogWarning "Pulling latest changes..." }

			$pullArgs = @("pull") + $quietFlag + @("origin", $currentBranch, "--ff-only")
			if ($Quiet) { git @pullArgs 2>$null | Out-Null } else { git @pullArgs | Out-Host }
			if ($LASTEXITCODE -ne 0) {
				$restoreStashAtEnd = $false
				$result.Outcome = "Conflict"
				if (-not $Quiet) { Write-LogError "Merge conflicts detected. Aborting!" }
				if ($Quiet) { git merge --abort 2>$null | Out-Null } else { git merge --abort | Out-Host }

				if ($stashName) {
					if (-not $Quiet) { Write-LogWarning "Restoring stashed changes..." }
					$popArgs = @("stash", "pop") + $quietFlag
					if ($Quiet) { git @popArgs 2>$null | Out-Null } else { git @popArgs | Out-Host }
					if ($LASTEXITCODE -ne 0) {
						if (-not $Quiet) {
							Write-LogError "Failed to restore stashed changes!"
							Write-LogWarning "Changes are preserved in stash => [$stashName]"
							Write-LogWarning "Restore manually with => [git stash pop]" -NoLeadingNewline
						}
					}
					else {
						$result.StashName = $null
					}
				}

				if (-not $Quiet) { Write-LogWarning "Please resolve conflicts manually and try again" }
			}
			else {
				$result.Outcome = "Updated"
				if (-not $Quiet) { Write-LogSuccess "Updated repository" }
			}
		}

		# The default branch is fetched into directly and never checked out, so it is safe to run
		# whatever the pull above did and while the stash is still held.
		if ($IncludeDefaultBranch) {
			$defaultBranch = Resolve-RepositoryDefaultBranch -LocalPath $LocalPath
			if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
				# No configured name and no origin/HEAD - a repository not created by `git clone`.
				# Ask origin once and record its answer; that writes only the local symbolic ref
				# refs/remotes/origin/HEAD, so every later run resolves without asking again.
				if ($Quiet) { git remote set-head origin --auto 2>$null | Out-Null } else { git remote set-head origin --auto | Out-Host }
				if ($LASTEXITCODE -eq 0) {
					$defaultBranch = Resolve-RepositoryDefaultBranch -LocalPath $LocalPath
				}
			}
			if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
				$result.DefaultBranchOutcome = "Unresolved"
				if (-not $Quiet) { Write-LogWarning "Default branch of [$Name] could not be determined - set RepositoryUpdate.DefaultBranch or run [git remote set-head origin --auto]" }
			}
			else {
				$result.DefaultBranch = $defaultBranch
				$result.DefaultBranchOutcome = Update-RepositoryDefaultBranch -DefaultBranch $defaultBranch -CurrentBranch "$currentBranch" -LocalPath $LocalPath -Quiet:$Quiet
			}
		}

		if ($restoreStashAtEnd -and $stashName) {
			if (-not $Quiet) { Write-LogWarning "Attempting to restore stashed changes..." }
			$popArgs = @("stash", "pop") + $quietFlag
			if ($Quiet) { git @popArgs 2>$null | Out-Null } else { git @popArgs | Out-Host }
			if ($LASTEXITCODE -ne 0) {
				$result.Outcome = "StashConflict"
				if (-not $Quiet) {
					Write-LogError "Conflicts occurred while restoring stashed changes in [$Name]"
					Write-LogWarning "Changes are preserved in stash: $stashName"
					Write-LogWarning "Please resolve conflicts manually with [git stash pop]" -NoLeadingNewline
				}
			}
			else {
				$result.StashName = $null
				if (-not $Quiet) { Write-LogSuccess "Restored stashed changes!" }
			}
		}
	}
	catch {
		$result.Outcome = "Error"
		Write-LogError "An error occurred while updating [$Name]: $_"
	}
	finally {
		Pop-Location
	}

	return $result
}
