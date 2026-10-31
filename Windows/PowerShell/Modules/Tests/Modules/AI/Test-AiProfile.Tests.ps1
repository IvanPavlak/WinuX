#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Resolve-AiProfile.ps1"
	. "$FunctionsPath\Test-AiProfile.ps1"
}

Describe "Test-AiProfile" {
	BeforeEach {
		Mock Write-LogTitle { }
		Mock Write-LogStep { }
		Mock Write-LogSuccess { }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogList { }

		$script:TestHome = Join-Path $TestDrive "home"
		if (Test-Path -Path $script:TestHome) { Remove-Item -Path $script:TestHome -Recurse -Force }
		New-Item -ItemType Directory -Path (Join-Path $script:TestHome ".claude") -Force | Out-Null
		$script:SavedUserProfile = $env:USERPROFILE
		$script:SavedClaudeConfigDir = $env:CLAUDE_CONFIG_DIR
		$script:SavedApiKey = $env:ANTHROPIC_API_KEY
		$env:USERPROFILE = $script:TestHome
		Remove-Item -Path Env:\CLAUDE_CONFIG_DIR, Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue

		$script:Uuid = "00000000-0000-0000-0000-00000000000a"
		$script:ManagedPath = Join-Path $TestDrive "managed\managed-settings.json"
		New-Item -ItemType Directory -Path (Split-Path $script:ManagedPath) -Force | Out-Null
		Set-Content -Path $script:ManagedPath -Value "{ `"forceLoginOrgUUID`": `"$($script:Uuid)`" }"
		Set-Content -Path (Join-Path $script:TestHome ".claude.json") -Value "{ `"oauthAccount`": { `"organizationUuid`": `"$($script:Uuid)`", `"organizationName`": `"My Org`" } }"

		$script:Selected = @{ Name = "Personal"; Plans = @(@{ Name = "Max"; OrgUuid = $script:Uuid }); McpServers = $null }
		Mock Resolve-AiProfile { @{ Enabled = $true; Name = "Personal"; Source = "default"; HostName = "DESKTOP-GAMING"; Profile = $script:Selected; Warnings = @() } }

		$script:Servers = @{}
		Mock Get-ConfigSetting {
			switch ($Path) {
				'AiHarnesses' { @{ "claude-code" = @{ Destinations = @(@{ Kind = "Rules"; Placement = "File"; Files = @("managed-settings.json"); Hooks = @("managed-settings"); Path = $script:ManagedPath }) } } }
				'AiMcpServers' { @{ Servers = $script:Servers } }
				default { $null }
			}
		}

	}

	AfterEach {
		$env:USERPROFILE = $script:SavedUserProfile
		if ($script:SavedClaudeConfigDir) { $env:CLAUDE_CONFIG_DIR = $script:SavedClaudeConfigDir }
		if ($script:SavedApiKey) { $env:ANTHROPIC_API_KEY = $script:SavedApiKey } else { Remove-Item -Path Env:\ANTHROPIC_API_KEY -ErrorAction SilentlyContinue }
	}

	It "exits 2 when no AI profile is configured" {
		Mock Resolve-AiProfile { @{ Enabled = $false; HostName = "DESKTOP-GAMING"; Warnings = @() } }

		$result = Test-AiProfile -ShellProfile @() -PassThru

		$result.ExitCode | Should -Be 2
		$LASTEXITCODE | Should -Be 2
	}

	It "exits 0 when the expected Plan is logged in and pinned and no credential is found" {
		$result = Test-AiProfile -ShellProfile @() -PassThru

		$result.Problems | Should -BeNullOrEmpty -Because "a pay-per-use variable in this machine's user or machine environment would be a real finding"
		$result.ExitCode | Should -Be 0
		$result.LoggedIn.OrgUuid | Should -Be $script:Uuid
		$result.Pinned | Should -Be @($script:Uuid)
	}

	It "exits 1 when another Plan is logged in" {
		Set-Content -Path (Join-Path $script:TestHome ".claude.json") -Value '{ "oauthAccount": { "organizationUuid": "11111111-1111-1111-1111-111111111111", "organizationName": "Other" } }'

		(Test-AiProfile -ShellProfile @() -PassThru).ExitCode | Should -Be 1
	}

	It "exits 1 when the managed settings pin another Plan, or are missing" {
		Set-Content -Path $script:ManagedPath -Value '{ "forceLoginOrgUUID": ["11111111-1111-1111-1111-111111111111"] }'
		(Test-AiProfile -ShellProfile @() -PassThru).ExitCode | Should -Be 1

		Remove-Item -Path $script:ManagedPath
		(Test-AiProfile -ShellProfile @() -PassThru).ExitCode | Should -Be 1 -Because "missing managed settings pin nothing"
	}

	It "reports a credential in the environment, in a shell profile and an apiKeyHelper, by name only" {
		$env:ANTHROPIC_API_KEY = "planted-test-value"
		$shellProfile = Join-Path $script:TestHome ".bashrc"
		Set-Content -Path $shellProfile -Value 'export ANTHROPIC_AUTH_TOKEN=planted'
		Set-Content -Path (Join-Path $script:TestHome ".claude\settings.json") -Value '{ "apiKeyHelper": "/bin/echo" }'

		$result = Test-AiProfile -ShellProfile @($shellProfile) -PassThru

		$result.ExitCode | Should -Be 1
		@($result.Credentials | Where-Object { $_ -like "ANTHROPIC_API_KEY in the process environment" }).Count | Should -Be 1
		@($result.Credentials | Where-Object { $_ -like "ANTHROPIC_AUTH_TOKEN assigned in*" }).Count | Should -Be 1
		@($result.Credentials | Where-Object { $_ -like "apiKeyHelper in*" }).Count | Should -Be 1
		@($result.Credentials | Where-Object { $_ -like "*planted*" }).Count | Should -Be 0 -Because "a value is never printed"
	}

	It "does not count a mention that is no assignment" {
		$shellProfile = Join-Path $script:TestHome ".bashrc"
		Set-Content -Path $shellProfile -Value '# never set ANTHROPIC_API_KEY here'

		(Test-AiProfile -ShellProfile @($shellProfile) -PassThru).Credentials | Should -BeNullOrEmpty
	}

	It "lists the profile's OAuth MCP servers without checking them, and without changing the exit code" {
		$script:Servers = @{
			"oauth-listed"   = @{ Url = "https://mcp.example.com/mcp" }
			"oauth-unlisted" = @{ Url = "https://mcp.example.org/mcp" }
			"keyed"          = @{ Url = "https://api.example.com/mcp"; BearerTokenEnvVar = "MY_API_KEY" }
			"headered"       = @{ Url = "https://api.example.net/mcp"; Headers = @{ Authorization = "Bearer static" } }
			"local"          = @{ Command = "npx"; Args = @("-y", "my-mcp-server") }
		}
		$script:Selected.McpServers = @("oauth-listed", "keyed", "headered", "local")

		$result = Test-AiProfile -ShellProfile @() -PassThru

		$result.OAuthMcp | Should -Be @("oauth-listed")
		$result.ExitCode | Should -Be 0
	}
}
