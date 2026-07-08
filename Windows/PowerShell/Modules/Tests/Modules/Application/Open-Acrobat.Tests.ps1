#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Acrobat.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Open-Acrobat" {
	BeforeEach {
		$global:MachineSpecificPaths = @{}
		$global:Configuration = @{
			AcrobatGroups    = @('ExampleCharacter')
			AcrobatPdfGroups = @{ ExampleCharacter = @('Docs.ExampleCharacterPdf') }
		}

		Mock Write-Host { }
		Mock Get-Process { $null }
		Mock Get-ChildItem { @() }
		Mock Get-ItemProperty { [PSCustomObject]@{} }
		Mock Resolve-Selection { @('ExampleCharacter') }
		Mock Invoke-Command { 'C:\Docs\ExampleCharacter.pdf' }
		Mock Test-Path { $true }
		Mock Start-Process { }
	}

	It "starts Acrobat process directly when Pdf parameter is omitted and Acrobat is not running" {
		Open-Acrobat

		Should -Invoke Start-Process -Times 1 -Exactly
		Should -Invoke Resolve-Selection -Times 0
	}

	It "resolves configured PDF path and opens it for a valid Pdf group" {
		Open-Acrobat -Pdf 'ExampleCharacter'

		Should -Invoke Invoke-Command -Times 1 -Exactly
		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Docs\ExampleCharacter.pdf'
		}
	}

	It "opens a recent PDF entry selected via Resolve-Selection" {
		$recentShortcut = [PSCustomObject]@{
			FullName      = 'C:\Users\You\AppData\Roaming\Microsoft\Windows\Recent\Recent1.lnk'
			LastWriteTime = Get-Date
		}

		$fakeShell = [PSCustomObject]@{}
		$fakeShell | Add-Member -MemberType ScriptMethod -Name CreateShortcut -Value {
			param($shortcutPath)
			[PSCustomObject]@{ TargetPath = 'C:\Docs\Recent1.pdf' }
		}

		Mock Get-ChildItem { @() } -ParameterFilter { $Path -like 'HKCU:*' }
		Mock Get-ChildItem { @($recentShortcut) } -ParameterFilter { $Path -notlike 'HKCU:*' }
		Mock New-Object { $fakeShell } -ParameterFilter { $ComObject -eq 'WScript.Shell' }
		Mock Resolve-Selection { @('Recent => Recent1') }

		Open-Acrobat -Pdf ''

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Docs\Recent1.pdf'
		}
		Should -Invoke Invoke-Command -Times 0 -Exactly
	}

	It "includes registry recent PDFs in the selection options" {
		$script:CapturedOptions = @()
		$recentRegistryKey = [PSCustomObject]@{
			PSChildName = 'c1'
			PSPath      = 'HKCU:\Software\Adobe\Adobe Acrobat\DC\AVGeneral\cRecentFiles\c1'
		}

		Mock Get-ChildItem { @($recentRegistryKey) } -ParameterFilter { $Path -like 'HKCU:*' }
		Mock Get-ChildItem { @() } -ParameterFilter { $Path -notlike 'HKCU:*' }
		Mock Get-ItemProperty { [PSCustomObject]@{ tDIText = '/C/Docs/RecentFromRegistry.pdf' } }
		Mock Resolve-Selection {
			$script:CapturedOptions = @($OptionList)
			$null
		}

		Open-Acrobat -Pdf ''

		$script:CapturedOptions | Should -Contain 'Recent => RecentFromRegistry'
	}

	It "opens a selected registry recent PDF" {
		$recentRegistryKey = [PSCustomObject]@{
			PSChildName = 'c1'
			PSPath      = 'HKCU:\Software\Adobe\Adobe Acrobat\DC\AVGeneral\cRecentFiles\c1'
		}

		Mock Get-ChildItem { @($recentRegistryKey) } -ParameterFilter { $Path -like 'HKCU:*' }
		Mock Get-ChildItem { @() } -ParameterFilter { $Path -notlike 'HKCU:*' }
		Mock Get-ItemProperty { [PSCustomObject]@{ tDIText = '/C/Docs/RecentFromRegistry.pdf' } }
		Mock Resolve-Selection { @('Recent => RecentFromRegistry') }

		Open-Acrobat -Pdf ''

		Should -Invoke Start-Process -Times 1 -Exactly -ParameterFilter {
			$FilePath -eq 'C:\Docs\RecentFromRegistry.pdf'
		}
	}
}
