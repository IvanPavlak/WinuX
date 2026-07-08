function Invoke-WithOptionalRetry {
	<#
	.SYNOPSIS
		Executes a script block with optional retry/backoff behavior.

	.DESCRIPTION
		Centralizes the common pattern:
		- if retry is enabled and Invoke-WithRetry is available, execute with
		  exponential backoff
		- otherwise execute the script block directly

		This avoids duplicated if/else branches in callers that need to run the
		same operation either with retries (RPC/COM transient failure handling)
		or without retries.

	.PARAMETER ScriptBlock
		The operation to execute.

	.PARAMETER MaxAttempts
		Maximum retry attempts when retry mode is enabled. Default is 3.

	.PARAMETER InitialDelayMs
		Initial retry delay in milliseconds. Default is 200.

	.PARAMETER EnableRetry
		When specified, attempts to use Invoke-WithRetry if available.

	.PARAMETER OnRetry
		Optional script block passed through to Invoke-WithRetry. Receives the
		ErrorRecord and failed attempt number after each failed attempt that will
		be retried.

	.EXAMPLE
		Invoke-WithOptionalRetry -EnableRetry -ScriptBlock { Get-DesktopList } -MaxAttempts 3 -InitialDelayMs 200

	.EXAMPLE
		Invoke-WithOptionalRetry -ScriptBlock { Get-DesktopList }
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[scriptblock]$ScriptBlock,

		[Parameter()]
		[int]$MaxAttempts = 3,

		[Parameter()]
		[int]$InitialDelayMs = 200,

		[Parameter()]
		[switch]$EnableRetry,

		[Parameter()]
		[scriptblock]$OnRetry
	)

	if ($EnableRetry -and (Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)) {
		if ($OnRetry) {
			return Invoke-WithRetry -ScriptBlock $ScriptBlock -MaxAttempts $MaxAttempts -InitialDelayMs $InitialDelayMs -OnRetry $OnRetry
		}

		return Invoke-WithRetry -ScriptBlock $ScriptBlock -MaxAttempts $MaxAttempts -InitialDelayMs $InitialDelayMs
	}

	return & $ScriptBlock
}
