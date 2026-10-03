#Requires -Modules Pester

BeforeAll {
	$FunctionsPath = Join-Path (Get-RepositoryPath).Modules "AI\Functions"
	. "$FunctionsPath\Set-ClaudeSettingsEnv.ps1"
}

Describe "Set-ClaudeSettingsEnv" {
	BeforeEach {
		Mock Write-LogStep { }
		Mock Write-LogError { }

		$script:Dir = Join-Path $TestDrive "home\.claude"
		$script:Settings = Join-Path $script:Dir "settings.json"
		if (Test-Path -Path (Join-Path $TestDrive "home")) { Remove-Item -Path (Join-Path $TestDrive "home") -Recurse -Force }
	}

	It "creates the directory and the file with only the env key when the file is missing" {
		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "C:\mods\alpha" -SettingsPath $script:Settings | Should -BeTrue

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.env.CLAUDE_CODE_PLUGIN_DIRS | Should -Be "C:\mods\alpha"
		@($document.PSObject.Properties.Name) | Should -Be @("env")
	}

	It "keeps every other top-level key, nested object and env variable" {
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"effortLevel":"high","env":{"OTHER":"1"},"permissions":{"allow":["Bash(ls)"],"deny":[]},"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]},"skipWorkflowUsageWarning":true}'

		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "C:\mods\alpha" -SettingsPath $script:Settings | Should -BeTrue

		$document = Get-Content -Path $script:Settings -Raw | ConvertFrom-Json
		$document.effortLevel | Should -Be "high"
		$document.skipWorkflowUsageWarning | Should -BeTrue
		$document.env.OTHER | Should -Be "1"
		$document.env.CLAUDE_CODE_PLUGIN_DIRS | Should -Be "C:\mods\alpha"
		@($document.permissions.allow) | Should -Be @("Bash(ls)")
		$document.hooks.Stop[0].hooks[0].command | Should -Be "echo hi"
	}

	It "adds an env object when the file has none" {
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"effortLevel":"high"}'

		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings | Should -BeTrue

		(Get-Content -Path $script:Settings -Raw | ConvertFrom-Json).env.CLAUDE_CODE_PLUGIN_DIRS | Should -Be "x"
	}

	It "does not rewrite the file when the value is already set" {
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		$original = '{"env":{"CLAUDE_CODE_PLUGIN_DIRS":"x"},"z":1}'
		Set-Content -Path $script:Settings -Value $original -NoNewline
		$before = (Get-Item -Path $script:Settings).LastWriteTimeUtc

		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings | Should -BeTrue

		Get-Content -Path $script:Settings -Raw | Should -Be $original
		(Get-Item -Path $script:Settings).LastWriteTimeUtc | Should -Be $before
	}

	It "leaves unparseable JSON untouched, logs an error and returns false" {
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{ not json' -NoNewline

		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings | Should -BeFalse

		Get-Content -Path $script:Settings -Raw | Should -Be '{ not json'
		Should -Invoke Write-LogError -Times 1
	}

	It "leaves the file untouched when env is not an object, or the top level is not an object" {
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"env":"oops"}' -NoNewline
		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings | Should -BeFalse
		Get-Content -Path $script:Settings -Raw | Should -Be '{"env":"oops"}'

		Set-Content -Path $script:Settings -Value '[1,2]' -NoNewline
		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings | Should -BeFalse
		Get-Content -Path $script:Settings -Raw | Should -Be '[1,2]'

		Should -Invoke Write-LogError -Times 2
	}

	It "writes nothing under -WhatIf" {
		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings -WhatIf | Out-Null
		Test-Path -Path $script:Settings | Should -BeFalse

		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"a":1}' -NoNewline
		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings -WhatIf | Out-Null
		Get-Content -Path $script:Settings -Raw | Should -Be '{"a":1}'
	}

	It "writes UTF-8 without a BOM, with LF line endings" {
		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings | Out-Null

		$bytes = [IO.File]::ReadAllBytes($script:Settings)
		($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
		[Text.Encoding]::UTF8.GetString($bytes) | Should -Not -Match "`r"
	}

	It "keeps date-like strings exactly as written" {
		New-Item -ItemType Directory -Path $script:Dir -Force | Out-Null
		Set-Content -Path $script:Settings -Value '{"lastSeen":"2026-10-03T17:45:57Z"}' -NoNewline

		Set-ClaudeSettingsEnv -Name "CLAUDE_CODE_PLUGIN_DIRS" -Value "x" -SettingsPath $script:Settings | Out-Null

		Get-Content -Path $script:Settings -Raw | Should -Match '"lastSeen": "2026-10-03T17:45:57Z"'
	}
}
