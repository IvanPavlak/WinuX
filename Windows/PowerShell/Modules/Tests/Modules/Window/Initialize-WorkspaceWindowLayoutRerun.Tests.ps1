#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "Window\Functions"

	. "$FunctionsPath\Initialize-WorkspaceWindowLayoutRerun.ps1"

	function Get-RpcRetryPolicy {
		param(
			[string]$OperationLabel,
			[switch]$Probe
		)
	}
	function Start-FancyZones {
		param(
			[int]$MaxWaitSeconds,
			[switch]$ForceRestart
		)
	}
	function Remove-VirtualDesktops {
		param()
	}
	function Clear-FancyZonesCache { }
	function Clear-MonitorCache { }
	function Clear-WindowCache { }
}

Describe "Initialize-WorkspaceWindowLayoutRerun" {
	BeforeEach {
		Mock Write-Host { }
		Mock Start-Sleep { }
		Mock Get-RpcRetryPolicy { @{ MaxAttempts = 3; InitialDelayMs = 200 } }
		Mock Start-FancyZones { $true }
		Mock Remove-VirtualDesktops { $true }
		Mock Clear-FancyZonesCache { }
		Mock Clear-MonitorCache { }
		Mock Clear-WindowCache { }
	}

	It "runs RPC preflight and preserves layout state for window-only retry" {
		$result = Initialize-WorkspaceWindowLayoutRerun -WindowOnlyRetry

		$result | Should -BeTrue
		Should -Invoke Get-RpcRetryPolicy -Times 1 -Exactly -ParameterFilter { $OperationLabel -eq 'rerun' -and $Probe }
		Should -Invoke Start-FancyZones -Times 0
		Should -Invoke Remove-VirtualDesktops -Times 0
		Should -Invoke Clear-FancyZonesCache -Times 0
		Should -Invoke Clear-MonitorCache -Times 0
		Should -Invoke Clear-WindowCache -Times 0
	}

	It "restarts FancyZones and clears layout state for full cleanup retry" {
		$result = Initialize-WorkspaceWindowLayoutRerun

		$result | Should -BeTrue
		Should -Invoke Get-RpcRetryPolicy -Times 1 -Exactly -ParameterFilter { $OperationLabel -eq 'rerun' -and $Probe }
		Should -Invoke Start-FancyZones -Times 1 -Exactly -ParameterFilter { $ForceRestart -and $MaxWaitSeconds -eq 20 }
		Should -Invoke Start-FancyZones -Times 1 -Exactly -ParameterFilter { -not $ForceRestart -and $MaxWaitSeconds -eq 8 }
		Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 350 }
		Should -Invoke Remove-VirtualDesktops -Times 1 -Exactly
		Should -Invoke Clear-FancyZonesCache -Times 1 -Exactly
		Should -Invoke Clear-MonitorCache -Times 1 -Exactly
		Should -Invoke Clear-WindowCache -Times 1 -Exactly
	}
}
