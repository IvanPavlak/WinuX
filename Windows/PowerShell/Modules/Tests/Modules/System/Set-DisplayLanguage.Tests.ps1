#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-DisplayLanguage.ps1"
}

Describe "Set-DisplayLanguage" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			DisplayLanguages       = [ordered]@{
				"en-US" = "en-US"
			}
			DefaultDisplayLanguage = "en-US"
		}
		Mock Test-AdminPrivileges { }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "returns when requested language is not configured" {
		{ Set-DisplayLanguage -Language "hr-HR" } | Should -Not -Throw
		Should -Invoke Write-LogError -Times 1
	}
}
