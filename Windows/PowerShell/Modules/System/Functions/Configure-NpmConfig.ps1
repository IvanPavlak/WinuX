function Configure-NpmConfig {
	<#
    .SYNOPSIS
        Authenticates npm against the private registries in NpmRegistries.

    .DESCRIPTION
        Writes the auth token line (`//<host><path>:_authToken=<token>`) of every registry in
        `NpmRegistries` into the user npmrc (`MachineSpecificPaths.NpmConfig`, the expanded
        `PathTemplates.NpmConfig`), plus `<Scope>:registry=<Url>` for an entry with a Scope, so
        `npm install` of a private scoped package (GitHub Packages) authenticates.

        An entry is configured when the npmrc already has its auth key with a non-empty value
        and, with a Scope, its scope line pointing at the URL. When every entry is configured
        and `-Override` is not set, nothing changes. Otherwise the token (a GitHub personal
        access token with read:packages, the same one Configure-NuGetConfig asks for) is asked
        once as a secure string and used for every entry that needs it; an empty token, or one
        with whitespace in it (GitHub tokens have none), writes nothing. The token is never taken from the GitHub CLI, put on a command line or shown.

        Every other line of the npmrc is kept unchanged and in order; an existing auth or scope
        line of an entry is replaced in place, a missing one is appended. The file keeps its line
        endings (LF for a new file) and is written as UTF-8 without a BOM. An existing real
        (non-symlink) npmrc is first copied into the backup sink (Backup-RepositoryItem, category
        System, key NpmConfig) with every credential value (_authToken, _auth, _password)
        replaced by <redacted>, so the undo keeps the other settings but never a token; if that
        backup fails the write is skipped. An empty
        `NpmRegistries` warns and returns.

    .PARAMETER Override
        Ask for the token and rewrite every registry's lines even when they are already set.

    .PARAMETER BackupRoot
        Root of the unified backup sink an existing real npmrc is copied into before it is
        changed. Defaults to <Repo>\Backups\Windows resolved inside Backup-RepositoryItem.

    .EXAMPLE
        Configure-NpmConfig
        Asks for the token only when a registry in NpmRegistries is not configured yet.

    .EXAMPLE
        Configure-NpmConfig -Override
        Replaces the token of every registry, e.g. after rotating it.
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[switch]$Override,

		[string]$BackupRoot = ""
	)

	Write-LogTitle "npm Config Setup"

	$npmrcPath = $MachineSpecificPaths.NpmConfig
	if ([string]::IsNullOrWhiteSpace($npmrcPath)) {
		Write-LogError "PathTemplates.NpmConfig is not set - no npmrc to write!"
		return
	}

	$registries = @(Get-ConfigSetting -Path 'NpmRegistries' -Default @())
	if ($registries.Count -eq 0) {
		Write-LogWarning "No registries in NpmRegistries - nothing to configure"
		return
	}

	# Each entry becomes its wanted lines: the auth key derived from the URL without its scheme
	# (https://npm.pkg.github.com/ => //npm.pkg.github.com/:_authToken) and, with a Scope, the
	# scope line routing that scope's packages to the registry.
	$entries = @()
	foreach ($registry in $registries) {
		$url = [string]$registry.Url
		if ($url -notmatch '^https?://[^/\s]+') {
			Write-LogWarning "Skipped npm registry with an invalid Url => [$url]"
			continue
		}
		$url = $url.TrimEnd('/') + '/'
		$scope = [string]$registry.Scope
		$entries += [PSCustomObject]@{
			Url      = $url
			Scope    = $scope
			AuthKey  = ($url -replace '^https?:', '') + ':_authToken'
			ScopeKey = if ($scope) { "${scope}:registry" } else { "" }
		}
	}
	if ($entries.Count -eq 0) {
		Write-LogWarning "No valid registries in NpmRegistries - nothing to configure"
		return
	}

	$existingItem = Get-Item -LiteralPath $npmrcPath -Force -ErrorAction SilentlyContinue
	$content = if ($existingItem) { [System.IO.File]::ReadAllText($npmrcPath) } else { "" }
	$newline = if ($content -match "`r`n") { "`r`n" } else { "`n" }
	$lines = [System.Collections.Generic.List[string]]::new()
	if ($content) {
		foreach ($line in ($content -split "`r?`n")) { $lines.Add($line) }
		# A trailing newline leaves one empty element after the split; it is written back below.
		if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") { $lines.RemoveAt($lines.Count - 1) }
	}
	$originalLines = @($lines)

	# The value of each key in the npmrc (`key=value`, spaces around = allowed); the last line wins,
	# as in npm. Line indexes are kept so a key is replaced where it stands.
	$values = @{}
	$indexes = @{}
	for ($i = 0; $i -lt $lines.Count; $i++) {
		if ($lines[$i] -match '^\s*([^#;=\s][^=]*?)\s*=\s*(.*?)\s*$') {
			$values[$Matches[1]] = $Matches[2]
			$indexes[$Matches[1]] = $i
		}
	}

	$pending = @($entries | Where-Object {
			$configured = -not [string]::IsNullOrWhiteSpace($values[$_.AuthKey]) -and
			(-not $_.ScopeKey -or ([string]$values[$_.ScopeKey]).TrimEnd('/') -eq $_.Url.TrimEnd('/'))
			$Override -or -not $configured
		})
	if ($pending.Count -eq 0) {
		Write-LogSuccess "npm config is already configured for every registry => [$npmrcPath]"
		return
	}

	$secureToken = Custom-ReadHost "`nEnter GitHub Personal Access Token (PAT) with read:packages: " -AsSecureString -AddNewLine:$false
	$token = ""
	if ($secureToken -is [System.Security.SecureString] -and $secureToken.Length -gt 0) {
		$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)
		try {
			$token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
		}
		finally {
			[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
		}
	}
	if ([string]::IsNullOrWhiteSpace($token)) {
		Write-LogError "Token cannot be empty - npm config not changed"
		return
	}
	# GitHub tokens have no whitespace: one that does is something else pasted by mistake.
	if ($token -match '\s') {
		Write-LogError "A token has no spaces - that looks like something else pasted - npm config not changed"
		return
	}

	foreach ($entry in $pending) {
		$wanted = [ordered]@{ $entry.AuthKey = $token }
		if ($entry.ScopeKey) { $wanted[$entry.ScopeKey] = $entry.Url }
		foreach ($key in $wanted.Keys) {
			if ($indexes.ContainsKey($key)) {
				$lines[$indexes[$key]] = "$key=$($wanted[$key])"
			}
			else {
				$lines.Add("$key=$($wanted[$key])")
				$indexes[$key] = $lines.Count - 1
			}
		}
	}

	# The npmrc may hold settings of registries NpmRegistries knows nothing about; keep an undo in
	# the gitignored backup sink before changing it. A backup that cannot be taken aborts the write.
	# Its credentials are redacted: a copy of a token is a second place it leaks from, and a token
	# is asked again anyway. The redacted copy is made in a temporary folder and removed after.
	if ($existingItem -and -not $existingItem.LinkType) {
		$redactedDir = Join-Path ([System.IO.Path]::GetTempPath()) ("npmrc-" + [guid]::NewGuid().ToString("N"))
		try {
			New-Item -Path $redactedDir -ItemType Directory -Force | Out-Null
			$redactedPath = Join-Path $redactedDir (Split-Path $npmrcPath -Leaf)
			$redacted = foreach ($line in $originalLines) {
				if ($line -match '^([^=]*(_authToken|_auth|_password))\s*=') { "$($Matches[1].TrimEnd())=<redacted>" } else { $line }
			}
			[System.IO.File]::WriteAllText($redactedPath, ((@($redacted) -join $newline) + $newline), [System.Text.UTF8Encoding]::new($false))
			$backupDir = Backup-RepositoryItem -Path $redactedPath -Category "System" -Key "NpmConfig" -BackupRoot $BackupRoot
			Write-LogWarning "Backed up existing npmrc, tokens redacted => [$npmrcPath] => [$backupDir]"
		}
		catch {
			Write-LogError "Skipped npm config (could not back up the existing file) => [$npmrcPath] => $($_.Exception.Message)"
			return
		}
		finally {
			Remove-Item -LiteralPath $redactedDir -Recurse -Force -ErrorAction SilentlyContinue
		}
	}

	$directory = Split-Path $npmrcPath -Parent
	if ($directory -and -not (Test-Path -LiteralPath $directory)) {
		New-Item -Path $directory -ItemType Directory -Force | Out-Null
	}
	[System.IO.File]::WriteAllText($npmrcPath, (($lines -join $newline) + $newline), [System.Text.UTF8Encoding]::new($false))

	foreach ($entry in $pending) {
		Write-LogSuccess "npm registry configured => [$($entry.Url)]$(if ($entry.Scope) { " for [$($entry.Scope)]" })"
	}
	Write-LogSuccess "npm config written => [$npmrcPath]"
}
