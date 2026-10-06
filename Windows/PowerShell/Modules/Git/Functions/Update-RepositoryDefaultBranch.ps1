function Update-RepositoryDefaultBranch {
	<#
	.SYNOPSIS
		Fast-forwards a repository's default branch without checking it out.

	.DESCRIPTION
		Brings the local default branch (for example `master`) up to date while another branch
		is checked out, by running

		  git fetch origin <default>:<default>

		The refspec has no leading `+`, so git itself refuses anything but a fast-forward, and a
		fetch into a branch that is not checked out never touches the working tree, the index or
		the stash. Local work is therefore never at risk, whatever state the tree is in.

		Returns one outcome:

		- Current   : the default branch IS the checked-out branch - nothing to do here, the
		              caller's normal pull already covers it.
		- Missing   : no local branch of that name. Skipped, never created.
		- UpToDate  : fetched, nothing new.
		- Updated   : fast-forwarded.
		- Diverged  : the local default branch has commits the remote does not, so git refused
		              the fast-forward. Left exactly as it was.
		- Failed    : the fetch failed for any other reason (offline, no remote, the branch is
		              checked out in another worktree).

		With -Quiet nothing is logged and git runs with --quiet and its stderr dropped; the
		caller reports the outcome. Otherwise each outcome is logged as one line.

	.PARAMETER DefaultBranch
		The default branch's name, typically from Resolve-RepositoryDefaultBranch.

	.PARAMETER CurrentBranch
		The checked-out branch (`git rev-parse --abbrev-ref HEAD`).

	.PARAMETER LocalPath
		The repository's working-tree path. Defaults to the current location.

	.PARAMETER Quiet
		Log nothing and silence git; the caller prints the outcome.

	.OUTPUTS
		[string] - Current, Missing, UpToDate, Updated, Diverged or Failed.

	.EXAMPLE
		Update-RepositoryDefaultBranch -DefaultBranch master -CurrentBranch feature/login
		Fast-forwards master from origin while feature/login stays checked out.

	.EXAMPLE
		Update-RepositoryDefaultBranch -DefaultBranch master -CurrentBranch master
		"Current" - nothing is run.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$DefaultBranch,

		[Parameter(Mandatory = $true)]
		[AllowEmptyString()]
		[string]$CurrentBranch,

		[Parameter(Mandatory = $false)]
		[string]$LocalPath = $PWD.Path,

		[Parameter(Mandatory = $false)]
		[switch]$Quiet
	)

	if ($DefaultBranch -eq $CurrentBranch) { return "Current" }

	git -C $LocalPath show-ref --verify --quiet "refs/heads/$DefaultBranch"
	if ($LASTEXITCODE -ne 0) {
		if (-not $Quiet) { Write-LogWarning "Default branch [$DefaultBranch] has no local branch - skipped" }
		return "Missing"
	}

	$before = git -C $LocalPath rev-parse --verify --quiet "refs/heads/$DefaultBranch"

	if (-not $Quiet) { Write-LogStep " Fast-forwarding default branch [$DefaultBranch]" }
	if ($Quiet) {
		git -C $LocalPath fetch --quiet origin "${DefaultBranch}:${DefaultBranch}" 2>$null
	}
	else {
		# To the console, never into this function's output: the caller reads the outcome string.
		git -C $LocalPath fetch origin "${DefaultBranch}:${DefaultBranch}" | Out-Host
	}
	$fetchExitCode = $LASTEXITCODE

	if ($fetchExitCode -ne 0) {
		# A rejected fast-forward and a failed fetch exit alike; the refs tell them apart. When the
		# local branch is not an ancestor of the remote-tracking one, the two have diverged.
		$remoteRef = "refs/remotes/origin/$DefaultBranch"
		git -C $LocalPath rev-parse --verify --quiet $remoteRef | Out-Null
		$remoteExists = ($LASTEXITCODE -eq 0)
		$outcome = "Failed"
		if ($remoteExists) {
			git -C $LocalPath merge-base --is-ancestor "refs/heads/$DefaultBranch" $remoteRef
			if ($LASTEXITCODE -eq 1) { $outcome = "Diverged" }
		}

		if (-not $Quiet) {
			if ($outcome -eq "Diverged") {
				Write-LogWarning "Default branch [$DefaultBranch] has local commits origin does not - left untouched"
			}
			else {
				Write-LogError "Failed to fetch default branch [$DefaultBranch]"
			}
		}
		return $outcome
	}

	$after = git -C $LocalPath rev-parse --verify --quiet "refs/heads/$DefaultBranch"
	if ("$before" -eq "$after") {
		if (-not $Quiet) { Write-LogSuccess "Default branch [$DefaultBranch] is already up to date!" }
		return "UpToDate"
	}

	if (-not $Quiet) { Write-LogSuccess "Default branch [$DefaultBranch] fast-forwarded" }
	return "Updated"
}
