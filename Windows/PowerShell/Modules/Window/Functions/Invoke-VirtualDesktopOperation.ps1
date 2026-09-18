function Invoke-VirtualDesktopOperation {
	<#
	.SYNOPSIS
		Runs one call against the VirtualDesktop COM cmdlets, recovering a stale session once.

	.DESCRIPTION
		The one seam between this repository and the third-party VirtualDesktop module. Every
		Window function that needs the desktop manager goes through here instead of calling
		Switch-Desktop, Get-DesktopCount, Move-Window and the rest directly, so the knowledge of
		how that module fails lives in exactly one place:

		  - The module is imported lazily (Import-VirtualDesktopModule); a machine without it
		    gets one clear exception rather than a "command not found" from deep inside a caller.
		  - With -Probe, the live RPC endpoint is checked first (Get-RpcRetryPolicy) and repaired
		    before the first attempt - the preflight the long-running cleanups used to do themselves.
		  - An RPC failure (0x800706BA and friends, classified by Test-RpcUnavailableError through
		    the InnerException chain and HRESULT) means this process holds COM proxies to a shell
		    that is gone: the module compiles its proxies once per process and caches them, so
		    the failure repeats forever unless the proxies are reconnected. Reset-VirtualDesktopState
		    does that, then the operation is retried with exponential backoff.
		  - Any other error is the caller's business (a window that closed mid-lookup, an index
		    out of range) and is rethrown at once, untouched.
		  - When the attempts are exhausted the last error is thrown. Callers never see a silent
		    $null or $false from a broken session - that is how a stale count of one desktop once
		    made every window move report "out of range" on a screen showing three.

	.PARAMETER Operation
		The scriptblock to run. It calls the VirtualDesktop cmdlets directly; its output is the
		function's output.

	.PARAMETER Label
		What the operation is, for the debug log and the RPC preflight message.

	.PARAMETER MaxAttempts
		How many times an RPC-classified failure is retried after a state reset. Default 3.

	.PARAMETER InitialDelayMs
		Backoff before the second attempt, doubled each time. Default 200.

	.PARAMETER Probe
		Verify and repair the live RPC endpoint before the first attempt. Use it in front of a
		long sequence of desktop operations (creating or removing several desktops), not per call.

	.OUTPUTS
		Whatever the operation returns.

	.EXAMPLE
		$count = [int](Invoke-VirtualDesktopOperation -Operation { Get-DesktopCount } -Label 'counting desktops')

	.EXAMPLE
		Invoke-VirtualDesktopOperation -Operation { $null = Switch-Desktop -Desktop 2 -ErrorAction Stop } -Label 'switching desktop'
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[scriptblock]$Operation,

		[Parameter()]
		[string]$Label = 'virtual desktop operation',

		[Parameter()]
		[ValidateRange(1, 20)]
		[int]$MaxAttempts = 3,

		[Parameter()]
		[ValidateRange(0, 60000)]
		[int]$InitialDelayMs = 200,

		[Parameter()]
		[switch]$Probe
	)

	if (-not (Import-VirtualDesktopModule -Silent)) {
		throw "The VirtualDesktop module is not available - install it with: Install-Module -Name VirtualDesktop -Scope CurrentUser (https://github.com/MScholtes/PSVirtualDesktop)"
	}

	# The preflight repairs Windows RPC services and the live endpoint before a long sequence; it
	# also hands back the attempt budget it considers sane for the current state.
	$attempts = $MaxAttempts
	$delayMs = $InitialDelayMs
	if ($Probe -and (Get-Command Get-RpcRetryPolicy -ErrorAction SilentlyContinue)) {
		$policy = Get-RpcRetryPolicy -OperationLabel $Label -MaxAttempts $MaxAttempts -InitialDelayMs $InitialDelayMs -Probe
		if ($policy) {
			$attempts = [int]$policy.MaxAttempts
			$delayMs = [int]$policy.InitialDelayMs
		}
	}

	for ($attempt = 1; $attempt -le $attempts; $attempt++) {
		try {
			return & $Operation
		}
		catch {
			$errorRecord = $_
			$isRpcFailure = [bool](Test-RpcUnavailableError $errorRecord)
			if (-not $isRpcFailure -or $attempt -ge $attempts) {
				throw
			}

			Write-LogDebug "  RPC endpoint unavailable while $Label (attempt $attempt/$attempts) - reconnecting the VirtualDesktop session before retrying" -Style Warning -NoLeadingNewline
			[void](Reset-VirtualDesktopState)

			if ($delayMs -gt 0) {
				Start-Sleep -Milliseconds ($delayMs * [math]::Pow(2, $attempt - 1))
			}
		}
	}
}
