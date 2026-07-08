#Requires -Modules Pester

BeforeAll {
	if (-not ("WindowModule.Native" -as [type])) {
		Add-Type -TypeDefinition @"
namespace WindowModule {
    public static class Native {
        public static void ClearProcessCache() { }
        public static object[] GetAllWindows() { return new object[0]; }
    }
}
"@
	}

	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Clear-WindowCache.ps1"
}

Describe "Clear-WindowCache" {
	It "resets window cache values" {
		$script:WindowCache = @{
			Windows   = @(@{ Handle = [IntPtr]1 })
			Timestamp = [datetime]::Now
			MaxAgeMs  = 50
		}

		{ Clear-WindowCache } | Should -Not -Throw
		$script:WindowCache.Windows | Should -BeNullOrEmpty
		$script:WindowCache.Timestamp | Should -Be ([datetime]::MinValue)
	}
}
