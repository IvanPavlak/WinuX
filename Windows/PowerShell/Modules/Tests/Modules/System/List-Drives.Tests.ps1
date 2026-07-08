#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\List-Drives.ps1"
}

Describe "List-Drives" {
	BeforeEach {
		Mock Get-PSDrive {
			@("C", "D")
		} -ParameterFilter { $PSProvider -eq "FileSystem" }
	}

	It "requests FileSystem drives" {
		$result = List-Drives

		Should -Invoke Get-PSDrive -Times 1 -ParameterFilter { $PSProvider -eq "FileSystem" }
		$result.Count | Should -Be 2
	}
}
