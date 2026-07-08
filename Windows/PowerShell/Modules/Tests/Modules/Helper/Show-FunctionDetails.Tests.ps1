#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Show-FunctionDetails.ps1"
}

Describe "Show-FunctionDetails" {
	BeforeEach {
		$global:Configuration = [PSCustomObject]@{
			ShowFunctionDetailsColors = [PSCustomObject]@{
				FunctionName = "Green"
				Description  = "White"
				Parameters   = @("Cyan", "Yellow")
			}
		}
		Mock Write-Host { }
	}

	It "writes function name, description, and parameter lines" {
		$info = [ordered]@{
			Description = "Example description"
			Path        = "C:\\Dev"
			Mode        = "Fast"
		}

		{ Show-FunctionDetails -FunctionName "Invoke-Sample" -FunctionInfo $info } | Should -Not -Throw
		Should -Invoke Write-Host -Times 4
	}
}
