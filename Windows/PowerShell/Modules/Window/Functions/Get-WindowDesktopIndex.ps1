function Get-WindowDesktopIndex {
	<#
	.SYNOPSIS
		Resolves which virtual desktop a window lives on, as a 0-based index.

	.DESCRIPTION
		Wraps the `Get-DesktopIndex (Get-DesktopFromWindow -Hwnd ...)` pair that answers "which
		desktop is this window on", run through Invoke-VirtualDesktopOperation, with the guards that
		every caller of it needs: the VirtualDesktop module may be missing, the lookup throws for
		windows that cannot be resolved at all, and a stale COM session must be reconnected rather
		than reported as "no desktop".

		Returns -1 rather than $null or an exception for every "cannot tell" case, so callers can
		compare the result without null checks and never have to wrap the call in a try. Shell windows
		are the reason this matters in practice: "Windows Input Experience" (TextInputHost) always
		answers TYPE_E_ELEMENTNOTFOUND, and a window that closed mid-scan answers nothing at all.
		Neither is an error worth propagating - the window simply has no known desktop.

		Only RPC failures are retried, and only by the seam: Invoke-VirtualDesktopOperation reconnects
		a stale COM session (Reset-VirtualDesktopState) and retries with backoff, then a desktop
		manager that is still unreachable reads as -1 here. A lookup that fails on its own merits is
		rethrown by the seam at once and answered with -1 - a window that cannot be resolved cannot
		succeed on a second attempt, and burning a backoff ladder per window is exactly the cost
		Remove-VirtualDesktops was fixed to stop paying. A caller doing a whole-set scan hands the
		whole scan to the seam, so a genuine RPC failure retries the scan, not the window.

	.PARAMETER WindowHandle
		Handle of the window to locate.

	.OUTPUTS
		[int] 0-based desktop index, or -1 when it cannot be determined.

	.EXAMPLE
		$index = Get-WindowDesktopIndex -WindowHandle $window.Handle
		if ($index -ge 0) { "window is on desktop $index" }

	.EXAMPLE
		$byDesktop = @(Get-WindowHandle) | Group-Object { Get-WindowDesktopIndex -WindowHandle $_.Handle }
		Groups every visible window by the desktop it sits on.
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[IntPtr]$WindowHandle
	)

	if ($WindowHandle -eq [IntPtr]::Zero) { return -1 }

	# -1 for everything that is not an answer: a window with no desktop (shell surfaces answer
	# that way), a lookup that failed on its own merits, and a desktop manager that stayed
	# unreachable after the operation seam's recovery. Callers treat -1 as "unknown".
	try {
		$index = Invoke-VirtualDesktopOperation -Operation {
			$desktop = Get-DesktopFromWindow -Hwnd $WindowHandle.ToInt64()
			if (-not $desktop) { return -1 }
			$resolved = Get-DesktopIndex -Desktop $desktop
			if ($null -eq $resolved) { return -1 }
			return [int]$resolved
		} -Label 'resolving the desktop of a window'
		if ($null -eq $index) { return -1 }
		return [int]$index
	}
	catch {
		return -1
	}
}
