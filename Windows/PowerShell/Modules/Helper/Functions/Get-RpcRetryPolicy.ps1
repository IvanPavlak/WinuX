function Get-RpcRetryPolicy {
	<#
	.SYNOPSIS
		Returns standard RPC retry settings and runs optional RPC preflight recovery.

	.DESCRIPTION
		Centralizes the repeated RPC safety pattern used by VirtualDesktop-heavy
		functions:
		- provides shared retry defaults (`MaxAttempts`, `InitialDelayMs`)
		- performs RPC preflight via Test-RpcServerHealth (service-status by default,
		  or live probe when -Probe is specified)
		- if unhealthy, runs Repair-RpcServer before the caller proceeds

		Returns a hashtable with `MaxAttempts` and `InitialDelayMs`.

	.PARAMETER OperationLabel
		Human-readable operation label used in preflight output.

	.PARAMETER MaxAttempts
		Maximum retry attempts callers should use for Invoke-WithRetry.
		Default is 3.

	.PARAMETER InitialDelayMs
		Initial retry delay in milliseconds callers should use for Invoke-WithRetry.
		Default is 200.

	.PARAMETER Probe
		When specified, preflight uses Test-RpcServerHealth -Probe to verify live
		RPC endpoint responsiveness instead of only checking service status.

	.EXAMPLE
		$rpcPolicy = Get-RpcRetryPolicy -OperationLabel "desktop cleanup"
		$rpcMaxAttempts = $rpcPolicy.MaxAttempts
		$rpcInitialDelayMs = $rpcPolicy.InitialDelayMs
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[string]$OperationLabel = "operation",

		[Parameter()]
		[int]$MaxAttempts = 3,

		[Parameter()]
		[int]$InitialDelayMs = 200,

		[Parameter()]
		[switch]$Probe
	)

	$policy = @{
		MaxAttempts    = [Math]::Max(1, $MaxAttempts)
		InitialDelayMs = [Math]::Max(1, $InitialDelayMs)
	}

	if (Get-Command Test-RpcServerHealth -ErrorAction SilentlyContinue) {
		if ($Probe) {
			$rpcHealthy = Test-RpcServerHealth -Probe
		}
		else {
			$rpcHealthy = Test-RpcServerHealth
		}

		if (-not $rpcHealthy -and (Get-Command Repair-RpcServer -ErrorAction SilentlyContinue)) {
			if ($Probe) {
				Write-LogWarning "RPC endpoint unresponsive - running recovery retry loop before $OperationLabel..."
			}
			else {
				Write-LogWarning "RPC services not running - running recovery retry loop before $OperationLabel..."
			}
			[void](Repair-RpcServer)
		}
	}

	return $policy
}
