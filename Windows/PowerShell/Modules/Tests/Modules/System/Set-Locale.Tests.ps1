#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	# The unconfigured-section guards warn through Confirm-ConfigValue (Helper);
	# dot-source it (and its Test-ConfigValue dependency) so the Write-LogWarning
	# mocks in these tests apply to the guard's warning.
	. "$ModuleRoot\Helper\Functions\Test-ConfigValue.ps1"
	. "$ModuleRoot\Helper\Functions\Confirm-ConfigValue.ps1"

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

	It "returns with a warning and no menu when Locales is empty (empty base)" {
		$script:Configuration = [PSCustomObject]@{
			Locales       = @{}
			DefaultLocale = ""
		}
		Mock Write-LogWarning { }
		Mock Resolve-Selection { }

		{ Set-Locale } | Should -Not -Throw

		Should -Invoke Write-LogWarning -Times 1 -ParameterFilter { $Message -match "Locales not configured" }
		Should -Invoke Resolve-Selection -Times 0
	}
}
