#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Configure-NpmConfig.ps1"
}

Describe "Configure-NpmConfig" {
	BeforeEach {
		$script:npmrc = Join-Path $TestDrive "home\.npmrc"
		$script:backupRoot = Join-Path $TestDrive "Backups"
		Remove-Item -LiteralPath (Join-Path $TestDrive "home") -Recurse -Force -ErrorAction SilentlyContinue
		Remove-Item -LiteralPath $script:backupRoot -Recurse -Force -ErrorAction SilentlyContinue

		$global:MachineSpecificPaths = @{ NpmConfig = $script:npmrc }
		$global:Configuration = @{
			NpmRegistries = @(
				@{ Url = "https://npm.pkg.github.com"; Scope = "@my-org" }
			)
		}

		$script:token = "test-token-1234"
		Mock Custom-ReadHost { [System.Net.NetworkCredential]::new('', $script:token).SecurePassword }
		Mock Write-Host { }
	}

	It "creates a new npmrc with the auth and scope lines, without a backup" {
		Configure-NpmConfig -BackupRoot $script:backupRoot

		$content = [System.IO.File]::ReadAllText($script:npmrc)
		$content | Should -Be "//npm.pkg.github.com/:_authToken=test-token-1234`n@my-org:registry=https://npm.pkg.github.com/`n"
		Test-Path (Join-Path $script:backupRoot "System\NpmConfig") | Should -BeFalse
		Should -Invoke Custom-ReadHost -Times 1 -Exactly -ParameterFilter { $AsSecureString }
	}

	It "writes UTF-8 without a BOM" {
		Configure-NpmConfig -BackupRoot $script:backupRoot

		$bytes = [System.IO.File]::ReadAllBytes($script:npmrc)
		$bytes[0] | Should -Not -Be 0xEF
	}

	It "keeps unrelated lines in order and replaces a stale token line in place" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		[System.IO.File]::WriteAllText($script:npmrc, "save-exact=true`n//npm.pkg.github.com/:_authToken=`n# comment`nfund=false`n")

		Configure-NpmConfig -BackupRoot $script:backupRoot

		$lines = [System.IO.File]::ReadAllText($script:npmrc) -split "`n"
		$lines[0] | Should -Be "save-exact=true"
		$lines[1] | Should -Be "//npm.pkg.github.com/:_authToken=test-token-1234"
		$lines[2] | Should -Be "# comment"
		$lines[3] | Should -Be "fund=false"
		$lines[4] | Should -Be "@my-org:registry=https://npm.pkg.github.com/"
	}

	It "adds the scope line when only the token is set" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		[System.IO.File]::WriteAllText($script:npmrc, "//npm.pkg.github.com/:_authToken=old`n")

		Configure-NpmConfig -BackupRoot $script:backupRoot

		$content = [System.IO.File]::ReadAllText($script:npmrc)
		$content | Should -Match "(?m)^@my-org:registry=https://npm\.pkg\.github\.com/$"
	}

	It "changes nothing and asks nothing when every registry is configured" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		$before = "//npm.pkg.github.com/:_authToken=old`n@my-org:registry=https://npm.pkg.github.com/`n"
		[System.IO.File]::WriteAllText($script:npmrc, $before)

		Configure-NpmConfig -BackupRoot $script:backupRoot

		[System.IO.File]::ReadAllText($script:npmrc) | Should -Be $before
		Should -Invoke Custom-ReadHost -Times 0
		Test-Path (Join-Path $script:backupRoot "System\NpmConfig") | Should -BeFalse
	}

	It "asks again and replaces the token with -Override" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		[System.IO.File]::WriteAllText($script:npmrc, "//npm.pkg.github.com/:_authToken=old`n@my-org:registry=https://npm.pkg.github.com/`n")

		Configure-NpmConfig -Override -BackupRoot $script:backupRoot

		[System.IO.File]::ReadAllText($script:npmrc) | Should -Be "//npm.pkg.github.com/:_authToken=test-token-1234`n@my-org:registry=https://npm.pkg.github.com/`n"
		Should -Invoke Custom-ReadHost -Times 1 -Exactly
	}

	It "keeps the CRLF line endings of an existing npmrc" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		[System.IO.File]::WriteAllText($script:npmrc, "fund=false`r`n")

		Configure-NpmConfig -BackupRoot $script:backupRoot

		[System.IO.File]::ReadAllText($script:npmrc) | Should -Be "fund=false`r`n//npm.pkg.github.com/:_authToken=test-token-1234`r`n@my-org:registry=https://npm.pkg.github.com/`r`n"
	}

	It "asks once for several registries and writes the same token for each" {
		$global:Configuration.NpmRegistries = @(
			@{ Url = "https://npm.pkg.github.com/"; Scope = "@my-org" }
			@{ Url = "https://registry.example.com/npm/"; Scope = "" }
		)

		Configure-NpmConfig -BackupRoot $script:backupRoot

		$content = [System.IO.File]::ReadAllText($script:npmrc)
		$content | Should -Match "(?m)^//registry\.example\.com/npm/:_authToken=test-token-1234$"
		$content | Should -Not -Match "(?m)^:registry="
		Should -Invoke Custom-ReadHost -Times 1 -Exactly
	}

	It "writes nothing when the token has whitespace in it (a pasted command)" {
		$script:token = "Configure-NuGetConfig -Override"

		Configure-NpmConfig -BackupRoot $script:backupRoot

		Test-Path $script:npmrc | Should -BeFalse
	}

	It "writes nothing when the token is empty" {
		Mock Custom-ReadHost { [System.Security.SecureString]::new() }

		Configure-NpmConfig -BackupRoot $script:backupRoot

		Test-Path $script:npmrc | Should -BeFalse
	}

	It "backs up an existing npmrc before changing it" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		[System.IO.File]::WriteAllText($script:npmrc, "fund=false`n")

		Configure-NpmConfig -BackupRoot $script:backupRoot

		$backups = @(Get-ChildItem -Path (Join-Path $script:backupRoot "System\NpmConfig") -Recurse -File -Force)
		$backups.Count | Should -Be 1
		[System.IO.File]::ReadAllText($backups[0].FullName) | Should -Be "fund=false`n"
	}

	It "redacts every credential in the backup and keeps the other settings" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		[System.IO.File]::WriteAllText($script:npmrc, "fund=false`n//npm.pkg.github.com/:_authToken=old-token`n//registry.example.invalid/:_auth = b2xkLWF1dGg=`n//other.example.invalid/:_password=old-password`n")
		$tempBefore = @(Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter "npmrc-*" -Directory -ErrorAction SilentlyContinue).Count

		Configure-NpmConfig -BackupRoot $script:backupRoot

		$backups = @(Get-ChildItem -Path (Join-Path $script:backupRoot "System\NpmConfig") -Recurse -File -Force)
		$backups.Count | Should -Be 1
		$backups[0].Name | Should -Be ".npmrc"
		[System.IO.File]::ReadAllText($backups[0].FullName) | Should -Be "fund=false`n//npm.pkg.github.com/:_authToken=<redacted>`n//registry.example.invalid/:_auth=<redacted>`n//other.example.invalid/:_password=<redacted>`n"
		@(Get-ChildItem -Path ([System.IO.Path]::GetTempPath()) -Filter "npmrc-*" -Directory -ErrorAction SilentlyContinue).Count | Should -Be $tempBefore
		[System.IO.File]::ReadAllText($script:npmrc) | Should -Match "_authToken=test-token-1234"
	}

	It "leaves the npmrc untouched when the backup fails" {
		New-Item -ItemType Directory -Path (Split-Path $script:npmrc) -Force | Out-Null
		[System.IO.File]::WriteAllText($script:npmrc, "fund=false`n")
		Mock Backup-RepositoryItem { throw "access denied" }

		Configure-NpmConfig -BackupRoot $script:backupRoot

		[System.IO.File]::ReadAllText($script:npmrc) | Should -Be "fund=false`n"
	}

	It "does nothing and asks nothing when NpmRegistries is empty" {
		$global:Configuration.NpmRegistries = @()

		Configure-NpmConfig -BackupRoot $script:backupRoot

		Test-Path $script:npmrc | Should -BeFalse
		Should -Invoke Custom-ReadHost -Times 0
	}

	It "skips an entry with an invalid Url" {
		$global:Configuration.NpmRegistries = @( @{ Url = "npm.pkg.github.com"; Scope = "" } )

		Configure-NpmConfig -BackupRoot $script:backupRoot

		Test-Path $script:npmrc | Should -BeFalse
		Should -Invoke Custom-ReadHost -Times 0
	}

	It "never shows the token in any output stream" {
		$output = Configure-NpmConfig -BackupRoot $script:backupRoot *>&1 | Out-String

		$output | Should -Not -Match ([regex]::Escape($script:token))
		Should -Invoke Write-Host -Times 0 -ParameterFilter { "$Object" -match [regex]::Escape($script:token) }
	}
}
