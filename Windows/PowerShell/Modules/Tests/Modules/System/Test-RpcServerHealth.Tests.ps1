#Requires -Modules Pester

BeforeAll {
	$ModuleRoot = (Get-RepositoryPath).Modules
	$FunctionsPath = Join-Path $ModuleRoot "System\Functions"

	. "$FunctionsPath\Test-RpcServerHealth.ps1"
}

Describe "Test-RpcServerHealth" {
	BeforeEach {
		Mock Write-Host { }
	}

	It "returns false when any required service is not running" {
		Mock Get-Service {
			if ($Name -eq "RpcSs") {
				[PSCustomObject]@{ Status = "Stopped" }
			}
			else {
				[PSCustomObject]@{ Status = "Running" }
			}
		}

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs", "DcomLaunch")
		$result | Should -BeFalse
	}

	It "returns true when all required services are running" {
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs", "DcomLaunch", "RpcEptMapper")
		$result | Should -BeTrue
	}

	It "returns true when the live probe succeeds" {
		$script:probeJob = [PSCustomObject]@{ Id = 1; State = "Completed" }
		function Start-Job { param([scriptblock]$ScriptBlock) $script:probeJob }
		function Wait-Job { param($Job, $Timeout) $Job }
		function Receive-Job { param($Job) [PSCustomObject]@{ Success = $true; Error = $null } }
		function Remove-Job { param($Job, [switch]$Force) }
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe
		$result | Should -BeTrue
	}

	It "returns false when the live probe reports RPC unavailable" {
		$script:probeJob = [PSCustomObject]@{ Id = 1; State = "Completed" }
		function Start-Job { param([scriptblock]$ScriptBlock) $script:probeJob }
		function Wait-Job { param($Job, $Timeout) $Job }
		function Receive-Job { param($Job) [PSCustomObject]@{ Success = $false; Error = "The RPC server is unavailable. (0x800706BA)" } }
		function Remove-Job { param($Job, [switch]$Force) }
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe
		$result | Should -BeFalse
	}

	It "returns false when the live probe times out" {
		$script:probeJob = [PSCustomObject]@{ Id = 1; State = "Running" }
		function Start-Job { param([scriptblock]$ScriptBlock) $script:probeJob }
		function Wait-Job { param($Job, $Timeout) $null }
		function Stop-Job { param($Job) }
		function Remove-Job { param($Job, [switch]$Force) }
		Mock Get-Service { [PSCustomObject]@{ Status = "Running" } }

		$result = Test-RpcServerHealth -ServiceNames @("RpcSs") -Probe -ProbeTimeoutMs 100
		$result | Should -BeFalse
	}
}
