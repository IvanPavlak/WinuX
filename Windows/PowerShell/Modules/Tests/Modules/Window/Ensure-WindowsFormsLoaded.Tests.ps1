#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Ensure-WindowsFormsLoaded.ps1"
}

Describe "Ensure-WindowsFormsLoaded" {
	BeforeEach {
		Mock Add-Type { }
	}

	It "loads assembly when not already marked as loaded" {
		$script:WindowsFormsLoaded = $false

		Ensure-WindowsFormsLoaded

		Should -Invoke Add-Type -Times 1 -ParameterFilter { $AssemblyName -eq "System.Windows.Forms" }
		$script:WindowsFormsLoaded | Should -BeTrue
	}

	It "does not reload assembly when already loaded" {
		$script:WindowsFormsLoaded = $true

		Ensure-WindowsFormsLoaded

		Should -Invoke Add-Type -Times 0
	}
}
