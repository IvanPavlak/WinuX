#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Initialize-Directory.ps1"
}

Describe "Initialize-Directory" {
	Context "Directory Creation" {
		It "Should create directory when it does not exist" {
			$testDir = Join-Path $TestDrive "NewTestDir"

			Initialize-Directory -Path $testDir

			Test-Path $testDir | Should -Be $true
		}

		It "Should not throw when directory already exists" {
			$testDir = Join-Path $TestDrive "ExistingDir"
			New-Item -ItemType Directory -Path $testDir -Force | Out-Null

			{ Initialize-Directory -Path $testDir } | Should -Not -Throw

			Test-Path $testDir | Should -Be $true
		}

		It "Should create nested directories" {
			$testDir = Join-Path $TestDrive "Level1\Level2\Level3"

			Initialize-Directory -Path $testDir

			Test-Path $testDir | Should -Be $true
		}
	}
}
