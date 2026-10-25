function Deploy-AiMcpServers {
	<#
	.SYNOPSIS
		Adds the configured MCP servers to Claude Code and Codex, on Windows and inside WSL.

	.DESCRIPTION
		An MCP server is not an artifact Deploy-AiArtifacts can link: each app keeps its servers in
		its own configuration file, Claude Code in the user's ~\.claude.json and Codex in
		~\.codex\config.toml. This function writes them there, from one definition per server under
		AiMcpServers.Servers, into the apps AiMcpServers.Deploy names for this machine type:

		1. claude-code: with the Claude Code CLI on PATH, every server the mcpServers block of
		   ~\.claude.json ($env:CLAUDE_CONFIG_DIR\.claude.json when CLAUDE_CONFIG_DIR is set) does
		   not carry is added at user scope through `claude mcp add --scope user`, a server it
		   carries with another definition is removed (`claude mcp remove --scope user`) and added
		   again, and a server it carries as configured is left alone. The file is only read: the
		   CLI writes it. A missing CLI only warns.
		2. codex: the [mcp_servers.<name>] table of every server is written to Codex's config.toml
		   ($env:CODEX_HOME\config.toml when CODEX_HOME is set), replacing that table and its
		   subtables in place or appending it; every other line of the file is kept, comments
		   included. Codex reads only stdio and streamable HTTP servers, so an sse server is
		   skipped there with a warning.

		A server is either a Url (an HTTP server, or an SSE one with Transport "sse") with optional
		Headers and BearerTokenEnvVar, or a Command with optional Args and Env (a stdio server).
		Machine scopes a server to some machine types ("PC/Work"). Secrets never belong in the
		repository: BearerTokenEnvVar names the environment variable that holds the token, and is
		written as an `Authorization: Bearer ${VAR}` header, which Claude Code expands when it
		starts, and as Codex's bearer_token_env_var. A server that signs in with OAuth needs that
		sign-in once per machine and app (/mcp in Claude Code, `codex mcp login <name>`), because
		the tokens stay in the machine's own credential store.

		Servers are added and updated, never removed: a server taken out of the configuration stays
		in the apps until it is removed by hand.

		Inside WSL (DefaultWSLDistribution and DefaultWSLUsername set) the same servers reach the
		WSL user: the Codex tables are written to /home/<DefaultWSLUsername>/.codex/config.toml
		through the \\wsl.localhost share (an unreachable share only warns), and the Claude Code
		steps run again against the Claude Code CLI installed inside WSL, through
		`wsl -d <distro> -u <user>` and a login shell, comparing with that user's ~/.claude.json,
		which is read through WSL as well. A claude that WSL resolves under /mnt/ is the Windows CLI
		reached through interop, which would write the Windows profile, so it counts as missing
		there.

		Idempotent. Called by Bootstrap when the opt-in BootstrapConfig.Steps.AiMcpServers toggle is
		enabled (OFF by default); the base configuration names no servers, so a vanilla run deploys
		nothing.

	.PARAMETER Command
		The Claude Code CLI to call. Defaults to `claude`; tests pass a stub script.

	.PARAMETER WslCommand
		The WSL launcher to reach the Claude Code CLI inside WSL through. Defaults to `wsl`; tests
		pass a stub script.

	.EXAMPLE
		Deploy-AiMcpServers
		Adds every configured MCP server to the apps AiMcpServers.Deploy names, on Windows and inside WSL.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string]$Command = 'claude',

		[Parameter()]
		[string]$WslCommand = 'wsl'
	)

	Write-LogTitle "Deploying AI MCP Servers"

	$section = Get-ConfigSetting -Path 'AiMcpServers'
	if ($section -isnot [hashtable]) { $section = @{} }
	$servers = if ($section.Servers -is [hashtable]) { $section.Servers } else { @{} }

	if ($servers.Count -eq 0) {
		Write-LogWarning "No MCP servers configured under AiMcpServers.Servers - nothing to deploy!"
		return
	}

	# The apps this machine type deploys into: a per-machine-type hashtable with a Default
	# fallback, or one list for every machine type.
	$supported = @('claude-code', 'codex')
	$machineType = [string]$global:MachineType
	$deploy = @()
	if ($section.Deploy -is [hashtable]) {
		if ($machineType -and $section.Deploy.ContainsKey($machineType)) {
			$deploy = @($section.Deploy[$machineType])
		}
		elseif ($section.Deploy.ContainsKey('Default')) {
			$deploy = @($section.Deploy['Default'])
		}
	}
	elseif ($section.Deploy) {
		$deploy = @($section.Deploy)
	}
	$deploy = @($deploy | Where-Object { $_ } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Select-Object -Unique)
	foreach ($app in $deploy) {
		if ($supported -notcontains $app) {
			Write-LogWarning "AiMcpServers.Deploy names [$app], which WinuX cannot add MCP servers to (claude-code, codex) - skipped!"
		}
	}
	$deploy = @($deploy | Where-Object { $supported -contains $_ })
	if ($deploy.Count -eq 0) {
		Write-LogWarning "AiMcpServers.Deploy names no app for this machine type - nothing to deploy!"
		return
	}

	# A TOML basic string, for the Codex tables.
	$tomlString = {
		param([string]$Value)
		$escaped = $Value.Replace('\', '\\').Replace('"', '\"').Replace("`t", '\t').Replace("`n", '\n').Replace("`r", '\r')
		return "`"$escaped`""
	}

	# One comparable form of a Claude Code server entry, the configured one or the one read from
	# ~\.claude.json: an entry without a type is a stdio server, streamable-http is http.
	$canonical = {
		param($Entry)
		$sorted = {
			param($Value)
			$map = [ordered]@{}
			if ($Value -is [System.Collections.IDictionary]) {
				foreach ($key in ($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) { $map[$key] = [string]$Value[$key] }
			}
			return $map
		}
		$type = [string]$Entry['type']
		if (-not $type) { $type = 'stdio' }
		if ($type -eq 'streamable-http') { $type = 'http' }
		return ([ordered]@{
				type    = $type
				url     = [string]$Entry['url']
				headers = & $sorted $Entry['headers']
				command = [string]$Entry['command']
				args    = @($Entry['args'] | Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
				env     = & $sorted $Entry['env']
			} | ConvertTo-Json -Compress -Depth 4)
	}

	# Validated once: each server becomes its Claude Code entry and add arguments and its Codex
	# table.
	$valid = [ordered]@{}
	$usesOAuth = $false
	foreach ($name in ($servers.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
		$entry = $servers[$name]
		if ($name -notmatch '^[A-Za-z0-9_-]+$') {
			Write-LogError "MCP server [$name] has an invalid name (letters, digits, - and _ only) - skipped!"
			continue
		}
		if ($entry -isnot [hashtable]) {
			Write-LogError "AiMcpServers.Servers.$name is not a hashtable - skipped!"
			continue
		}
		if ($entry.Machine -and -not (Test-MachineTypeScope -Scope ([string]$entry.Machine) -Context "AiMcpServers.Servers.$name")) {
			Write-LogDebug "MCP server [$name] is scoped to [$($entry.Machine)] - not deployed on this machine type"
			continue
		}

		$problems = @()
		$url = [string]$entry.Url
		$serverCommand = [string]$entry.Command
		$transport = ([string]$entry.Transport).ToLowerInvariant()
		$bearer = [string]$entry.BearerTokenEnvVar
		$headers = [ordered]@{}
		$environment = [ordered]@{}
		$arguments = @()

		if ([bool]$url -eq [bool]$serverCommand) {
			$problems += "needs exactly one of Url and Command"
		}
		if ($url) {
			if ($url -notmatch '^https?://\S+$') { $problems += "has a Url that is not an http(s) address" }
			if (-not $transport) { $transport = 'http' }
			if ($transport -notin @('http', 'sse')) { $problems += "has a Transport other than http or sse" }
			if ($null -ne $entry.Env) { $problems += "has an Env, which only a Command server takes" }
			if ($null -ne $entry.Args) { $problems += "has Args, which only a Command server takes" }
			if ($null -ne $entry.Headers) {
				if ($entry.Headers -isnot [hashtable]) {
					$problems += "has Headers that are not a hashtable"
				}
				else {
					foreach ($header in ($entry.Headers.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
						if ($header -notmatch '^[A-Za-z0-9!#$%&''*+.^_`|~-]+$') {
							$problems += "names an invalid header [$header]"
							continue
						}
						$headers[$header] = [string]$entry.Headers[$header]
					}
				}
			}
			if ($bearer) {
				if ($bearer -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { $problems += "has an invalid BearerTokenEnvVar [$bearer]" }
				if (@($headers.Keys | Where-Object { $_ -eq 'Authorization' }).Count -gt 0) { $problems += "sets both BearerTokenEnvVar and an Authorization header" }
			}
		}
		elseif ($serverCommand) {
			if ($transport -and $transport -ne 'stdio') { $problems += "has a Transport, which only a Url server takes" }
			$transport = 'stdio'
			if ($null -ne $entry.Headers) { $problems += "has Headers, which only a Url server takes" }
			if ($bearer) { $problems += "has a BearerTokenEnvVar, which only a Url server takes" }
			if ($null -ne $entry.Args) { $arguments = @($entry.Args | ForEach-Object { [string]$_ }) }
			if ($null -ne $entry.Env) {
				if ($entry.Env -isnot [hashtable]) {
					$problems += "has an Env that is not a hashtable"
				}
				else {
					foreach ($variable in ($entry.Env.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
						if ($variable -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
							$problems += "names an invalid environment variable [$variable]"
							continue
						}
						$environment[$variable] = [string]$entry.Env[$variable]
					}
				}
			}
		}
		if ($problems.Count -gt 0) {
			foreach ($problem in $problems) { Write-LogError "MCP server [$name] $problem - skipped!" }
			continue
		}

		# Claude Code: the entry `claude mcp add` writes and the arguments that write it.
		if ($url) {
			$claudeHeaders = [ordered]@{}
			foreach ($header in $headers.Keys) { $claudeHeaders[$header] = $headers[$header] }
			if ($bearer) { $claudeHeaders['Authorization'] = "Bearer `${$bearer}" }
			$claudeEntry = @{ type = $transport; url = $url; headers = $claudeHeaders }
			$claudeAdd = @('mcp', 'add', '--scope', 'user', '--transport', $transport, $name, $url)
			foreach ($header in $claudeHeaders.Keys) { $claudeAdd += @('--header', "${header}: $($claudeHeaders[$header])") }
			if (-not $bearer -and -not $claudeHeaders.Contains('Authorization')) { $usesOAuth = $true }
		}
		else {
			$claudeEntry = @{ type = 'stdio'; command = $serverCommand; args = $arguments; env = $environment }
			$claudeAdd = @('mcp', 'add', '--scope', 'user', $name)
			foreach ($variable in $environment.Keys) { $claudeAdd += @('-e', "$variable=$($environment[$variable])") }
			$claudeAdd += @('--', $serverCommand) + $arguments
		}

		# Codex: the [mcp_servers.<name>] table, inline tables for the maps so it stays one table.
		$codexBlock = @("[mcp_servers.$name]")
		if ($url) {
			$codexBlock += "url = $(& $tomlString $url)"
			if ($bearer) { $codexBlock += "bearer_token_env_var = $(& $tomlString $bearer)" }
			if ($headers.Count -gt 0) {
				$pairs = @($headers.Keys | ForEach-Object { "$(& $tomlString $_) = $(& $tomlString $headers[$_])" })
				$codexBlock += "http_headers = { $($pairs -join ', ') }"
			}
		}
		else {
			$codexBlock += "command = $(& $tomlString $serverCommand)"
			if ($arguments.Count -gt 0) {
				$codexBlock += "args = [$((@($arguments | ForEach-Object { & $tomlString $_ })) -join ', ')]"
			}
			if ($environment.Count -gt 0) {
				$pairs = @($environment.Keys | ForEach-Object { "$(& $tomlString $_) = $(& $tomlString $environment[$_])" })
				$codexBlock += "env = { $($pairs -join ', ') }"
			}
		}

		$valid[$name] = @{
			Transport       = $transport
			ClaudeCanonical = & $canonical $claudeEntry
			ClaudeAdd       = $claudeAdd
			CodexBlock      = $codexBlock
		}
	}

	if ($valid.Count -eq 0) {
		Write-LogWarning "No MCP server to deploy on this machine type!"
		return
	}

	$codexNames = @()
	if ($deploy -contains 'codex') {
		foreach ($name in $valid.Keys) {
			if ($valid[$name].Transport -eq 'sse') {
				Write-LogWarning "MCP server [$name] is an sse server, which Codex does not read (stdio and streamable HTTP only) - not added to Codex!"
				continue
			}
			$codexNames += $name
		}
	}

	# The user-scope servers in the text of a ~/.claude.json: an empty map for a missing file or
	# block, $null for a file that does not parse. -AsHashtable, because the file can carry keys
	# that differ only in case (two spellings of one project path).
	$parseClaudeServers = {
		param([string]$Raw)
		if ([string]::IsNullOrWhiteSpace($Raw)) { return @{} }
		try {
			$document = $Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
		}
		catch {
			Write-LogDebug "Parsing the Claude Code user configuration failed => $($_.Exception.Message)"
			return $null
		}
		if ($document -isnot [System.Collections.IDictionary] -or $document['mcpServers'] -isnot [System.Collections.IDictionary]) { return @{} }
		return $document['mcpServers']
	}

	# The Claude Code half against one CLI: $Invoke runs it with the given arguments and leaves its
	# exit code in $LASTEXITCODE, $ReadState returns the text of that user's ~/.claude.json (empty
	# when there is none), so Windows and WSL share every check and message.
	$deployClaude = {
		param([string]$Label, [string]$Where, [scriptblock]$ReadState, [scriptblock]$Invoke)

		$current = & $parseClaudeServers ((@(& $ReadState) | ForEach-Object { [string]$_ }) -join "`n")
		if ($null -eq $current) {
			Write-LogError "${Label}The Claude Code user configuration (.claude.json) does not parse - its MCP servers were not deployed!"
			return
		}
		foreach ($name in $valid.Keys) {
			$present = $current.Contains($name)
			if ($present -and (& $canonical $current[$name]) -eq $valid[$name].ClaudeCanonical) {
				Write-LogStep "${Label}Claude Code MCP server [$name] already configured"
				continue
			}
			try {
				if ($present) {
					$global:LASTEXITCODE = 0
					& $Invoke mcp remove --scope user $name *> $null
					if ($LASTEXITCODE -ne 0) {
						Write-LogError "${Label}claude mcp remove --scope user [$name] failed (exit code $LASTEXITCODE) - run it by hand$Where to see why!"
						continue
					}
				}
				$addArguments = $valid[$name].ClaudeAdd
				$global:LASTEXITCODE = 0
				& $Invoke @addArguments *> $null
				if ($LASTEXITCODE -eq 0) {
					$verb = if ($present) { "Updated" } else { "Added" }
					Write-LogSuccess "${Label}$verb Claude Code MCP server [$name]"
				}
				else {
					Write-LogError "${Label}claude mcp add [$name] failed (exit code $LASTEXITCODE) - run it by hand$Where to see why!"
				}
			}
			catch {
				Write-LogError "${Label}claude mcp add [$name] threw => $($_.Exception.Message)"
			}
		}
	}

	# The Codex half against one config.toml: each server's table (its header line, the lines up to
	# the next table header and its subtables) is replaced in place or appended. Comment lines in
	# that stretch stay where they are, since they usually introduce the next table.
	$deployCodex = {
		param([string]$Label, [string]$Path)

		try {
			$text = if (Test-Path -LiteralPath $Path) { [System.IO.File]::ReadAllText($Path) } else { "" }
			$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
			$lines = [System.Collections.Generic.List[string]]::new()
			if ($text.Length -gt 0) {
				foreach ($line in ($text -split "`r?`n")) { $lines.Add($line) }
				if ($lines[$lines.Count - 1] -eq "") { $lines.RemoveAt($lines.Count - 1) }
			}

			$messages = @()
			foreach ($name in $codexNames) {
				$escapedName = [regex]::Escape($name)
				$header = '^\s*\[\s*mcp_servers\s*\.\s*(?:' + $escapedName + '|"' + $escapedName + '")\s*(?:\.[^\]]*)?\]\s*(?:#.*)?$'
				$kept = [System.Collections.Generic.List[string]]::new()
				$existing = @()
				$start = -1
				$inside = $false
				foreach ($line in $lines) {
					if ($line -match '^\s*\[') {
						$inside = $line -match $header
						if ($inside -and $start -lt 0) { $start = $kept.Count }
					}
					if (-not $inside -or $line -match '^\s*#') {
						$kept.Add($line)
					}
					elseif ($line.Trim()) {
						$existing += $line.Trim()
					}
				}

				$block = [string[]]$valid[$name].CodexBlock
				if ($start -ge 0 -and ($existing -join "`n") -eq ($block -join "`n")) {
					$messages += @{ Kind = 'Step'; Text = "${Label}Codex MCP server [$name] already configured" }
					continue
				}
				if ($start -ge 0) {
					$kept.InsertRange($start, [string[]]($block + ""))
					$messages += @{ Kind = 'Success'; Text = "${Label}Updated Codex MCP server [$name]" }
				}
				else {
					if ($kept.Count -gt 0 -and $kept[$kept.Count - 1].Trim()) { $kept.Add("") }
					$kept.AddRange($block)
					$messages += @{ Kind = 'Success'; Text = "${Label}Added Codex MCP server [$name]" }
				}
				$lines = $kept
			}

			if (@($messages | Where-Object { $_.Kind -eq 'Success' }).Count -gt 0) {
				$directory = Split-Path -Parent $Path
				if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
				[System.IO.File]::WriteAllText($Path, (($lines -join $newline) + $newline), [System.Text.UTF8Encoding]::new($false))
			}
			foreach ($message in $messages) {
				if ($message.Kind -eq 'Success') { Write-LogSuccess $message.Text } else { Write-LogStep $message.Text }
			}
		}
		catch {
			Write-LogError "${Label}Codex configuration [$Path] not updated => $($_.Exception.Message)"
		}
	}

	# Windows.
	$claudeState = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $env:CLAUDE_CONFIG_DIR ".claude.json" } else { Join-Path $env:USERPROFILE ".claude.json" }
	$codexConfig = if ($env:CODEX_HOME) { Join-Path $env:CODEX_HOME "config.toml" } else { Join-Path $env:USERPROFILE ".codex\config.toml" }
	if ($deploy -contains 'claude-code') {
		if (Get-Command -Name $Command -ErrorAction SilentlyContinue) {
			$readWindows = { if (Test-Path -LiteralPath $claudeState) { [System.IO.File]::ReadAllText($claudeState) } else { "" } }
			& $deployClaude -Label "" -Where "" -ReadState $readWindows -Invoke { & $Command @args }
		}
		else {
			Write-LogWarning "Claude Code CLI (claude) not found on PATH - its MCP servers are added once the Claude Code CLI is installed and this runs again!"
		}
	}
	if ($codexNames.Count -gt 0) {
		& $deployCodex -Label "" -Path $codexConfig
	}

	# WSL: the Codex file through the \\wsl.localhost share, the Claude Code CLI installed inside
	# WSL (its ~/.claude.json read through WSL itself, so the share is not needed for it).
	$distro = [string](Get-ConfigSetting -Path 'DefaultWSLDistribution' -Default '')
	$wslUser = [string](Get-ConfigSetting -Path 'DefaultWSLUsername' -Default '')
	if ($distro -and $wslUser -and (Test-WSLDistributionInstalled)) {
		if ($codexNames.Count -gt 0) {
			$wslHome = "\\wsl.localhost\$distro\home\$wslUser"
			if (Test-Path -LiteralPath $wslHome) {
				& $deployCodex -Label "[WSL] " -Path (Join-Path $wslHome ".codex\config.toml")
			}
			else {
				Write-LogWarning "WSL share for [$distro] unreachable - the Codex MCP servers were not added inside WSL!"
			}
		}
		if ($deploy -contains 'claude-code') {
			# A login shell, so the PATH a WSL user's profile sets (~/.local/bin, npm) is the one used.
			$invokeWsl = { & $WslCommand -d $distro -u $wslUser -e sh -lc 'PATH=$HOME/.local/bin:$PATH; exec claude "$@"' claude @args }
			$readWsl = { & $WslCommand -d $distro -u $wslUser -e sh -lc 'cat "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null; exit 0' 2>$null }
			$global:LASTEXITCODE = 0
			$resolved = try { ((& $WslCommand -d $distro -u $wslUser -e sh -lc 'PATH=$HOME/.local/bin:$PATH; command -v claude' 2>$null) -join "").Trim() } catch { "" }
			if ($LASTEXITCODE -ne 0 -or -not $resolved) {
				Write-LogWarning "Claude Code CLI (claude) not found inside WSL [$distro] - its MCP servers are added there once the Claude Code CLI is installed inside WSL!"
			}
			elseif ($resolved -like "/mnt/*") {
				Write-LogWarning "WSL [$distro] resolves claude to the Windows CLI [$resolved], which would write the Windows profile - install the Claude Code CLI inside WSL so its MCP servers are added there!"
			}
			else {
				& $deployClaude -Label "[WSL] " -Where " inside WSL" -ReadState $readWsl -Invoke $invokeWsl
			}
		}
	}

	if ($usesOAuth) {
		Write-LogStep "A server that signs in with OAuth needs it once per machine: /mcp in Claude Code, ``codex mcp login <name>`` in Codex"
	}
	Write-LogSuccess "AI MCP servers deployed!"
}
