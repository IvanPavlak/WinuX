function Initialize-Repository {
	<#
	.SYNOPSIS
		Clones a repository to a local path, or pulls updates if it already exists.

	.DESCRIPTION
		If the target path does not exist, clones the repository from `RepositoryUrl`.
		If the target path already exists, updates it with Update-Repository: local changes are
		stashed and restored, the branch is fast-forwarded only, and nothing that cannot be done
		without loss is attempted. (It used to run a plain `git pull`, which merges and silently
		overwrites ignored local files at paths upstream starts tracking.)

		When a `Token` is provided, injects it into the HTTPS clone URL as
		`https://<token>@github.com/...` for authenticated access to private repositories.
		After a successful authenticated clone, the origin remote is reset to the
		credential-free URL - git would otherwise persist the token in plaintext in
		`.git/config` for the life of the clone. Future fetches authenticate via the
		Git credential manager.

		A URL that a RepositoryGroups entry marks `Shallow = $true` is cloned with `--depth 1`, a
		clone that keeps its .git and can still commit and push (a repository with a large history).
		All cloned repositories have `takeown` applied to set the current user as owner.

		A URL that a RepositoryGroups entry marks `Hooks = "<folder>"` has its tracked git hooks
		turned on after the clone, and after the update of an existing clone: Sync-RepositoryHooks
		points the clone's `core.hooksPath` at that folder. A URL no entry marks is never touched.

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

	# What the RepositoryGroups entry of this URL asks for: a shallow clone, tracked hooks.
	# Compared without case, a user name, a trailing slash or `.git`: the configured URL and the
	# one this function was handed need not be spelled alike. Only marked entries are resolved.
	$urlKey = { param($Url) $Url -replace '^(\w+://)[^/]*@', '$1' -replace '/$' -replace '\.git$' }
	$shallow = $false
	$hooksPath = $null
	foreach ($repositoryGroup in @(Get-ConfigSetting -Path 'RepositoryGroups' -Default @())) {
		foreach ($repository in $repositoryGroup[@($repositoryGroup.Keys)[0]]) {
			if (-not $repository.Shallow -and [string]::IsNullOrWhiteSpace($repository.Hooks)) { continue }
			$resolvedRepo = Resolve-ProjectPath -ProjectName $repository.Name -ForRepository -RepositoryEntry $repository
			if ($resolvedRepo -and (& $urlKey $resolvedRepo.RepositoryUrl) -eq (& $urlKey $RepositoryUrl)) {
				if ($repository.Shallow) { $shallow = $true }
				if (-not [string]::IsNullOrWhiteSpace($repository.Hooks)) { $hooksPath = $repository.Hooks }
			}
		}
	}
	$hooksName = if ([string]::IsNullOrWhiteSpace($RepositoryName)) { Split-Path $LocalPath -Leaf } else { $RepositoryName }

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

		if ($shallow) {
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

		# A fresh clone of a repository marked with Hooks gets its tracked hooks turned on.
		if ($hooksPath -and (Test-Path (Join-Path $LocalPath ".git"))) {
			Sync-RepositoryHooks -Name $hooksName -LocalPath $LocalPath -HooksPath $hooksPath | Out-Null
		}
	}
	else {
		Write-LogTitle "Updating [$RepositoryName] repository"
		Write-LogWarning "Repository [$RepositoryName] already exists at [$LocalPath]"
		# Not a plain `git pull`: that merges whatever it fetched and silently overwrites an ignored
		# local file at a path upstream starts tracking. Update-Repository stashes and restores
		# local work, fast-forwards only, and refuses anything it cannot do without loss.
		Update-Repository -Name $hooksName -LocalPath $LocalPath | Out-Null

		# Set only: a URL no entry marks is left exactly as it is. Taking a value back when a
		# mark is removed is Update-Repositories' job, which knows the entry.
		if ($hooksPath) {
			Sync-RepositoryHooks -Name $hooksName -LocalPath $LocalPath -HooksPath $hooksPath | Out-Null
		}
	}
}
