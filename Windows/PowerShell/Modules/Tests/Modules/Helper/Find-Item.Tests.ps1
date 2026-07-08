#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Find-Item.ps1"
}

Describe "Find-Item" {
	BeforeEach {
		Mock Write-Host { }
		Mock Get-Location { [PSCustomObject]@{ Path = "C:\\Repo" } }
		Mock Get-ChildItem { @() }
		Mock Split-Path { "C:\\" }
	}

	It "returns null when no matching items are found" {
		$result = Find-Item -Pattern "*.sln" -StartPath "C:\\Repo" -MaxUpwardDepth 1 -MaxDownwardDepth 1

		$result | Should -Be $null
		Should -Invoke Get-ChildItem -Times 1
	}
}
