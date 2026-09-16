#Requires -Modules Pester

BeforeAll {
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Enable-ObsidianCli.ps1"
}

Describe "Enable-ObsidianCli" {
	BeforeEach {
		$script:settingsPath = Join-Path $TestDrive 'obsidian\obsidian.json'
		New-Item -ItemType Directory -Path (Split-Path -Parent $script:settingsPath) -Force | Out-Null
		$script:original = '{"vaults":{"39204097ad491025":{"path":"C:\\Vaults\\Obsidian","ts":1740239861403,"open":true}}}'
		Set-Content -LiteralPath $script:settingsPath -Value $script:original -NoNewline

		$script:obsidianRunning = $false
		Mock Get-Process { if ($script:obsidianRunning) { [PSCustomObject]@{ Name = 'obsidian' } } } -ParameterFilter { $Name -eq 'obsidian' }
		Mock Write-LogWarning { }
		Mock Write-LogError { }
		Mock Write-LogSuccess { }
	}

	It "sets cli to true and keeps the vault list" {
		Enable-ObsidianCli -SettingsPath $script:settingsPath

		$json = Get-Content -LiteralPath $script:settingsPath -Raw | ConvertFrom-Json
		$json.cli | Should -BeTrue
		$json.vaults.'39204097ad491025'.path | Should -Be 'C:\Vaults\Obsidian'
		Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -like '*enabled!*' }
		Should -Invoke Write-LogWarning -Times 0
	}

	It "writes a single compact line, the shape Obsidian itself uses" {
		Enable-ObsidianCli -SettingsPath $script:settingsPath

		$raw = Get-Content -LiteralPath $script:settingsPath -Raw
		$raw | Should -Not -Match "`n"
		$raw | Should -Match '"cli":true'
	}

	It "reports an already enabled CLI without rewriting the file" {
		Set-Content -LiteralPath $script:settingsPath -Value '{"vaults":{},"cli":true}' -NoNewline
		$before = (Get-Item -LiteralPath $script:settingsPath).LastWriteTimeUtc

		Enable-ObsidianCli -SettingsPath $script:settingsPath

		Should -Invoke Write-LogSuccess -Times 1 -Exactly -ParameterFilter { $Message -like '*already enabled*' }
		(Get-Item -LiteralPath $script:settingsPath).LastWriteTimeUtc | Should -Be $before
		Get-Content -LiteralPath $script:settingsPath -Raw | Should -Be '{"vaults":{},"cli":true}'
	}

	It "warns and leaves the file alone while Obsidian is running" {
		$script:obsidianRunning = $true

		Enable-ObsidianCli -SettingsPath $script:settingsPath

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*Obsidian is running*' }
		Get-Content -LiteralPath $script:settingsPath -Raw | Should -Be $script:original
	}

	It "warns when obsidian.json does not exist and creates nothing" {
		$missing = Join-Path $TestDrive 'nowhere\obsidian.json'

		Enable-ObsidianCli -SettingsPath $missing

		Should -Invoke Write-LogWarning -Times 1 -Exactly -ParameterFilter { $Message -like '*not found*start Obsidian once*' }
		Test-Path -LiteralPath $missing | Should -BeFalse
	}

	It "reports an unparsable file and does not overwrite it" {
		Set-Content -LiteralPath $script:settingsPath -Value '{not json' -NoNewline

		Enable-ObsidianCli -SettingsPath $script:settingsPath

		Should -Invoke Write-LogError -Times 1 -Exactly
		Get-Content -LiteralPath $script:settingsPath -Raw | Should -Be '{not json'
	}

	It "writes nothing with -WhatIf" {
		Enable-ObsidianCli -SettingsPath $script:settingsPath -WhatIf

		Get-Content -LiteralPath $script:settingsPath -Raw | Should -Be $script:original
		Should -Invoke Write-LogSuccess -Times 0
	}
}
