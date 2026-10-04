#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Set-ClaudeSettingsKey.ps1"
}

Describe "Set-ClaudeSettingsKey" {
	BeforeEach {
		Mock Write-LogStep { }
		Mock Write-LogError { }

		$script:Settings = Join-Path $TestDrive "home\.claude\settings.json"
		if (Test-Path -Path (Join-Path $TestDrive "home")) { Remove-Item -Path (Join-Path $TestDrive "home") -Recurse -Force }
	}

	It "creates a missing file holding only the nested path" {
		$result = Set-ClaudeSettingsKey -Path "extraKnownMarketplaces.my-marketplace" -Value @{ source = @{ source = "github"; repo = "MyOrg/MyMarketplace" } } -SettingsPath $script:Settings

		$result | Should -BeTrue
		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.extraKnownMarketplaces.'my-marketplace'.source.repo | Should -Be "MyOrg/MyMarketplace"
		@($document.PSObject.Properties.Name) | Should -Be @("extraKnownMarketplaces")
	}

	It "sets a key deep in an existing file and keeps every other setting" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"C:\\mods\\a"},"permissions":{"allow":["Bash"]},"pluginConfigs":{"my-plugin":{"options":{"pulse":false}}}}'

		$result = Set-ClaudeSettingsKey -Path "pluginConfigs.my-plugin.options" -Value @{ theme = "light" } -SettingsPath $script:Settings

		$result | Should -BeTrue
		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.pluginConfigs.'my-plugin'.options.theme | Should -Be "light"
		$document.pluginConfigs.'my-plugin'.options.PSObject.Properties['pulse'] | Should -BeNullOrEmpty -Because "the leaf is replaced whole"
		$document.env.CLAUDE_CODE_PLUGIN_DIRS | Should -Be "C:\mods\a"
		@($document.permissions.allow) | Should -Be @("Bash")
	}

	It "creates the objects along the path" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"env":{}}'

		Set-ClaudeSettingsKey -Path "a.b.c" -Value 1 -SettingsPath $script:Settings | Should -BeTrue

		(Get-Content -Path $script:Settings -Raw | ConvertFrom-Json).a.b.c | Should -Be 1
	}

	It "writes nothing when the value is already equal" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"extraKnownMarketplaces":{"my-marketplace":{"source":{"source":"github","repo":"MyOrg/MyMarketplace"}}}}'
		$before = (Get-Item -Path $script:Settings).LastWriteTimeUtc
		Start-Sleep -Milliseconds 20

		$result = Set-ClaudeSettingsKey -Path "extraKnownMarketplaces.my-marketplace" -Value @{ source = @{ source = "github"; repo = "MyOrg/MyMarketplace" } } -SettingsPath $script:Settings

		$result | Should -BeTrue
		(Get-Item -Path $script:Settings).LastWriteTimeUtc | Should -Be $before
		Should -Invoke Write-LogStep -ParameterFilter { $Message -like "*already up to date*" }
	}

	It "refuses when a value along the path is not an object" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"pluginConfigs":"nope"}'

		$result = Set-ClaudeSettingsKey -Path "pluginConfigs.my-plugin" -Value @{ a = 1 } -SettingsPath $script:Settings

		$result | Should -BeFalse
		(Get-Content -Path $script:Settings -Raw | ConvertFrom-Json).pluginConfigs | Should -Be "nope"
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "*pluginConfigs*not a JSON object*" }
	}

	It "leaves an unparseable file untouched" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{ not json'

		Set-ClaudeSettingsKey -Path "a" -Value 1 -SettingsPath $script:Settings | Should -BeFalse

		Get-Content -Path $script:Settings -Raw | Should -BeLike "{ not json*"
		Should -Invoke Write-LogError -ParameterFilter { $Message -like "Could not parse*" }
	}

	It "rejects a path with an empty segment" {
		Set-ClaudeSettingsKey -Path "a..b" -Value 1 -SettingsPath $script:Settings | Should -BeFalse

		Test-Path -Path $script:Settings | Should -BeFalse
	}

	It "reports the change without writing under -WhatIf" {
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:Settings) -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"env":{}}'

		Set-ClaudeSettingsKey -Path "a.b" -Value "x" -SettingsPath $script:Settings -WhatIf | Should -BeTrue

		(Get-Content -Path $script:Settings -Raw | ConvertFrom-Json).PSObject.Properties['a'] | Should -BeNullOrEmpty
	}
}
