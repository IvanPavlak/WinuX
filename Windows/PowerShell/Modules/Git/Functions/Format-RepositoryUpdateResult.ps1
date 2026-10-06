function Format-RepositoryUpdateResult {
	<#
	.SYNOPSIS
		Turns one repository update result into the one-line summary Update-Repositories -Quiet
		prints.

	.DESCRIPTION
		Takes the result object Update-Repository returns (or the ones Update-Repositories
		builds for repositories it skipped or cloned) and returns the line to print, the level
		to print it at, and the totals bucket it counts towards. Pure: it prints nothing.

		Example lines:

		  [MyRepo] feature/login - updated, master fast-forwarded
		  [MyRepo] feature/login - up to date, master up to date
		  [MyRepo] master - up to date
		  [MyRepo] feature/login - could not fast-forward, resolve manually
		  [MyRepo] not cloned on this machine - skipped

		Level is Warning, and Category is Attention, whenever the user has something to do: the
		fetch failed, the pull could not fast-forward, local changes could not be stashed or
		restored, an error occurred, or the default branch diverged, could not be fetched or
		could not be named. A checked-out branch that is not on origin is Skipped - a local
		branch has nothing to pull.
		Whenever the default-branch step ran for a branch other than the checked-out one, the
		line names it and says what happened ("master up to date", "no local master"), so
		silence never has to be interpreted. A default branch that has no local branch is not a
		problem and does not count as needing attention.

	.PARAMETER Result
		One update result: Name, Branch, Outcome, DefaultBranch, DefaultBranchOutcome, StashName.

	.OUTPUTS
		[pscustomobject] with Message (string), Level (Success or Warning) and Category
		(Updated, UpToDate, Attention or Skipped).

	.EXAMPLE
		Format-RepositoryUpdateResult -Result (Update-Repository -Name MyRepo -LocalPath "C:\Dev\MyRepo" -Quiet)
		The line Update-Repositories -Quiet would print for that repository.
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[object]$Result
	)

	$outcomeText = switch ($Result.Outcome) {
		"Updated" { "updated" }
		"UpToDate" { "up to date" }
		"Cloned" { "cloned" }
		"NoUpstream" { "not on origin, nothing to pull" }
		"FetchFailed" { "could not fetch from origin" }
		"Conflict" { "could not fast-forward, nothing changed - resolve manually" }
		"Detached" { "detached HEAD, nothing to pull" }
		"Busy" { "operation in progress, nothing touched" }
		"NotARepository" { "not the top of a git repository, nothing touched" }
		"StashFailed" { "local changes could not be stashed - skipped" }
		"StashConflict" { "local changes could not be restored cleanly and are kept in stash [$($Result.StashName)]" }
		"StashMissing" { "its stash was taken by another git command - check the working tree and git stash list" }
		"NotCloned" { "not cloned on this machine - skipped" }
		"NotConfigured" { "no local path on this machine - skipped" }
		default { "failed" }
	}

	$category = switch ($Result.Outcome) {
		{ $_ -in @("Updated", "Cloned") } { "Updated"; break }
		"UpToDate" { "UpToDate"; break }
		{ $_ -in @("NotCloned", "NotConfigured", "NoUpstream", "Detached") } { "Skipped"; break }
		default { "Attention" }
	}

	$defaultBranch = $Result.DefaultBranch
	# Whenever the default branch differs from the checked-out one, the line says what happened to
	# it - silence would read as "not checked". "Current" means they are the same branch.
	$defaultText = switch ($Result.DefaultBranchOutcome) {
		"Updated" { "$defaultBranch fast-forwarded" }
		"UpToDate" { "$defaultBranch up to date" }
		"Missing" { "no local $defaultBranch" }
		"Diverged" { "$defaultBranch has local commits, left untouched" }
		"Failed" { "$defaultBranch could not be fetched" }
		"Unresolved" { "default branch unknown" }
		default { $null }
	}
	if ($Result.DefaultBranchOutcome -in @("Diverged", "Failed", "Unresolved")) { $category = "Attention" }

	$message = if ([string]::IsNullOrWhiteSpace($Result.Branch)) {
		"[$($Result.Name)] $outcomeText"
	}
	else {
		"[$($Result.Name)] $($Result.Branch) - $outcomeText"
	}
	if ($defaultText) { $message += ", $defaultText" }

	return [pscustomobject]@{
		Message  = $message
		Level    = if ($category -eq "Attention") { "Warning" } else { "Success" }
		Category = $category
	}
}
