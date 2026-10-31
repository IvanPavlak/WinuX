#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiProfile.ps1"
	. "$FunctionsPath\Test-AiProfile.ps1"
	. "$FunctionsPath\Initialize-AiProfile.ps1"
}

Describe "Initialize-AiProfile" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogDebug { }
		Mock Write-LogList { }
		Mock Custom-ReadHost { "" }
		Mock Test-AiProfile { $global:LASTEXITCODE = 0 }

		$script:TestHome = Join-Path $TestDrive "home"
		if (Test-Path -Path $script:TestHome) { Remove-Item -Path $script:TestHome -Recurse -Force }
		New-Item -ItemType Directory -Path $script:TestHome -Force | Out-Null
		$script:SavedUserProfile = $env:USERPROFILE
		$script:SavedClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
		$env:USERPROFILE = $script:TestHome
		Remove-Item -Path Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue

		$script:Uuid = "00000000-0000-0000-0000-00000000000a"
		Set-Content -Path (Join-Path $script:TestHome ".claude.json") -Value "{ `"oauthAccount`": { `"organizationUuid`": `"$($script:Uuid)`", `"organizationName`": `"My Org`" } }"
		$script:Selected = @{ Name = "Personal"; Plans = @(@{ Name = "Max"; OrgUuid = $script:Uuid }); McpServers = @("remote"); EnvVars = @() }
		Mock Resolve-AiProfile { @{ Enabled = $true; Name = "Personal"; Source = "default"; HostName = "DESKTOP-GAMING"; Profile = $script:Selected; Warnings = @() } }
		Mock Get-ConfigSetting {
			switch ($Path) {
				'AiMcpServers' { @{ Servers = @{ remote = @{ Url = "https://mcp.example.com/mcp" }; unlisted = @{ Url = "https://mcp.example.org/mcp" } } } }
				default { $null }
			}
		}

		# A stand-in gh that records its calls and is signed in.
		$script:GhLog = Join-Path $TestDrive "gh.log"
		if (Test-Path -Path $script:GhLog) { Remove-Item -Path $script:GhLog -Force }
		$script:Gh = Join-Path $TestDrive "gh-stub.ps1"
		Set-Content -Path $script:Gh -Value @(
			"Add-Content -Path '$script:GhLog' -Value (`$args -join ' ')",
						"exit 0"
		)
	}

	AfterEach {
		$env:USERPROFILE = $script:SavedUserProfile
		if ($script:SavedClaudeConfigDir) { $env:CLAUDE_CONFIG_DIR = $script:SavedClaudeConfigDir }
	}

	It "says so and does nothing else without an AI profile" {
		Mock Resolve-AiProfile { @{ Enabled = $false; Warnings = @() } }

		Initialize-AiProfile -GhCommand $script:Gh

		Should -Invoke Test-AiProfile -Times 0
		Test-Path -Path $script:GhLog | Should -BeFalse
	}

	It "skips the Claude Code login when the expected Plan is logged in, and ends with Test-AiProfile" {
		Initialize-AiProfile -GhCommand $script:Gh

		Should -Invoke Custom-ReadHost -Times 0 -ParameterFilter { $PromptMessage -like "*Claude Code is logged in*" }
		Should -Invoke Test-AiProfile -Times 1 -Exactly
	}

	It "waits for the Claude Code login when another Plan is logged in" {
		Set-Content -Path (Join-Path $script:TestHome ".claude.json") -Value '{ "oauthAccount": { "organizationUuid": "11111111-1111-1111-1111-111111111111", "organizationName": "Other" } }'

		Initialize-AiProfile -GhCommand $script:Gh

		Should -Invoke Custom-ReadHost -Times 1 -Exactly -ParameterFilter { $PromptMessage -like "*Claude Code is logged in*" }
	}

	It "runs gh auth login only when gh is not signed in" {
		Initialize-AiProfile -GhCommand $script:Gh
		@(Get-Content -Path $script:GhLog) | Should -Be @("auth status")

		Remove-Item -Path $script:GhLog
		Set-Content -Path $script:Gh -Value @(
			"Add-Content -Path '$script:GhLog' -Value (`$args -join ' ')",
			"if (`$args[1] -eq 'status') { exit 1 }",
			"exit 0"
		)
		Initialize-AiProfile -GhCommand $script:Gh
		@(Get-Content -Path $script:GhLog) | Should -Be @("auth status", "auth login")
	}

	It "lists only the OAuth MCP servers the profile registers" {
		Initialize-AiProfile -GhCommand $script:Gh

		Should -Invoke Write-LogList -Times 1 -Exactly -ParameterFilter { (@($Items) -join ',') -eq 'remote' }
		Should -Invoke Custom-ReadHost -Times 1 -Exactly -ParameterFilter { $PromptMessage -like "*every server is signed in*" }
	}

	It "checks the profile's environment variables by presence and asks only for the missing ones" {
		$script:Selected.EnvVars = @("WINUX_TEST_PRESENT_VAR", "WINUX_TEST_MISSING_VAR")
		$env:WINUX_TEST_PRESENT_VAR = "set"
		try {
			Initialize-AiProfile -GhCommand $script:Gh
		}
		finally {
			Remove-Item -Path Env:\WINUX_TEST_PRESENT_VAR -ErrorAction SilentlyContinue
		}

		Should -Invoke Custom-ReadHost -Times 1 -Exactly -ParameterFilter { $PromptMessage -like "*once they are set*" }
	}
}
