#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$HelperFunctionsPath = Join-Path $ModuleRoot "Helper\Functions"
	$FunctionsPath = Join-Path $ModuleRoot "Workflow\Functions"

	. "$HelperFunctionsPath\Get-TargetTerminalWindow.ps1"
	. "$FunctionsPath\Close-ProjectTerminals.ps1"

	# Stub dependent functions
	function Get-WindowHandle { param($ProcessName) $null }
	function Focus-TerminalTab { param($TargetTitle) }
}

Describe "Close-ProjectTerminals" {
	BeforeEach {
		Mock Write-Host { }
		Mock Start-Sleep { }
		Mock Add-Type { }
	}

	Context "When Windows Terminal is not running" {
		It "Should return 0" {
			Mock Get-Process { $null }

			$result = Close-ProjectTerminals -ProjectName "AnotherProject"

			$result | Should -Be 0
		}
	}

	Context "When Windows Terminal is running but activation fails" {
		It "Should return 0 when process activation throws" {
			# Mock Get-Process to return a fake WT process with a non-existent PID
			# The function's try/catch handles the AppActivate failure gracefully
			Mock Get-Process { [PSCustomObject]@{ ProcessName = "WindowsTerminal"; Id = 99999 } }

			$result = Close-ProjectTerminals -ProjectName "AnotherProject"

			$result | Should -Be 0
		}
	}

	Context "Parameter validation" {
		It "Should require ProjectName parameter" {
			$cmd = Get-Command Close-ProjectTerminals
			$param = $cmd.Parameters['ProjectName']
			$param | Should -Not -BeNullOrEmpty

			$mandatoryAttr = $param.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
			$mandatoryAttr.Mandatory | Should -BeTrue
		}
	}
}
