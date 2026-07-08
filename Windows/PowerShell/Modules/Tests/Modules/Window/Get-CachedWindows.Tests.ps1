#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Get-CachedWindows.ps1"
}

Describe "Get-CachedWindows" {
	It "returns cached windows when cache is still valid" {
		$cached = @(@{ Handle = [IntPtr]1; Title = "A" })
		$script:WindowCache = @{
			Windows   = $cached
			Timestamp = [datetime]::Now
			MaxAgeMs  = 999999
		}

		$result = Get-CachedWindows

		$result | Should -Be $cached
	}
}
