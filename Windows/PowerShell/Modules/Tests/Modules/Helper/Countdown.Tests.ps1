#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Helper\Functions"

	. "$FunctionsPath\Countdown.ps1"
}

Describe "Countdown" {
	BeforeEach {
		Mock Start-Sleep { }
		Mock Write-Host { }
	}

	It "counts down and sleeps once per second value" {
		Countdown -Seconds 3

		Should -Invoke Start-Sleep -Times 3
	}

	It "prints message when provided" {
		Countdown -Seconds 1 -Message "Restarting in"

		Should -Invoke Write-Host -Times 2
	}
}
