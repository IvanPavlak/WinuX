#Requires -Modules Pester

BeforeAll {
	$script:OriginalConfiguration = $global:Configuration
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-NotepadPlusPlus.ps1"
}

AfterAll {
	$global:Configuration = $script:OriginalConfiguration
}

Describe "Open-NotepadPlusPlus" {
	BeforeEach {
		$global:Configuration = @{ Universal = @{ NotepadPlusPlusExe = 'C:\\Tools\\npp\\notepad++.exe' } }
		Mock Write-Host { }
		Mock Start-Application { }
		Mock Start-Process { }
		Mock Resolve-Path { 'C:\Repos\WinuX\README.md' }
		Mock Get-WindowHandle { @() }
	}

	It "delegates to Start-Application when no file path is provided" {
		Open-NotepadPlusPlus

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Notepad++' -and
			$ProcessName -eq 'notepad++' -and
			$StartMethod -eq 'ConfigPath' -and
			$ConfigKey -eq 'NotepadPlusPlusExe' -and
			$NoNewWindow
		}
		Should -Invoke Start-Process -Times 0
	}

	It "does not open a duplicate file when an existing Notepad++ window already contains that filename" {
		Mock Get-WindowHandle {
			@([PSCustomObject]@{ Title = 'README.md - Notepad++' })
		}

		Open-NotepadPlusPlus -File 'C:\Repos\WinuX\README.md'

		Should -Invoke Start-Process -Times 0
	}
}
