#Requires -Modules Pester

BeforeAll {
	$script:OriginalMachineSpecificPaths = $global:MachineSpecificPaths
	$AppFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Application\Functions"
	. "$AppFunctionsPath\Open-Obsidian.ps1"
}

AfterAll {
	$global:MachineSpecificPaths = $script:OriginalMachineSpecificPaths
}

Describe "Open-Obsidian" {
	BeforeEach {
		$global:MachineSpecificPaths = @{ ObsidianStartupScript = 'C:\Obsidian\ObsidianStartupScript.pyw' }
		Mock Start-Application { }
	}

	It "delegates to Start-Application with pythonw startup script and skip path validation" {
		Open-Obsidian

		Should -Invoke Start-Application -Times 1 -Exactly -ParameterFilter {
			$AppName -eq 'Obsidian' -and
			$ProcessName -eq 'obsidian' -and
			$StartMethod -eq 'DirectPath' -and
			$ExecutablePath -eq 'pythonw' -and
			$Arguments -eq 'C:\Obsidian\ObsidianStartupScript.pyw' -and
			$SkipPathValidation
		}
	}
}
