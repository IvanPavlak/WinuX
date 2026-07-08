function Get-RepositoryName {
	<#
	.SYNOPSIS
		Extract repository name from Git URL.

	.DESCRIPTION
		Parses HTTPS, SSH, and SCP-style Git URLs to extract the repository name.
		Handles .git suffix removal and various URL formats.

	.PARAMETER RepositoryUrl
		The Git repository URL (e.g., 'https://github.com/user/repo.git' or 'git@github.com:user/repo.git').

	.EXAMPLE
		$name = Get-RepositoryName -RepositoryUrl "https://github.com/user/myrepo.git"
		Write-Host "Repo: $name"  # Output: myrepo
	#>
	param(
		[string]$RepositoryUrl
	)

	if ([string]::IsNullOrWhiteSpace($RepositoryUrl)) {
		Write-LogError "Repository URL is empty or null"
		return ""
	}

	try {
		if ($RepositoryUrl -match '^(?:https?|git)://|^git@') {
			# Handle HTTPS and SSH URLs
			$RepositoryName = $RepositoryUrl -replace '^.*[:/]([^/:]+?)(\.git)?$', '$1'
		}
		elseif ($RepositoryUrl -match '^[\w-]+@[\w.-]+:.+?') {
			# Handle SCP-style Git URLs
			$RepositoryName = $RepositoryUrl -replace '^.*:([^/]+?)(\.git)?$', '$1'
		}
		else {
			Write-LogError "Invalid or unsupported repository URL format"
			return ""
		}

		if ([string]::IsNullOrEmpty($RepositoryName)) {
			Write-LogError "Unable to extract repository name from '$RepositoryUrl'"
			return ""
		}

		return $RepositoryName
	}
	catch {
		Write-LogError "An error occurred while extracting the repository name. $_"
		return ""
	}
}
