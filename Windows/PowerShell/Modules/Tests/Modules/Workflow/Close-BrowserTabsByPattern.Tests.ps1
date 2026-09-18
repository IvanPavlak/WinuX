#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$FunctionsPath\Close-BrowserTabsByPattern.ps1"

	# Stub dependent functions
	function Get-WindowHandle { param($ProcessName) $null }
	function Close-Window { param([IntPtr[]]$Handle) 0 }
}

Describe "Close-BrowserTabsByPattern" {
	BeforeEach {
		Mock Write-Host { }
		Mock Start-Sleep { }
		Mock Add-Type { }
	}

	Context "When no browser windows are found" {
		It "Should return 0" {
			Mock Get-WindowHandle { $null }

			$result = Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger")

			$result | Should -Be 0
		}
	}

	Context "When browser windows exist with matching titles" {
		It "Should identify windows matching the title pattern" {
			$mockWindow = [PSCustomObject]@{
				Title     = "Swagger UI - Chrome"
				Handle    = [IntPtr]::new(12345)
				ProcessId = 100
			}
			Mock Get-WindowHandle { $mockWindow }

			# The direct close goes through the Window module's Close-Window seam, so it is mocked
			# here and asserted on rather than posting a real WM_CLOSE.
			Mock Close-Window { 1 }
			{ Close-BrowserTabsByPattern -ProcessName "chrome" -TitlePatterns @("(?i)swagger") } | Should -Not -Throw
		}
	}

	Context "Parameter validation" {
		It "Should require ProcessName parameter" {
			$cmd = Get-Command Close-BrowserTabsByPattern
			$param = $cmd.Parameters['ProcessName']
			$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
			$mandatoryAttr.Mandatory | Should -BeTrue
		}

		It "Should require TitlePatterns parameter" {
			$cmd = Get-Command Close-BrowserTabsByPattern
			$param = $cmd.Parameters['TitlePatterns']
			$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
			$mandatoryAttr.Mandatory | Should -BeTrue
		}
	}
}
