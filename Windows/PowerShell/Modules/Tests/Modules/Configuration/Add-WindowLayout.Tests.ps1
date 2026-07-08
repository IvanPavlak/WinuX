#Requires -Modules Pester

BeforeAll {
	$ConfigurationFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Configuration\Functions"
	. "$ConfigurationFunctionsPath\Find-ConfigurationSection.ps1"
	. "$ConfigurationFunctionsPath\Add-WindowLayout.ps1"
}

Describe "Add-WindowLayout" {
	BeforeEach {
		$testLayoutsDir = Join-Path $TestDrive "Layouts"
		if (Test-Path $testLayoutsDir) {
			Remove-Item -Path $testLayoutsDir -Recurse -Force
		}
		New-Item -Path (Join-Path $testLayoutsDir "PC") -ItemType Directory -Force | Out-Null
		New-Item -Path (Join-Path $testLayoutsDir "Laptop") -ItemType Directory -Force | Out-Null

		$testConfig = Join-Path $TestDrive "Configuration.psd1"
		$configContent = @(
			'@{'
			'	SimpleLayoutWorkspaces = @("Fullscreen", "Empty")'
			'}'
		)
		Set-Content -Path $testConfig -Value $configContent
	}

	Context "Layout file creation" {
		It "Should create a layout file for specified machine type" {
			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("PC") -LayoutsDirectory $testLayoutsDir

			$layoutFile = Join-Path $testLayoutsDir "PC\TestWS_PC.psd1"
			Test-Path $layoutFile | Should -BeTrue
		}

		It "Should create layout files for multiple machine types" {
			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("PC", "Laptop") -LayoutsDirectory $testLayoutsDir

			Test-Path (Join-Path $testLayoutsDir "PC\TestWS_PC.psd1") | Should -BeTrue
			Test-Path (Join-Path $testLayoutsDir "Laptop\TestWS_Laptop.psd1") | Should -BeTrue
		}

		It "Should not overwrite existing layout files" {
			$existingFile = Join-Path $testLayoutsDir "PC\TestWS_PC.psd1"
			Set-Content -Path $existingFile -Value "existing content"

			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("PC") -LayoutsDirectory $testLayoutsDir

			$content = Get-Content -Path $existingFile -Raw
			$content | Should -Match "existing content"
		}

		It "Should generate valid PowerShell data in layout file" {
			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("PC") -LayoutsDirectory $testLayoutsDir

			$layoutFile = Join-Path $testLayoutsDir "PC\TestWS_PC.psd1"
			$parsed = Import-PowerShellDataFile -Path $layoutFile
			$parsed | Should -Not -BeNullOrEmpty
			$parsed.Monitors | Should -Not -BeNullOrEmpty
			$parsed.Layout | Should -Not -BeNullOrEmpty
		}

		It "Should include workspace name in layout visualization comment" {
			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("PC") -LayoutsDirectory $testLayoutsDir

			$content = Get-Content -Path (Join-Path $testLayoutsDir "PC\TestWS_PC.psd1") -Raw
			$content | Should -Match "TestWS"
			$content | Should -Match "PC"
		}
	}

	Context "SimpleLayoutWorkspaces integration" {
		It "Should add to SimpleLayoutWorkspaces when -Simple is set" {
			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("PC") -Simple `
				-LayoutsDirectory $testLayoutsDir -ConfigurationFilePath $testConfig

			$content = Get-Content -Path $testConfig -Raw
			$content | Should -Match "TestWS"
		}

		It "Should handle single-line SimpleLayoutWorkspaces array" {
			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("PC") -Simple `
				-LayoutsDirectory $testLayoutsDir -ConfigurationFilePath $testConfig

			$parsed = Import-PowerShellDataFile -Path $testConfig
			$parsed.SimpleLayoutWorkspaces | Should -Contain "TestWS"
			$parsed.SimpleLayoutWorkspaces | Should -Contain "Fullscreen"
			$parsed.SimpleLayoutWorkspaces | Should -Contain "Empty"
		}
	}

	Context "Directory creation" {
		It "Should create machine type directory if it does not exist" {
			$newMachineDir = Join-Path $testLayoutsDir "NewMachine"
			Test-Path $newMachineDir | Should -BeFalse

			Add-WindowLayout -WorkspaceName "TestWS" -MachineType @("NewMachine") -LayoutsDirectory $testLayoutsDir

			Test-Path (Join-Path $newMachineDir "TestWS_NewMachine.psd1") | Should -BeTrue
		}
	}
}
