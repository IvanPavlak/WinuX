function Resolve-RepositoryDefaultBranch {
	<#
	.SYNOPSIS
		Resolves the name of a repository's default branch.

	.DESCRIPTION
		Answers "which branch is the default one" for the default-branch step of
		Update-Repository, in this order:

		1. `RepositoryUpdate.DefaultBranch` from configuration, when it is not empty. One name
		   for every repository - set it only when all of them share it.
		2. What the remote reports: `refs/remotes/origin/HEAD`, the symbolic ref `git clone`
		   writes, read with `git symbolic-ref` and returned without its `origin/` prefix.
		3. $null - the caller skips the default-branch step and says why.

		Read-only: nothing is fetched and no ref is written. A repository cloned by something
		other than `git clone` may carry no `origin/HEAD`; `git remote set-head origin --auto`
		writes it once.

	.PARAMETER LocalPath
		The repository's working-tree path. Defaults to the current location.

	.OUTPUTS
		[string] - the branch name, or $null when neither source names one.

	.EXAMPLE
		Resolve-RepositoryDefaultBranch -LocalPath "C:\Dev\MyRepo"
		"master" when the remote's HEAD points at master and the configuration names none.

	.EXAMPLE
		Resolve-RepositoryDefaultBranch
		The default branch of the repository the shell stands in.
	#>
	[CmdletBinding()]
	[OutputType([string])]
	param(
		[Parameter(Mandatory = $false, Position = 0)]
		[string]$LocalPath = $PWD.Path
	)

	$configured = [string](Get-ConfigSetting -Path 'RepositoryUpdate.DefaultBranch' -Default '')
	if (-not [string]::IsNullOrWhiteSpace($configured)) {
		return $configured.Trim()
	}

	# --quiet makes a missing symbolic ref a plain non-zero exit instead of a fatal message.
	$remoteHead = git -C $LocalPath symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>$null
	if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$remoteHead")) {
		return $null
	}

	return ("$remoteHead".Trim() -replace '^origin/', '')
}
