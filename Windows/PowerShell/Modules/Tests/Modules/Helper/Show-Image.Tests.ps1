#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Show-Image.ps1"
}

Describe "Show-Image" {
	BeforeEach {
		Mock Add-WindowsFormsType { }
		Mock Get-Item { throw "Missing image" }
	}

	It "throws when image path cannot be resolved" {
		{ Show-Image -ImagePath "C:\\missing.png" } | Should -Throw
		Should -Invoke Add-WindowsFormsType -Times 1
		Should -Invoke Get-Item -Times 1
	}
}
