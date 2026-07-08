#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Set-Locale.ps1"
}

Describe "Set-Locale" {
	BeforeEach {
		$script:Configuration = [PSCustomObject]@{
			Locales       = [ordered]@{
				"en-US" = [PSCustomObject]@{ Code = "en-US"; GeoId = 244 }
			}
			DefaultLocale = "en-US"
		}
		Mock Test-AdminPrivileges { }
		Mock Write-Host { }
		Mock Write-LogError { }
	}

	It "returns when requested locale is not configured" {
		{ Set-Locale -Locale "hr-HR" } | Should -Not -Throw
		Should -Invoke Write-LogError -Times 1
	}
}
