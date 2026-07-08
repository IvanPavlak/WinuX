#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Write-WindowInfoBlock.ps1"
}

Describe "Write-WindowInfoBlock" {
	BeforeEach {
		Mock Create-CenteredBorder { '-----' }
		Mock Write-Host { }
	}

	It "writes a formatted window block without throwing" {
		$info = [PSCustomObject]@{
			ProcessName = 'firefox'
			Title       = 'GitHub - Mozilla Firefox'
			Handle      = [IntPtr]1234
			ProcessId   = 4321
			X           = 10
			Y           = 20
			Width       = 1280
			Height      = 720
		}

		{ Write-WindowInfoBlock -Info $info } | Should -Not -Throw
		Should -Invoke Create-CenteredBorder -Times 1 -Exactly
	}
}
