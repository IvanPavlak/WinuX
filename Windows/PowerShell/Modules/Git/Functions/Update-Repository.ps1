function Update-Repository {
	<#
	.SYNOPSIS
		Updates one cloned repository: the checked-out branch, optionally the default branch,
		with local changes preserved.

	.DESCRIPTION
		The per-repository step of Update-Repositories. Losing local work is never an acceptable
		outcome, so every step either leaves the repository exactly as it was or is undone:

		1. Refuses a path that is not the top of its own working tree. A folder that is not a
		   repository but sits inside another one would otherwise make every git command below
		   act on that parent repository.
		2. Refuses a repository in the middle of a merge, rebase, cherry-pick, revert or bisect,
		   or with unresolved conflicts - stashing or fast-forwarding there could throw away
		   work in progress.
		3. Skips the pull on a detached HEAD (a checked-out tag, a bisect position): there is
		   no branch to update, and moving HEAD would lose that position.
		4. Stashes local changes, untracked files included, as `<branch>_<timestamp>`, with an
		   ephemeral identity so it works before a global git identity exists. The stash is
		   tracked by its commit: a push that reports success without creating anything
		   (changes git cannot stash, such as a submodule's new commits) restores nothing later,
		   and a push that fails after creating the stash (a locked file) is restored at once.
		5. Fetches the checked-out branch and fast-forwards it when it is behind, with
		   `git merge --ff-only --no-overwrite-ignore origin/<branch>`: a plain pull would
		   silently overwrite an ignored local file (a local settings file) at a path upstream
		   starts tracking; this refuses instead. A branch origin does not have (never pushed)
		   has nothing to pull; a failed fetch (offline) pulls nothing and says so.
		6. With -IncludeDefaultBranch, fast-forwards the default branch too, without checking it
		   out (Resolve-RepositoryDefaultBranch, then Update-RepositoryDefaultBranch). When
		   neither configuration nor origin/HEAD names it, origin is asked once
		   (`git remote set-head origin --auto`).
		7. Restores exactly its own stash with Restore-RepositoryStash, which re-applies what
		   was staged too and drops the stash only after a clean restore. A conflicting restore
		   keeps the stash, so the original changes always survive in it.

		The repository must exist; cloning a missing one is Update-Repositories' job.

		Without -Quiet every step is logged and git's own output reaches the console. With
		-Quiet nothing is logged, git runs with --quiet and its stderr dropped, and the caller
		reports the returned result.

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
		(offline or origin unreachable), Conflict (could not fast-forward: diverged, or it would
		overwrite an ignored file), Detached (no branch checked out, nothing pulled), Busy (an
		operation is in progress, nothing done), NotARepository (the path is not the top of a
		working tree, nothing done), StashFailed (local changes could not be stashed; anything
		half-stashed was restored), StashConflict (the stash could not be restored cleanly and
		is kept, its name in StashName), or Error.
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

		# 1. The path must be the top of its own working tree (an empty prefix), or every
		# command below would act on whatever repository encloses it.
		$insideWorkTree = git rev-parse --is-inside-work-tree 2>$null
		$prefix = git rev-parse --show-prefix 2>$null
		if ("$insideWorkTree".Trim() -ne "true" -or -not [string]::IsNullOrWhiteSpace("$prefix")) {
			$result.Outcome = "NotARepository"
			if (-not $Quiet) { Write-LogError "[$LocalPath] is not the top of a git repository - nothing was touched" }
			return $result
		}

		# 2. Work in progress that a stash or a fast-forward could destroy.
		$gitDir = "$(git rev-parse --absolute-git-dir)".Trim()
		$operation = $null
		foreach ($marker in @(
				@("MERGE_HEAD", "a merge"), @("CHERRY_PICK_HEAD", "a cherry-pick"), @("REVERT_HEAD", "a revert"),
				@("rebase-merge", "a rebase"), @("rebase-apply", "a rebase or am"), @("BISECT_LOG", "a bisect")
			)) {
			if (Test-Path -LiteralPath (Join-Path $gitDir $marker[0])) { $operation = $marker[1]; break }
		}
		if (-not $operation -and (git ls-files --unmerged)) { $operation = "unresolved conflicts" }
		if ($operation) {
			$result.Outcome = "Busy"
			if (-not $Quiet) { Write-LogWarning "[$Name] has $operation in progress - nothing was touched" }
			return $result
		}

		$currentBranch = "$(git rev-parse --abbrev-ref HEAD)".Trim()
		$result.Branch = $currentBranch
		if (-not $Quiet) { Write-LogStep " Current branch => [$currentBranch]" }

		# 3. Detached HEAD: no branch to pull into, and moving HEAD would lose the position.
		$detached = ($currentBranch -eq "HEAD")
		$stashCommit = $null

		if ($detached) {
			$result.Outcome = "Detached"
			if (-not $Quiet) { Write-LogWarning "[$Name] has no branch checked out (detached HEAD) - nothing to pull" }
		}
		else {
			# 4. Stash, tracked by its commit.
			$status = git status --porcelain
			if ($status) {
				if (-not $Quiet) { Write-LogWarning "Local changes detected. Creating stash..." }

				$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
				$stashName = "${currentBranch}_$timestamp"
				$stashBefore = "$(git rev-parse --verify --quiet refs/stash)"

				# git stash creates commit objects, which git refuses without an author identity
				# ("fatal: empty ident name"). Supply an ephemeral identity for this command only,
				# so stashing works even before the machine's global identity is configured -
				# stash authorship is throwaway metadata and never lands in history.
				$stashArgs = @("-c", "user.name=WinuX", "-c", "user.email=winux@localhost", "stash", "push", "--include-untracked") + $quietFlag + @("-m", $stashName)
				if ($Quiet) { git @stashArgs 2>$null | Out-Null } else { git @stashArgs | Out-Host }
				$pushExitCode = $LASTEXITCODE

				$stashAfter = "$(git rev-parse --verify --quiet refs/stash)"
				if ($stashAfter -and $stashAfter -ne $stashBefore) { $stashCommit = $stashAfter }

				if ($pushExitCode -ne 0) {
					# A push can fail after it created the stash and reset part of the tree (a file
					# Windows keeps locked). Whatever it took is given back right away.
					$result.Outcome = "StashFailed"
					if ($stashCommit) {
						if ((Restore-RepositoryStash -StashCommit $stashCommit -Quiet:$Quiet) -ne "Restored") { $result.StashName = $stashName }
					}
					if (-not $Quiet) {
						Write-LogError "Failed to stash changes in [$Name]. Skipping update."
						if ($result.StashName) { Write-LogWarning "Part of the changes could not be put back and are kept in stash => [$stashName]" }
					}
					return $result
				}

				if ($stashCommit) {
					$result.StashName = $stashName
					if (-not $Quiet) { Write-LogSuccess "Changes stashed as [$stashName]" }
				}
				elseif (-not $Quiet) {
					# Nothing git can stash (a submodule's new commits, line-ending noise): there is
					# nothing to restore later either, and the pull below leaves such changes alone.
					Write-LogStep " Nothing stashable among the local changes - continuing"
				}
			}

			# 5. Fetch, then fast-forward without ever overwriting an ignored file.
			if (-not $Quiet) {
				Write-LogStep " Updating [$Name] on branch [$currentBranch]"
				Write-LogWarning "Fetching latest changes..."
			}
			$fetchArgs = @("fetch") + $quietFlag + @("origin", $currentBranch)
			if ($Quiet) { git @fetchArgs 2>$null | Out-Null } else { git @fetchArgs | Out-Host }
			$fetchExitCode = $LASTEXITCODE

			# A branch origin does not have (never pushed) has nothing to pull, and a fetch that
			# failed while origin does have it (offline) must not be reported as up to date
			# against a stale remote-tracking ref.
			git rev-parse --verify --quiet "refs/remotes/origin/$currentBranch" | Out-Null
			$hasUpstream = ($LASTEXITCODE -eq 0)

			$behind = if ($hasUpstream -and $fetchExitCode -eq 0) { git rev-list "HEAD..origin/$currentBranch" --count 2>$null } else { $null }
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

				# Not `git pull`: its merge silently replaces an ignored local file at a path the
				# incoming commits start tracking. --no-overwrite-ignore refuses instead, and a
				# --ff-only merge that refuses changes nothing - so there is never a merge to abort.
				$mergeArgs = @("merge", "--ff-only", "--no-overwrite-ignore") + $quietFlag + @("origin/$currentBranch")
				if ($Quiet) { git @mergeArgs 2>$null | Out-Null } else { git @mergeArgs | Out-Host }
				if ($LASTEXITCODE -ne 0) {
					$result.Outcome = "Conflict"
					if (-not $Quiet) { Write-LogError "Could not fast-forward [$currentBranch] - it has local commits origin does not, or the update would overwrite an ignored file. Nothing was changed." }
				}
				else {
					$result.Outcome = "Updated"
					if (-not $Quiet) { Write-LogSuccess "Updated repository" }
				}
			}
		}

		# 6. The default branch is fetched into directly and never checked out, so it is safe to
		# run whatever happened above and while the stash is still held.
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
				$result.DefaultBranchOutcome = Update-RepositoryDefaultBranch -DefaultBranch $defaultBranch -CurrentBranch $currentBranch -LocalPath $LocalPath -Quiet:$Quiet
			}
		}

		# 7. Give back exactly this run's stash.
		if ($stashCommit) {
			if (-not $Quiet) { Write-LogWarning "Attempting to restore stashed changes..." }
			$restore = Restore-RepositoryStash -StashCommit $stashCommit -Quiet:$Quiet
			if ($restore -eq "Restored") {
				$result.StashName = $null
				if (-not $Quiet) { Write-LogSuccess "Restored stashed changes!" }
			}
			elseif ($restore -eq "Missing") {
				# Something else applied or dropped it in the meantime (another shell's git stash
				# pop). Its changes went wherever that took them; nothing more to do here safely.
				$result.Outcome = "StashMissing"
				if (-not $Quiet) { Write-LogError "The stash [$($result.StashName)] was taken by another git command before it could be restored - check the working tree and [git stash list]" }
			}
			else {
				$result.Outcome = "StashConflict"
				if (-not $Quiet) {
					Write-LogError "Conflicts occurred while restoring stashed changes in [$Name]"
					Write-LogWarning "Changes are preserved in stash: $($result.StashName)"
					Write-LogWarning "Please resolve conflicts manually with [git stash list] and [git stash apply]" -NoLeadingNewline
				}
			}
		}
	}
	catch {
		$result.Outcome = "Error"
		Write-LogError "An error occurred while updating [$Name]: $_"
		# Whatever failed, a stash this run made must not be left behind silently.
		if ($stashCommit) {
			try {
				if ((Restore-RepositoryStash -StashCommit $stashCommit -Quiet:$Quiet) -eq "Restored") { $result.StashName = $null }
			}
			catch { }
			if ($result.StashName) { Write-LogWarning "Local changes are kept in stash => [$($result.StashName)]" }
		}
	}
	finally {
		Pop-Location
	}

	return $result
}
