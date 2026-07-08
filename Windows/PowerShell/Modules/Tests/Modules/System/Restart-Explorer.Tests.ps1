#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Restart-Explorer.ps1"
}

Describe "Restart-Explorer" {
	BeforeEach {
		Mock Write-Host { }
		Mock Stop-Process { }
		Mock Loading-Spinner { }
	}

	It "stops explorer and starts spinner with message when provided" {
		Restart-Explorer -Message "Waiting" -Delay 1

		Should -Invoke Stop-Process -Times 1 -ParameterFilter { $ProcessName -eq "explorer" }
		Should -Invoke Loading-Spinner -Times 1 -ParameterFilter { $Label -eq "Waiting" }
	}

	It "stops explorer and starts spinner without label when message is omitted" {
		Restart-Explorer

		Should -Invoke Stop-Process -Times 1
		Should -Invoke Loading-Spinner -Times 1
	}
}
