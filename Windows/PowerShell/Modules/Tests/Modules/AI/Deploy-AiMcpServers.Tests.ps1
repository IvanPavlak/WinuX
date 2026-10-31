#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Deploy-AiMcpServers.ps1"
	. "$FunctionsPath\Resolve-AiProfile.ps1"
	# The machine-scope gate is dot-sourced so the Machine key is exercised for real.
	. (Join-Path (Get-RepositoryPath).Modules "Bootstrap\Functions\Test-MachineTypeScope.ps1")
}

Describe "Deploy-AiMcpServers" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }

		# Both apps' files are derived from the user profile, so the profile points into TestDrive.
		$script:TestHome = Join-Path $TestDrive "home"
		if (Test-Path -Path $script:TestHome) { Remove-Item -Path $script:TestHome -Recurse -Force }
		New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
		$script:ClaudeState = Join-Path $script:TestHome ".claude.json"
		$script:CodexConfig = Join-Path $script:TestHome ".codex\config.toml"
		$script:SavedUserProfile = $env:USERPROFILE
		$script:SavedCodexHome = $env:CODEX_HOME
		$script:SavedClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
		$env:USERPROFILE = $script:TestHome
		# The state file lives under LOCALAPPDATA, so that points into TestDrive as well.
		$script:SavedLocalAppData = $env:LOCALAPPDATA
		$env:LOCALAPPDATA = Join-Path $script:TestHome "AppData\Local"
		$script:StateFile = Join-Path $env:LOCALAPPDATA "WinuX\ai-mcp-servers.state"
		# Profiles off unless a test turns one on.
		Mock Resolve-AiProfile { @{ Enabled = $false; Warnings = @() } }
		Remove-Item -Path Env:\CODEX_HOME -ErrorAction SilentlyContinue
		Remove-Item -Path Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

		$script:SavedMachineType = $global:MachineType
		$global:MachineType = "PC"
		$script:Section = @{
			Deploy  = @{ Default = @("claude-code", "codex") }
			Servers = @{
				linear = @{ Url = "https://mcp.linear.app/mcp" }
			}
		}
		Mock Get-ConfigSetting {
			switch ($Path) {
				'AiMcpServers' { $script:Section }
				'DefaultWSLDistribution' { "" }
				default { $null }
			}
		}
		Mock Test-WSLDistributionInstalled { $false }

		# A stand-in CLI: records every call, one argument per |-separated field.
		$script:Log = Join-Path $TestDrive "calls.log"
		if (Test-Path -Path $script:Log) { Remove-Item -Path $script:Log -Force }
		$script:Stub = Join-Path $TestDrive "claude-stub.ps1"
		Set-Content -Path $script:Stub -Value @(
			"Add-Content -Path '$script:Log' -Value (`$args -join '|')",
			"if ((`$args -join ' ') -like '*broken*') { exit 1 }",
			"exit 0"
		)
	}

	AfterEach {
		$global:MachineType = $script:SavedMachineType
		$env:USERPROFILE = $script:SavedUserProfile
		$env:LOCALAPPDATA = $script:SavedLocalAppData
		if ($script:SavedCodexHome) { $env:CODEX_HOME = $script:SavedCodexHome } else { Remove-Item -Path Env:\CODEX_HOME -ErrorAction SilentlyContinue }
		if ($script:SavedClaudeConfigDir) { $env:CLAUDE_CONFIG_DIR = $script:SavedClaudeConfigDir } else { Remove-Item -Path Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
	}

	Context "Claude Code" {
		It "adds a server ~/.claude.json does not carry at user scope" {
			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Be @("mcp|add|--scope|user|--transport|http|linear|https://mcp.linear.app/mcp")
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Added Claude Code MCP server [linear]" }
		}

		It "leaves a server carried as configured alone" {
			Set-Content -Path $script:ClaudeState -Value '{"projects":{"C:/x":{},"c:/x":{}},"mcpServers":{"linear":{"type":"http","url":"https://mcp.linear.app/mcp"}}}'

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:Log | Should -BeFalse -Because "a matching entry needs no CLI call, and keys differing only in case must not break the read"
			Should -Invoke Write-LogStep -ParameterFilter { $Message -eq "Claude Code MCP server [linear] already configured" }
		}

		It "removes and adds again a server carried with another definition" {
			Set-Content -Path $script:ClaudeState -Value '{"mcpServers":{"linear":{"type":"http","url":"https://old.example.com/mcp"}}}'

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Be @(
				"mcp|remove|--scope|user|linear",
				"mcp|add|--scope|user|--transport|http|linear|https://mcp.linear.app/mcp"
			)
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Updated Claude Code MCP server [linear]" }
		}

		It "passes the headers and turns BearerTokenEnvVar into an Authorization header that names the variable" {
			$script:Section.Servers = @{
				keyed = @{ Url = "https://api.example.com/mcp"; Headers = @{ "X-Project" = "MyProject" }; BearerTokenEnvVar = "MY_API_KEY" }
			}

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Be @('mcp|add|--scope|user|--transport|http|keyed|https://api.example.com/mcp|--header|X-Project: MyProject|--header|Authorization: Bearer ${MY_API_KEY}')
		}

		It "adds a stdio server with its variables and arguments after --" {
			$script:Section.Servers = @{
				local = @{ Command = "npx"; Args = @("-y", "my-mcp-server"); Env = @{ LOG_LEVEL = "info" } }
			}

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Be @("mcp|add|--scope|user|local|-e|LOG_LEVEL=info|--|npx|-y|my-mcp-server")
		}

		It "matches a stdio entry written without a type" {
			$script:Section.Servers = @{ local = @{ Command = "npx"; Args = @("-y", "my-mcp-server") } }
			Set-Content -Path $script:ClaudeState -Value '{"mcpServers":{"local":{"command":"npx","args":["-y","my-mcp-server"],"env":{}}}}'

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:Log | Should -BeFalse
		}

		It "reports a failed add and keeps going" {
			$script:Section.Servers.broken = @{ Url = "https://broken.example.com/mcp" }

			Deploy-AiMcpServers -Command $script:Stub

			Should -Invoke Write-LogError -ParameterFilter { $Message -like "claude mcp add [[]broken] failed*" }
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Added Claude Code MCP server [linear]" }
		}

		It "deploys nothing to Claude Code when ~/.claude.json does not parse" {
			Set-Content -Path $script:ClaudeState -Value '{ not json'

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:Log | Should -BeFalse
			Should -Invoke Write-LogError -ParameterFilter { $Message -like "*does not parse*" }
			Test-Path -Path $script:CodexConfig | Should -BeTrue -Because "Codex is deployed regardless"
		}

		It "reads ~/.claude.json from CLAUDE_CONFIG_DIR when it is set" {
			$configDir = Join-Path $TestDrive "claude-config"
			New-Item -ItemType Directory -Path $configDir -Force | Out-Null
			Set-Content -Path (Join-Path $configDir ".claude.json") -Value '{"mcpServers":{"linear":{"type":"http","url":"https://mcp.linear.app/mcp"}}}'
			$env:CLAUDE_CONFIG_DIR = $configDir

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:Log | Should -BeFalse
		}

		It "only warns when the Claude Code CLI is missing, and still writes Codex" {
			Deploy-AiMcpServers -Command "winux-test-no-such-claude"

			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "Claude Code CLI (claude) not found on PATH*" }
			Test-Path -Path $script:CodexConfig | Should -BeTrue
		}
	}

	Context "Codex" {
		It "writes a new table for each server" {
			$script:Section.Servers = @{
				linear = @{ Url = "https://mcp.linear.app/mcp" }
				keyed  = @{ Url = "https://api.example.com/mcp"; Headers = @{ "X-Project" = "MyProject" }; BearerTokenEnvVar = "MY_API_KEY" }
				local  = @{ Command = "C:\Tools\server.exe"; Args = @("--port", "8080"); Env = @{ LOG_LEVEL = "info" } }
			}

			Deploy-AiMcpServers -Command $script:Stub

			$text = Get-Content -Path $script:CodexConfig -Raw
			$text | Should -Match ([regex]::Escape("[mcp_servers.keyed]`nurl = `"https://api.example.com/mcp`"`nbearer_token_env_var = `"MY_API_KEY`"`nhttp_headers = { `"X-Project`" = `"MyProject`" }"))
			$text | Should -Match ([regex]::Escape("[mcp_servers.linear]`nurl = `"https://mcp.linear.app/mcp`""))
			$text | Should -Match ([regex]::Escape("[mcp_servers.local]`ncommand = `"C:\\Tools\\server.exe`"`nargs = [`"--port`", `"8080`"]`nenv = { `"LOG_LEVEL`" = `"info`" }"))
		}

		It "keeps every other line and replaces the server's table and subtables in place" {
			New-Item -ItemType Directory -Path (Split-Path -Parent $script:CodexConfig) -Force | Out-Null
			Set-Content -Path $script:CodexConfig -NoNewline -Value (@(
					'model = "gpt-5"',
					'',
					'[mcp_servers.linear]',
					'url = "https://old.example.com/mcp"',
					'',
					'[mcp_servers.linear.env]',
					'OLD = "1"',
					'',
					'# The GitHub server',
					'[mcp_servers.github]',
					'url = "https://api.githubcopilot.com/mcp/"',
					''
				) -join "`n")

			Deploy-AiMcpServers -Command $script:Stub

			Get-Content -Path $script:CodexConfig -Raw | Should -Be (@(
					'model = "gpt-5"',
					'',
					'[mcp_servers.linear]',
					'url = "https://mcp.linear.app/mcp"',
					'',
					'# The GitHub server',
					'[mcp_servers.github]',
					'url = "https://api.githubcopilot.com/mcp/"',
					''
				) -join "`n")
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "Updated Codex MCP server [linear]" }
		}

		It "leaves the file untouched when every table is already as configured" {
			Deploy-AiMcpServers -Command $script:Stub
			$before = Get-Content -Path $script:CodexConfig -Raw
			(Get-Item -Path $script:CodexConfig).LastWriteTimeUtc = [datetime]::new(2000, 1, 1)

			Deploy-AiMcpServers -Command $script:Stub

			Get-Content -Path $script:CodexConfig -Raw | Should -Be $before
			(Get-Item -Path $script:CodexConfig).LastWriteTimeUtc | Should -Be ([datetime]::new(2000, 1, 1))
			Should -Invoke Write-LogStep -ParameterFilter { $Message -eq "Codex MCP server [linear] already configured" }
		}

		It "keeps the file's CRLF line endings" {
			New-Item -ItemType Directory -Path (Split-Path -Parent $script:CodexConfig) -Force | Out-Null
			[System.IO.File]::WriteAllText($script:CodexConfig, "model = `"gpt-5`"`r`n")

			Deploy-AiMcpServers -Command $script:Stub

			[System.IO.File]::ReadAllText($script:CodexConfig) | Should -Be "model = `"gpt-5`"`r`n`r`n[mcp_servers.linear]`r`nurl = `"https://mcp.linear.app/mcp`"`r`n"
		}

		It "writes to CODEX_HOME when it is set" {
			$env:CODEX_HOME = Join-Path $TestDrive "codex-home"

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path (Join-Path $env:CODEX_HOME "config.toml") | Should -BeTrue
			Test-Path -Path $script:CodexConfig | Should -BeFalse
		}

		It "skips an sse server for Codex but adds it to Claude Code" {
			$script:Section.Servers = @{ events = @{ Url = "https://events.example.com/sse"; Transport = "sse" } }

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:CodexConfig | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "MCP server [[]events] is an sse server*" }
			@(Get-Content -Path $script:Log) | Should -Be @("mcp|add|--scope|user|--transport|sse|events|https://events.example.com/sse")
		}
	}

	Context "selection" {
		It "deploys only into the apps Deploy names for this machine type" {
			$script:Section.Deploy = @{ Default = @("claude-code", "codex"); Work = @("claude-code") }
			$global:MachineType = "Work"

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:CodexConfig | Should -BeFalse
			@(Get-Content -Path $script:Log).Count | Should -Be 1
		}

		It "takes one array for every machine type and warns about an app it cannot write" {
			$script:Section.Deploy = @("codex", "gemini-cli")

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:CodexConfig | Should -BeTrue
			Test-Path -Path $script:Log | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "AiMcpServers.Deploy names [[]gemini-cli]*" }
		}

		It "skips a server scoped to other machine types" {
			$script:Section.Servers.worktool = @{ Url = "https://work.example.com/mcp"; Machine = "Work/Laptop" }

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Not -Contain "mcp|add|--scope|user|--transport|http|worktool|https://work.example.com/mcp"
			Get-Content -Path $script:CodexConfig -Raw | Should -Not -Match "worktool"
		}

		It "skips an invalid server with every reason and deploys the rest" {
			$script:Section.Servers.both = @{ Url = "https://x.example.com/mcp"; Command = "npx" }
			$script:Section.Servers."bad name" = @{ Url = "https://x.example.com/mcp" }
			$script:Section.Servers.keyed = @{ Url = "https://x.example.com/mcp"; BearerTokenEnvVar = "K"; Headers = @{ Authorization = "Bearer x" } }
			$script:Section.Servers.local = @{ Command = "npx"; Headers = @{ A = "b" } }

			Deploy-AiMcpServers -Command $script:Stub

			Should -Invoke Write-LogError -ParameterFilter { $Message -eq "MCP server [both] needs exactly one of Url and Command - skipped!" }
			Should -Invoke Write-LogError -ParameterFilter { $Message -like "MCP server [[]bad name] has an invalid name*" }
			Should -Invoke Write-LogError -ParameterFilter { $Message -eq "MCP server [keyed] sets both BearerTokenEnvVar and an Authorization header - skipped!" }
			Should -Invoke Write-LogError -ParameterFilter { $Message -eq "MCP server [local] has Headers, which only a Url server takes - skipped!" }
			@(Get-Content -Path $script:Log) | Should -Be @("mcp|add|--scope|user|--transport|http|linear|https://mcp.linear.app/mcp")
		}

		It "does nothing when no server is configured" {
			$script:Section = @{ Deploy = @{ Default = @("claude-code", "codex") } }

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:Log | Should -BeFalse
			Test-Path -Path $script:CodexConfig | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "No MCP servers configured*" }
		}

		It "does nothing when Deploy names no app" {
			$script:Section.Deploy = @{}

			Deploy-AiMcpServers -Command $script:Stub

			Test-Path -Path $script:Log | Should -BeFalse
			Test-Path -Path $script:CodexConfig | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "AiMcpServers.Deploy names no app*" }
		}
	}

	Context "AI profile and the state file" {
		BeforeEach {
			$script:Section.Servers.mobbin = @{ Url = "https://mcp.example.com/mcp" }
			$script:Listed = @("linear")
			Mock Resolve-AiProfile { @{ Enabled = $true; Name = "Personal"; Profile = @{ McpServers = $script:Listed }; Warnings = @() } }
		}

		It "registers only the servers the profile lists and records them per app" {
			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Be @("mcp|add|--scope|user|--transport|http|linear|https://mcp.linear.app/mcp")
			Get-Content -Path $script:CodexConfig -Raw | Should -Not -Match "mobbin"
			$state = @(Get-Content -Path $script:StateFile | Where-Object { $_ -and -not $_.StartsWith('#') })
			$state | Should -Be @("claude-code`tlinear", "codex`tlinear")
		}

		It "removes a recorded server the profile no longer lists, from Claude Code and Codex" {
			Deploy-AiMcpServers -Command $script:Stub
			Set-Content -Path $script:ClaudeState -Value '{"mcpServers":{"linear":{"type":"http","url":"https://mcp.linear.app/mcp"}}}'
			Remove-Item -Path $script:Log
			$script:Listed = @()

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Be @("mcp|remove|--scope|user|linear")
			Get-Content -Path $script:CodexConfig -Raw | Should -Not -Match "linear"
			@(Get-Content -Path $script:StateFile | Where-Object { $_ -and -not $_.StartsWith('#') }).Count | Should -Be 0
		}

		It "never removes a server the user added by hand with another definition" {
			Set-Content -Path $script:ClaudeState -Value '{"mcpServers":{"mobbin":{"type":"http","url":"https://my-own.example.com/mcp"},"mine":{"type":"http","url":"https://mine.example.com/mcp"}}}'
			New-Item -ItemType Directory -Path (Split-Path -Parent $script:CodexConfig) -Force | Out-Null
			Set-Content -Path $script:CodexConfig -Value @('[mcp_servers.mobbin]', 'url = "https://my-own.example.com/mcp"')

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Not -Contain "mcp|remove|--scope|user|mobbin"
			@(Get-Content -Path $script:Log) | Should -Not -Contain "mcp|remove|--scope|user|mine"
			Get-Content -Path $script:CodexConfig -Raw | Should -Match "my-own.example.com"
		}

		It "counts a configured server carried exactly as configured as its own, so it is removed when not listed" {
			Set-Content -Path $script:ClaudeState -Value '{"mcpServers":{"mobbin":{"type":"http","url":"https://mcp.example.com/mcp"}}}'
			New-Item -ItemType Directory -Path (Split-Path -Parent $script:CodexConfig) -Force | Out-Null
			Set-Content -Path $script:CodexConfig -Value @('model = "gpt-5"', '', '[mcp_servers.mobbin]', 'url = "https://mcp.example.com/mcp"')

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log) | Should -Contain "mcp|remove|--scope|user|mobbin"
			$codex = Get-Content -Path $script:CodexConfig -Raw
			$codex | Should -Not -Match "mobbin"
			$codex | Should -Match 'model = "gpt-5"'
		}

		It "registers every server when the profile leaves McpServers out" {
			$script:Listed = $null

			Deploy-AiMcpServers -Command $script:Stub

			@(Get-Content -Path $script:Log).Count | Should -Be 2
		}
	}

	Context "inside WSL" {
		BeforeEach {
			Mock Test-WSLDistributionInstalled { $true }
			Mock Get-ConfigSetting {
				switch ($Path) {
					'AiMcpServers' { $script:Section }
					'DefaultWSLDistribution' { "WinuXTestDistro-$([guid]::Empty)" }
					'DefaultWSLUsername' { "u" }
					default { $null }
				}
			}
			# A stand-in wsl.exe: `command -v claude` answers WINUX_TEST_WSL_CLAUDE, `cat` answers
			# WINUX_TEST_WSL_STATE; a claude call (everything after the `claude` that names $0) is
			# recorded.
			$script:WslLog = Join-Path $TestDrive "wsl-calls.log"
			if (Test-Path -Path $script:WslLog) { Remove-Item -Path $script:WslLog -Force }
			$env:WINUX_TEST_WSL_CLAUDE = "/home/u/.local/bin/claude"
			$env:WINUX_TEST_WSL_STATE = ""
			$script:WslStub = Join-Path $TestDrive "wsl-stub.ps1"
			Set-Content -Path $script:WslStub -Value @(
				"if ((`$args -join ' ') -like '*command -v claude*') { if (`$env:WINUX_TEST_WSL_CLAUDE) { Write-Output `$env:WINUX_TEST_WSL_CLAUDE; exit 0 }; exit 1 }",
				"if ((`$args -join ' ') -like '*cat *') { Write-Output `$env:WINUX_TEST_WSL_STATE; exit 0 }",
				"`$rest = `$args[([array]::IndexOf(`$args, 'claude') + 1)..(`$args.Count - 1)]",
				"Add-Content -Path '$script:WslLog' -Value (`$rest -join '|')",
				"exit 0"
			)
		}

		AfterEach {
			Remove-Item -Path Env:\WINUX_TEST_WSL_CLAUDE -ErrorAction SilentlyContinue
			Remove-Item -Path Env:\WINUX_TEST_WSL_STATE -ErrorAction SilentlyContinue
		}

		It "adds the server through the Claude Code CLI inside WSL and warns about the unreachable share" {
			Deploy-AiMcpServers -Command $script:Stub -WslCommand $script:WslStub

			@(Get-Content -Path $script:WslLog) | Should -Be @("mcp|add|--scope|user|--transport|http|linear|https://mcp.linear.app/mcp")
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "[WSL] Added Claude Code MCP server [linear]" }
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "WSL share for *unreachable - the Codex MCP servers were not added inside WSL!" }
			@(Get-Content -Path $script:Log) | Should -Contain "mcp|add|--scope|user|--transport|http|linear|https://mcp.linear.app/mcp" -Because "the Windows CLI is still deployed first"
		}

		It "compares with the WSL user's ~/.claude.json read through WSL" {
			$env:WINUX_TEST_WSL_STATE = '{"mcpServers":{"linear":{"type":"http","url":"https://mcp.linear.app/mcp"}}}'

			Deploy-AiMcpServers -Command $script:Stub -WslCommand $script:WslStub

			Test-Path -Path $script:WslLog | Should -BeFalse
			Should -Invoke Write-LogStep -ParameterFilter { $Message -eq "[WSL] Claude Code MCP server [linear] already configured" }
		}

		It "treats the Windows CLI reached through interop as missing inside WSL" {
			$env:WINUX_TEST_WSL_CLAUDE = "/mnt/c/Users/u/AppData/Roaming/npm/claude"

			Deploy-AiMcpServers -Command $script:Stub -WslCommand $script:WslStub

			Test-Path -Path $script:WslLog | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "WSL [[]*] resolves claude to the Windows CLI [[]/mnt/c/*" }
		}

		It "only warns when WSL has no Claude Code CLI" {
			$env:WINUX_TEST_WSL_CLAUDE = ""

			Deploy-AiMcpServers -Command $script:Stub -WslCommand $script:WslStub

			Test-Path -Path $script:WslLog | Should -BeFalse
			Should -Invoke Write-LogWarning -ParameterFilter { $Message -like "Claude Code CLI (claude) not found inside WSL*" }
			Should -Invoke Write-LogSuccess -ParameterFilter { $Message -eq "AI MCP servers deployed!" }
		}
	}
}
