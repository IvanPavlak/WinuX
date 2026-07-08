#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Set-WindowCacheMaxAge.ps1"
}

Describe "Set-WindowCacheMaxAge" {
	It "updates cache max age value" {
		$script:WindowCache = @{ MaxAgeMs = 50 }

		Set-WindowCacheMaxAge -MaxAgeMs 250

		$script:WindowCache.MaxAgeMs | Should -Be 250
	}
}
