function Test-AiProfile {
	<#
	.SYNOPSIS
		Checks that this machine runs Claude Code on the Plan its AI profile expects, pinned by the managed settings, with no pay-per-use credential anywhere.

	.DESCRIPTION
		Prints, read-only:

		  - the AI profile (Resolve-AiProfile) and how it was picked: override
		    (WINUX_AI_PROFILE), hostname (AiProfiles.Hosts) or default;
		  - the expected Plan (the profile's Plan: name and org UUID, one or several);
		  - the logged-in Plan: oauthAccount.organizationUuid and organizationName of the
		    Claude Code user state (~\.claude.json, or $env:CLAUDE_CONFIG_DIR\.claude.json);
		  - whether the deployed managed settings (the managed-settings destination of
		    AiHarnesses, C:\Program Files\ClaudeCode\managed-settings.json in the base) are a
		    copy, not a link, and pin exactly the expected UUIDs in forceLoginOrgUUID;
		  - every pay-per-use credential found: ANTHROPIC_API_KEY, ANTHROPIC_AUTH_TOKEN and
		    CLAUDE_CODE_OAUTH_TOKEN in the process, user and machine environment and assigned
		    in a shell profile (the PowerShell profiles, ~\.bashrc, ~\.bash_profile,
		    ~\.profile, ~\.zshrc), and apiKeyHelper in a Claude settings file (the user's
		    settings.json and settings.local.json, the managed settings and their
		    managed-settings.d drop-ins). Only names and places are printed, never a value;
		  - the OAuth MCP servers the profile registers (AiMcpServers.Servers, filtered by the
		    profile's McpServers) that sign in with OAuth (a Url without BearerTokenEnvVar or
		    an Authorization header), listed as "sign in once with /mcp, not checked". Whether
		    the sign-in is done is not checked (`claude mcp list` would start every stdio
		    server), and the line does not change the exit code.

		Sets $LASTEXITCODE: 0 when everything matches, 1 on any mismatch or credential found,
		2 when no AI profile is configured. -PassThru also returns the findings.

	.PARAMETER ShellProfile
		The shell profile files to scan for credentials. Defaults to the PowerShell profiles of
		$PROFILE and the bash and zsh start-up files in the user's home folder.

	.PARAMETER PassThru
		Returns @{ ExitCode; Profile; Source; Expected; LoggedIn; Pinned; Credentials;
		OAuthMcp; Problems }.

	.EXAMPLE
		Test-AiProfile
		Prints the profile, the expected and the logged-in Plan, the managed settings pin and any credential found.

	.EXAMPLE
		Test-AiProfile; if ($LASTEXITCODE -ne 0) { Write-Warning "This machine is not ready for unattended runs" }
		Uses the exit code in a script.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$ShellProfile,

		[Parameter()]
		[switch]$PassThru
	)

	Write-LogTitle "AI Profile Check"

	$findings = @{
		ExitCode    = 0
		Profile     = ''
		Source      = ''
		Expected    = @()
		LoggedIn    = $null
		Pinned      = @()
		Credentials = @()
		OAuthMcp    = @()
		Problems    = @()
	}

	$aiProfile = Resolve-AiProfile
	foreach ($message in @($aiProfile.Warnings)) { Write-LogWarning $message }
	if (-not $aiProfile.Enabled) {
		Write-LogWarning "No AI profile configured (AiProfiles.Profiles with a Default or a Hosts entry for [$($aiProfile.HostName)]) - nothing to check!"
		$findings.ExitCode = 2
		$global:LASTEXITCODE = 2
		if ($PassThru) { return $findings }
		return
	}

	$selected = $aiProfile.Profile
	$findings.Profile = $aiProfile.Name
	$findings.Source = $aiProfile.Source
	$findings.Expected = @($selected.Plans)
	Write-LogStep "Profile        : $($aiProfile.Name) (picked by $($aiProfile.Source), host $($aiProfile.HostName))"

	$expectedUuids = @($selected.Plans | ForEach-Object { $_.OrgUuid })
	foreach ($planError in @($selected.PlanErrors | Where-Object { $_ })) { $findings.Problems += $planError }
	if ($expectedUuids.Count -eq 0) {
		$findings.Problems += "The profile names no Plan (AiProfiles.Profiles.$($aiProfile.Name).Plan)"
		Write-LogStep "Expected Plan  : none configured"
	}
	else {
		Write-LogStep "Expected Plan  : $((@($selected.Plans | ForEach-Object { "$($_.Name) $($_.OrgUuid)" })) -join ', ')"
	}

	# --- Logged-in Plan ----------------------------------------------------------------------
	$statePath = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR ".claude.json" } else { Join-Path $env:USERPROFILE ".claude.json" }
	$account = $null
	if (Test-Path -LiteralPath $statePath -PathType Leaf) {
		try {
			$state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
			if ($state -is [System.Collections.IDictionary] -and $state['oauthAccount'] -is [System.Collections.IDictionary]) {
				$account = @{
					OrgUuid = ([string]$state['oauthAccount']['organizationUuid']).ToLowerInvariant()
					OrgName = [string]$state['oauthAccount']['organizationName']
				}
			}
		}
		catch {
			$findings.Problems += "The Claude Code user state does not parse => [$statePath]"
		}
	}
	$findings.LoggedIn = $account
	if (-not $account -or -not $account.OrgUuid) {
		Write-LogStep "Logged-in Plan : none (no oauthAccount in [$statePath])"
		$findings.Problems += "Claude Code is not logged in with a Plan - run claude and /login"
	}
	else {
		Write-LogStep "Logged-in Plan : $($account.OrgName) $($account.OrgUuid)"
		if ($expectedUuids.Count -gt 0 -and $expectedUuids -notcontains $account.OrgUuid) {
			$findings.Problems += "Claude Code is logged in to [$($account.OrgName)], not the expected Plan - /logout, then /login with the expected one"
		}
	}

	# --- Managed settings pin ------------------------------------------------------------------
	$managedPath = 'C:\Program Files\ClaudeCode\managed-settings.json'
	$harnesses = Get-ConfigSetting -Path 'AiHarnesses' -Default @{}
	if ($harnesses -is [hashtable]) {
		foreach ($harness in $harnesses.Values) {
			foreach ($destination in @($harness.Destinations)) {
				if ($destination -is [hashtable] -and @($destination.Hooks) -contains 'managed-settings' -and $destination.Path) {
					$managedPath = [string]$destination.Path
				}
			}
		}
	}
	$managedItem = Get-Item -LiteralPath $managedPath -Force -ErrorAction SilentlyContinue
	if (-not $managedItem) {
		Write-LogStep "Managed pin    : no managed settings at [$managedPath]"
		$findings.Problems += "No managed settings deployed - run Deploy-AiArtifacts"
	}
	elseif ($managedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
		Write-LogStep "Managed pin    : [$managedPath] is a link"
		$findings.Problems += "The managed settings are a link, not the administrator-owned copy - run Deploy-AiArtifacts"
	}
	else {
		try {
			$managed = [IO.File]::ReadAllText($managedPath) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
			$pinned = @($managed['forceLoginOrgUUID'] | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() })
			$findings.Pinned = $pinned
			Write-LogStep "Managed pin    : $(if ($pinned.Count -gt 0) { $pinned -join ', ' } else { 'none' })"
			$same = ($pinned.Count -eq $expectedUuids.Count) -and @($pinned | Where-Object { $expectedUuids -notcontains $_ }).Count -eq 0
			if (-not $same) {
				$findings.Problems += "The managed settings do not pin the expected Plan - run Deploy-AiArtifacts"
			}
		}
		catch {
			$findings.Problems += "The managed settings do not parse => [$managedPath]"
		}
	}

	# --- Pay-per-use credentials ----------------------------------------------------------------
	$names = @('ANTHROPIC_API_KEY', 'ANTHROPIC_AUTH_TOKEN', 'CLAUDE_CODE_OAUTH_TOKEN')
	foreach ($name in $names) {
		foreach ($scope in @('Process', 'User', 'Machine')) {
			if ([Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::$scope)) {
				$findings.Credentials += "$name in the $($scope.ToLowerInvariant()) environment"
			}
		}
	}
	if (-not $PSBoundParameters.ContainsKey('ShellProfile')) {
		$ShellProfile = @()
		if ($PROFILE) {
			foreach ($property in @('AllUsersAllHosts', 'AllUsersCurrentHost', 'CurrentUserAllHosts', 'CurrentUserCurrentHost')) {
				if ($PROFILE.PSObject.Properties[$property]) { $ShellProfile += [string]$PROFILE.$property }
			}
		}
		$documents = [Environment]::GetFolderPath('MyDocuments')
		if ($documents) {
			$ShellProfile += Join-Path $documents 'WindowsPowerShell\profile.ps1'
			$ShellProfile += Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
		}
		foreach ($file in @('.bashrc', '.bash_profile', '.profile', '.zshrc')) { $ShellProfile += Join-Path $env:USERPROFILE $file }
	}
	foreach ($file in @($ShellProfile | Where-Object { $_ } | Select-Object -Unique)) {
		if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
		$text = [IO.File]::ReadAllText($file)
		foreach ($name in $names) {
			$pattern = '(?m)(\$env:' + $name + '\s*=|SetEnvironmentVariable\(\s*[''"]' + $name + '[''"]|^\s*(export\s+|set\s+|setx\s+)?' + $name + '\s*=)'
			if ($text -match $pattern) { $findings.Credentials += "$name assigned in [$file]" }
		}
	}
	$settingsFiles = @(
		(Join-Path $env:USERPROFILE ".claude\settings.json"),
		(Join-Path $env:USERPROFILE ".claude\settings.local.json"),
		$managedPath
	)
	$dropIns = Join-Path (Split-Path -Parent $managedPath) 'managed-settings.d'
	if (Test-Path -LiteralPath $dropIns -PathType Container) {
		$settingsFiles += @(Get-ChildItem -LiteralPath $dropIns -File -Filter '*.json' | ForEach-Object { $_.FullName })
	}
	foreach ($file in $settingsFiles) {
		if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
		if ([IO.File]::ReadAllText($file) -match '"apiKeyHelper"\s*:') { $findings.Credentials += "apiKeyHelper in [$file]" }
	}
	if ($findings.Credentials.Count -eq 0) {
		Write-LogStep "Credentials    : none found"
	}
	else {
		Write-LogWarning "Pay-per-use credentials found (remove them - a Plan login is the only one allowed):"
		Write-LogList $findings.Credentials
	}

	# --- OAuth MCP servers: listed, never checked ------------------------------------------------
	# Whether a sign-in is done is not checked: `claude mcp list` would start every stdio server.
	$mcp = Get-ConfigSetting -Path 'AiMcpServers' -Default @{}
	$servers = if ($mcp -is [hashtable] -and $mcp.Servers -is [hashtable]) { $mcp.Servers } else { @{} }
	foreach ($name in ($servers.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
		$entry = $servers[$name]
		if ($entry -isnot [hashtable] -or -not $entry.Url) { continue }
		if ($null -ne $selected.McpServers -and @($selected.McpServers | Where-Object { $_ -eq $name }).Count -eq 0) { continue }
		$hasAuthHeader = $entry.Headers -is [hashtable] -and @($entry.Headers.Keys | Where-Object { [string]$_ -eq 'Authorization' }).Count -gt 0
		if ($entry.BearerTokenEnvVar -or $hasAuthHeader) { continue }
		$findings.OAuthMcp += $name
	}
	if ($findings.OAuthMcp.Count -gt 0) {
		Write-LogStep "MCP sign-ins   : sign in once with /mcp, not checked => [$($findings.OAuthMcp -join ', ')]"
	}

	if ($findings.Credentials.Count -gt 0) {
		$findings.Problems += "Pay-per-use credential(s) found"
	}
	if ($findings.Problems.Count -eq 0) {
		Write-LogSuccess "AI profile [$($aiProfile.Name)] matches: the expected Plan is logged in and pinned, and no pay-per-use credential was found!"
		$findings.ExitCode = 0
	}
	else {
		Write-LogError "AI profile [$($aiProfile.Name)] does not match:"
		Write-LogList $findings.Problems
		$findings.ExitCode = 1
	}
	$global:LASTEXITCODE = $findings.ExitCode
	if ($PassThru) { return $findings }
}
