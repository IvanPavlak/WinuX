#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Save-ConfigurationFile.ps1"
}

Describe "Save-ConfigurationFile" {
	BeforeEach {
		Mock Write-LogError { }
		$script:BackupRoot = Join-Path $TestDrive "Backups"
		$script:File = Join-Path $TestDrive "Configuration.local.psd1"
		if (Test-Path $script:File) { Remove-Item -Path $script:File -Force }
	}

	It "backs the existing file up under its own name, then writes the new lines" {
		Set-Content -Path $script:File -Value @('@{', '	Old = 1', '}')

		$saved = Save-ConfigurationFile -Path $script:File -Lines @('@{', '	New = 1', '}') -BackupRoot $script:BackupRoot

		$saved | Should -BeTrue
		(Get-Content -Path $script:File -Raw) | Should -Match 'New = 1'
		$backup = @(Get-ChildItem -Path (Join-Path $script:BackupRoot "Config\Configuration.local") -Recurse -File)
		$backup.Count | Should -Be 1
		(Get-Content -Path $backup[0].FullName -Raw) | Should -Match 'Old = 1'
	}

	It "writes a file that does not exist yet without a backup" {
		$saved = Save-ConfigurationFile -Path $script:File -Lines @('@{', '}') -BackupRoot $script:BackupRoot

		$saved | Should -BeTrue
		Test-Path $script:File | Should -BeTrue
		Test-Path $script:BackupRoot | Should -BeFalse
	}

	It "leaves the file untouched when the backup fails" {
		Set-Content -Path $script:File -Value @('@{', '	Old = 1', '}')
		Mock Backup-RepositoryItem { throw "disk full" }

		$saved = Save-ConfigurationFile -Path $script:File -Lines @('@{', '	New = 1', '}') -BackupRoot $script:BackupRoot

		$saved | Should -BeFalse
		(Get-Content -Path $script:File -Raw) | Should -Match 'Old = 1'
		Should -Invoke Write-LogError -Times 1 -Exactly
	}
}
