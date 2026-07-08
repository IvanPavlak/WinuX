#Requires -Modules Pester

BeforeAll {
	$ModulePath = Join-Path (Get-RepositoryPath).Modules "Logging\Logging.psd1"
	Import-Module $ModulePath -Force
}

AfterAll {
	Remove-Module Logging -Force -ErrorAction SilentlyContinue
}

Describe "Write-LogList" {
	BeforeEach {
		# Write-LogList delegates each bullet to Write-LogStep (same module) - mock it and assert calls.
		Mock -ModuleName Logging Write-LogStep { }
	}

	It "writes one bulleted Step line per item" {
		Write-LogList @("Windows Terminal", "Firefox")
		Should -Invoke -ModuleName Logging Write-LogStep -Times 2 -Exactly
		Should -Invoke -ModuleName Logging Write-LogStep -Times 1 -Exactly -ParameterFilter { $Message -eq "  • Windows Terminal" }
		Should -Invoke -ModuleName Logging Write-LogStep -Times 1 -Exactly -ParameterFilter { $Message -eq "  • Firefox" }
	}

	It "renders each bullet with the leading-newline suppressed so it sits under the summary" {
		Write-LogList @("Only")
		Should -Invoke -ModuleName Logging Write-LogStep -Times 1 -Exactly -ParameterFilter { $NoLeadingNewline }
	}

	It "skips null, empty, and whitespace-only items" {
		Write-LogList @("Alpha", "", "   ", $null, "Beta")
		Should -Invoke -ModuleName Logging Write-LogStep -Times 2 -Exactly
	}

	It "writes nothing for an empty list" {
		Write-LogList @()
		Should -Invoke -ModuleName Logging Write-LogStep -Times 0 -Exactly
	}

	It "accepts pipeline input" {
		@("One", "Two", "Three") | Write-LogList
		Should -Invoke -ModuleName Logging Write-LogStep -Times 3 -Exactly
	}
}
