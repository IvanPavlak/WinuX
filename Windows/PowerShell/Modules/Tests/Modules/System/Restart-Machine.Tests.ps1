#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Restart-Machine.ps1"
}

Describe "Restart-Machine" {
	BeforeEach {
		Mock Write-Host { }
		Mock Countdown { }
		Mock Restart-Computer { }
	}

	It "counts down and restarts when selection resolves to Yes" {
		Mock Resolve-Selection { "Yes" }

		Restart-Machine

		Should -Invoke Countdown -Times 1
		Should -Invoke Restart-Computer -Times 1
	}

	It "does not restart when selection resolves to No" {
		Mock Resolve-Selection { "No" }

		Restart-Machine

		Should -Invoke Restart-Computer -Times 0
	}
}
