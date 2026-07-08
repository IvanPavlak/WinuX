function BranchExists {
	<#
	.SYNOPSIS
		Check if a Git branch exists.

	.DESCRIPTION
		Queries the local Git repository to determine if a branch with the specified name exists.
		Returns $true if the branch is found, $false otherwise.

	.PARAMETER Branch
		The name of the branch to check for existence.

	.EXAMPLE
		if (BranchExists -Branch "feature/my-feature") { Write-Host "Branch exists" }
	#>
	param( [string] $Branch )

	return (git branch --list $Branch | ForEach-Object { $_.Trim() }) -ne $null
}
