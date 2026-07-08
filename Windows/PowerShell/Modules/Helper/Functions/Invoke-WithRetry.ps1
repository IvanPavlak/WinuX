function Invoke-WithRetry {
	<#
    .SYNOPSIS
        Execute a scriptblock with exponential backoff retry logic.

    .DESCRIPTION
        Attempts to run a scriptblock up to MaxAttempts times with exponential backoff delays.
        Useful for transient failures (network, temporary resource contention).

    .PARAMETER ScriptBlock
        The code to execute (required).

    .PARAMETER MaxAttempts
        Maximum number of attempts (default: 3).

    .PARAMETER InitialDelayMs
        Starting delay in milliseconds (default: 100). Doubles after each retry.

    .PARAMETER OnRetry
        Optional script block invoked after a failed attempt and before the next
        retry delay. Receives the ErrorRecord and the failed attempt number.

    .EXAMPLE
        Invoke-WithRetry -ScriptBlock { Invoke-RestMethod -Uri $url } -MaxAttempts 5
    #>
	param(
		[Parameter(Mandatory = $true)]
		[scriptblock]$ScriptBlock,

		[Parameter(Mandatory = $false)]
		[int]$MaxAttempts = 3,

		[Parameter(Mandatory = $false)]
		[int]$InitialDelayMs = 100,

		[Parameter(Mandatory = $false)]
		[scriptblock]$OnRetry
	)

	$attempt = 1
	$delay = $InitialDelayMs

	while ($attempt -le $MaxAttempts) {
		try {
			return & $ScriptBlock
		}
		catch {
			$errorRecord = $_
			if ($attempt -eq $MaxAttempts) {
				throw
			}

			if ($OnRetry) {
				try {
					$null = & $OnRetry $errorRecord $attempt
				}
				catch {
					# Recovery hooks are best-effort; preserve the original retry flow.
				}
			}

			Start-Sleep -Milliseconds $delay
			$delay *= 2  # Exponential backoff
			$attempt++
		}
	}
}
