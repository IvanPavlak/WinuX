#Requires -Modules Pester

BeforeAll {
	$HelperFunctionsPath = Join-Path (Get-RepositoryPath).Modules "Helper\Functions"
	. "$HelperFunctionsPath\Get-FilteredParams.ps1"
}

Describe "Get-FilteredParams" {
	Context "Filtering Valid Parameters" {
		It "Should return only parameters valid for the specified command" {
			$params = @{
				Path      = "C:\test"
				Filter    = "*.txt"
				FakeParam = "invalid"
			}

			$result = Get-FilteredParams -CommandName "Get-ChildItem" -Params $params

			$result.ContainsKey("Path") | Should -Be $true
			$result.ContainsKey("Filter") | Should -Be $true
			$result.ContainsKey("FakeParam") | Should -Be $false
		}

		It "Should return all params when all are valid" {
			$params = @{
				Path    = "C:\test"
				Recurse = $true
			}

			$result = Get-FilteredParams -CommandName "Get-ChildItem" -Params $params

			$result.Count | Should -Be 2
		}

		It "Should return empty hashtable when no params are valid" {
			$params = @{
				CompletelyFakeParam1 = "value1"
				CompletelyFakeParam2 = "value2"
			}

			$result = Get-FilteredParams -CommandName "Get-ChildItem" -Params $params

			$result.Count | Should -Be 0
		}
	}

	Context "Non-Existent Command" {
		It "Should return original params when command does not exist" {
			$params = @{
				Param1 = "value1"
				Param2 = "value2"
			}

			$result = Get-FilteredParams -CommandName "NonExistentCommand-12345" -Params $params

			$result.Count | Should -Be 2
			$result.Param1 | Should -Be "value1"
		}
	}
}
