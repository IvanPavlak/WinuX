function Initialize-Repository {
	<#
	.SYNOPSIS
		Clones a repository to a local path, or pulls updates if it already exists.

	.DESCRIPTION
		If the target path does not exist, clones the repository from `RepositoryUrl`.
		If the target path already exists, runs `git pull` to fetch the latest changes.

		When a `Token` is provided, injects it into the HTTPS clone URL as
		`https://<token>@github.com/...` for authenticated access to private repositories.
		After a successful authenticated clone, the origin remote is reset to the
		credential-free URL - git would otherwise persist the token in plaintext in
		`.git/config` for the life of the clone. Future fetches authenticate via the
		Git credential manager.

		The Obsidian repository is cloned with `--depth 1` (shallow) due to its large history.
		All cloned repositories have `takeown` applied to set the current user as owner.

		Parent directories are created automatically via Initialize-Directory.

	.PARAMETER RepositoryUrl
		HTTPS URL of the repository to clone or update.

	.PARAMETER LocalPath
		Absolute local path where the repository should be cloned.

	.PARAMETER Token
		Personal access token for authenticated HTTPS cloning of private repositories.
		Used for the clone itself only: the saved origin remote is reset to the
		credential-free URL afterwards, so the token is never persisted or logged.

	.EXAMPLE
		Initialize-Repository -RepositoryUrl "https://github.com/user/repo" -LocalPath "C:\Dev\repo"
		Clones the public repository to the specified path.

	.EXAMPLE
		Initialize-Repository -RepositoryUrl "https://github.com/user/private-repo" -LocalPath "C:\Dev\private" -Token $pat
		Clones a private repository using a personal access token.
	#>
	param(
		[string]$RepositoryUrl,
		[string]$LocalPath,
		[string]$Token
	)

	$ParentPath = Split-Path -Path $LocalPath -Parent
	Initialize-Directory $ParentPath

	$RepositoryName = Get-RepositoryName -RepositoryUrl $RepositoryUrl

	if (-not (Test-Path $LocalPath)) {
		Write-LogTitle "Initializing [$RepositoryName] Repository"

		$SanitizedUrl = $RepositoryUrl -replace 'https:\/\/.*@', 'https://'
		$CloneUrl = if (-not [string]::IsNullOrWhiteSpace($Token)) {
			Write-LogStep "=> Cloning with authenticated URL!"

			$CleanToken = $Token.Trim()
			$SanitizedUrl.Replace("https://", "https://$($CleanToken)@")

		}
		else {
			$RepositoryUrl
		}

		Write-LogStep "  Cloning [$RepositoryName] to [$LocalPath]"

		if ($RepositoryName -eq "Obsidian") {
			git clone --depth 1 $CloneUrl $LocalPath
			try { takeown /f $LocalPath /r /d y | Out-Null } catch {}
		}
		else {
			git clone $CloneUrl $LocalPath
			try { takeown /f $LocalPath /r /d y | Out-Null } catch {}
		}

		# Never persist the token: git saves the clone URL verbatim as the origin remote
		# (.git/config, plaintext), where it would outlive the bootstrap and leak with any
		# `git remote -v`. Reset origin to the credential-free URL; future fetches
		# authenticate via the Git credential manager.
		if (-not [string]::IsNullOrWhiteSpace($Token) -and (Test-Path (Join-Path $LocalPath ".git"))) {
			git -C $LocalPath remote set-url origin $SanitizedUrl
			Write-LogStep "  Token removed from the saved remote (credential manager handles future auth)"
		}
	}
	else {
		Write-LogTitle "Updating [$RepositoryName] repository"
		Write-LogWarning "Repository [$RepositoryName] already exists at [$LocalPath]"
		Write-LogStep "Pulling latest changes..."
		Push-Location $LocalPath
		git pull
		Pop-Location
	}
}
