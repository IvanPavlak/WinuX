#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Open-Training.ps1"
}

Describe "Open-Training" {
	BeforeEach {
		$script:MachineSpecificPaths = @{ TrainingDirectory = "C:\Training" }
		$script:Configuration = @{ Universal = @{ TrainingFile = "Plan.docx" } }
		Mock Write-Host { }
		Mock Start-Process { }
	}

	It "starts Word process when not already running" {
		Mock Get-Process { $null } -ParameterFilter { $Name -eq "WINWORD" }

		Open-Training

		Should -Invoke Start-Process -Times 1 -ParameterFilter { $FilePath -eq "winword" }
	}

	It "does not start Word when already running" {
		Mock Get-Process { @{ Name = "WINWORD" } } -ParameterFilter { $Name -eq "WINWORD" }

		Open-Training

		Should -Invoke Start-Process -Times 0
	}
}
