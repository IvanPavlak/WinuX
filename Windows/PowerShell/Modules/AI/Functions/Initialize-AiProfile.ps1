function Initialize-AiProfile {
	<#
	.SYNOPSIS
		Walks the one-time sign-ins of this machine's AI profile - the Claude Code login, the GitHub CLI, the OAuth MCP servers and the profile's environment variables - then runs Test-AiProfile.

	.DESCRIPTION
		Run once per machine after Bootstrap, at the keyboard. Every credential stays where its
		own tool keeps it: this function never asks for, reads, prints or stores a secret. It
		prints each step, starts the interactive login a tool offers, waits for Enter where the
		step happens elsewhere, and checks the result afterwards:

		  1. Claude Code: the logged-in Plan (oauthAccount of ~\.claude.json) is compared with
		     the profile's Plan. When it differs, the step says which Plan to sign in to (name
		     and org UUID) and how: claude, then /login with a Claude subscription account
		     (/logout first when another one is logged in). A long-lived token
		     (`claude setup-token`, CLAUDE_CODE_OAUTH_TOKEN) is never the answer.
		  2. GitHub CLI: `gh auth status`; when it is not signed in, `gh auth login` runs
		     interactively.
		  3. OAuth MCP servers: every server the profile registers (AiMcpServers.Servers,
		     filtered by the profile's McpServers) that signs in with OAuth (a Url without
		     BearerTokenEnvVar or an Authorization header) is listed with its sign-in: /mcp in
		     Claude Code, `codex mcp login <name>` in Codex.
		  4. Environment variables: every name in the profile's EnvVars is checked for presence
		     (process, user or machine environment; never its value). A missing one is listed
		     with the command to set it in the user environment, typed by you.
		  5. Test-AiProfile runs and its exit code is left in $LASTEXITCODE.

		With no AI profile configured it only says so. After it, the machine is ready for the
		unattended runs its profile allows.

	.PARAMETER Command
		The Claude Code CLI the steps tell you to run. Defaults to `claude`; it is never run.

	.PARAMETER GhCommand
		The GitHub CLI. Defaults to `gh`; tests pass a stub.

	.EXAMPLE
		Initialize-AiProfile
		Walks every sign-in this machine's AI profile needs, then checks the machine with Test-AiProfile.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$Command = 'claude',

		[Parameter()]
		[string]$GhCommand = 'gh'
	)

	$aiProfile = Resolve-AiProfile
	foreach ($message in @($aiProfile.Warnings)) { Write-LogWarning $message }
	if (-not $aiProfile.Enabled) {
		Write-LogWarning "No AI profile configured (AiProfiles) - there is nothing to initialize!"
		return
	}
	$selected = $aiProfile.Profile
	Write-LogTitle "Initializing AI Profile $($aiProfile.Name)"
	Write-LogStep "Picked by $($aiProfile.Source) (host $($aiProfile.HostName))"

	$statePath = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR ".claude.json" } else { Join-Path $env:USERPROFILE ".claude.json" }
	$readAccount = {
		if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
		try {
			$state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
			if ($state -is [System.Collections.IDictionary] -and $state['oauthAccount'] -is [System.Collections.IDictionary]) {
				return @{ OrgUuid = ([string]$state['oauthAccount']['organizationUuid']).ToLowerInvariant(); OrgName = [string]$state['oauthAccount']['organizationName'] }
			}
		}
		catch {
			Write-LogDebug "The Claude Code user state does not parse => $($_.Exception.Message)"
		}
		return $null
	}

	# --- 1. Claude Code login ------------------------------------------------------------------
	Write-LogTitle "Step 1: Claude Code login"
	$expected = @($selected.Plans | ForEach-Object { $_.OrgUuid })
	$planText = (@($selected.Plans | ForEach-Object { "$($_.Name) (org $($_.OrgUuid))" })) -join ' or '
	if ($expected.Count -eq 0) {
		Write-LogWarning "AiProfiles.Profiles.$($aiProfile.Name) names no Plan - sign in to the Plan this machine should use, then add it to the profile!"
	}
	$account = & $readAccount
	if ($account -and $expected -contains $account.OrgUuid) {
		Write-LogSuccess "Claude Code is logged in to the expected Plan [$($account.OrgName)]"
	}
	else {
		if ($account) { Write-LogWarning "Claude Code is logged in to [$($account.OrgName) $($account.OrgUuid)], not the expected Plan." }
		Write-LogStep "In another terminal run ``$Command``, type /logout if another account is signed in, then /login and choose the Claude subscription account of $(if ($planText) { $planText } else { 'the Plan this machine uses' })."
		Write-LogStep "Never use ``claude setup-token`` or CLAUDE_CODE_OAUTH_TOKEN: only a Plan login is allowed."
		Custom-ReadHost -PromptMessage "Press Enter once Claude Code is logged in... " | Out-Null
		$account = & $readAccount
		if ($account -and $expected -contains $account.OrgUuid) {
			Write-LogSuccess "Claude Code is logged in to the expected Plan [$($account.OrgName)]"
		}
		else {
			Write-LogWarning "Claude Code is still not logged in to the expected Plan - Test-AiProfile will report it."
		}
	}

	# --- 2. GitHub CLI -------------------------------------------------------------------------
	Write-LogTitle "Step 2: GitHub CLI"
	if (Get-Command -Name $GhCommand -ErrorAction SilentlyContinue) {
		$global:LASTEXITCODE = 0
		& $GhCommand auth status *> $null
		if ($LASTEXITCODE -eq 0) {
			Write-LogSuccess "The GitHub CLI is signed in"
		}
		else {
			Write-LogStep "Starting ``gh auth login`` - answer its questions in this terminal."
			$global:LASTEXITCODE = 0
			& $GhCommand auth login
			if ($LASTEXITCODE -eq 0) { Write-LogSuccess "The GitHub CLI is signed in" } else { Write-LogWarning "gh auth login did not finish (exit code $LASTEXITCODE) - run it again by hand." }
		}
	}
	else {
		Write-LogWarning "The GitHub CLI ($GhCommand) is not on PATH - install it (GitHub.cli) and run gh auth login."
	}

	# --- 3. OAuth MCP servers ------------------------------------------------------------------
	Write-LogTitle "Step 3: MCP server sign-ins"
	$mcp = Get-ConfigSetting -Path 'AiMcpServers' -Default @{}
	$servers = if ($mcp -is [hashtable] -and $mcp.Servers -is [hashtable]) { $mcp.Servers } else { @{} }
	$oauth = @()
	foreach ($name in ($servers.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
		$entry = $servers[$name]
		if ($entry -isnot [hashtable] -or -not $entry.Url) { continue }
		if ($null -ne $selected.McpServers -and @($selected.McpServers | Where-Object { $_ -eq $name }).Count -eq 0) { continue }
		$hasAuthHeader = $entry.Headers -is [hashtable] -and @($entry.Headers.Keys | Where-Object { [string]$_ -eq 'Authorization' }).Count -gt 0
		if ($entry.BearerTokenEnvVar -or $hasAuthHeader) { continue }
		$oauth += $name
	}
	if ($oauth.Count -eq 0) {
		Write-LogStep "The profile registers no OAuth MCP server."
	}
	else {
		Write-LogStep "Sign in to each once: run ``$Command``, type /mcp, pick the server and finish the sign-in in the browser (Codex: ``codex mcp login <name>``)."
		Write-LogList $oauth
		Custom-ReadHost -PromptMessage "Press Enter once every server is signed in... " | Out-Null
	}

	# --- 4. Environment variables --------------------------------------------------------------
	Write-LogTitle "Step 4: Environment variables"
	$isSet = {
		param([string]$Name)
		foreach ($scope in @('Process', 'User', 'Machine')) {
			if ([Environment]::GetEnvironmentVariable($Name, [EnvironmentVariableTarget]::$scope)) { return $true }
		}
		return $false
	}
	$variables = @($selected.EnvVars)
	if ($variables.Count -eq 0) {
		Write-LogStep "The profile names no environment variable."
	}
	else {
		$missing = @($variables | Where-Object { -not (& $isSet $_) })
		if ($missing.Count -eq 0) {
			Write-LogSuccess "Every environment variable of the profile is set => [$($variables -join ', ')]"
		}
		else {
			Write-LogStep "Set each missing variable yourself, in your own terminal (the value never passes through WinuX), then open a new shell:"
			Write-LogList @($missing | ForEach-Object { "[Environment]::SetEnvironmentVariable(`"$_`", `"<value>`", `"User`")" })
			Custom-ReadHost -PromptMessage "Press Enter once they are set... " | Out-Null
			$stillMissing = @($missing | Where-Object { -not (& $isSet $_) })
			if ($stillMissing.Count -eq 0) {
				Write-LogSuccess "Every environment variable of the profile is set"
			}
			else {
				Write-LogWarning "Still missing (a new shell sees variables set after this one started) => [$($stillMissing -join ', ')]"
			}
		}
	}

	# --- 5. Check --------------------------------------------------------------------------------
	Write-LogTitle "Step 5: Check"
	Test-AiProfile
}
