function Get-WindowDesktopIndex {
	<#
	.SYNOPSIS
		Resolves which virtual desktop a window lives on, as a 0-based index.

	.DESCRIPTION
		Wraps the `Get-DesktopIndex (Get-DesktopFromWindow -Hwnd ...)` pair that answers "which
		desktop is this window on", with the guards that every caller of it needs: the VirtualDesktop
		module may not be loaded, and the lookup throws for windows that cannot be resolved at all.

		Returns -1 rather than $null or an exception for every "cannot tell" case, so callers can
		compare the result without null checks and never have to wrap the call in a try. Shell windows
		are the reason this matters in practice: "Windows Input Experience" (TextInputHost) always
		answers TYPE_E_ELEMENTNOTFOUND, and a window that closed mid-scan answers nothing at all.
		Neither is an error worth propagating - the window simply has no known desktop.

		Failures are not retried. A window that cannot be resolved on its own merits cannot succeed on
		a second attempt, and burning an RPC backoff ladder per window is exactly the cost
		Remove-VirtualDesktops was fixed to stop paying. A caller doing a whole-set scan that must
		tolerate genuine RPC failure should retry the scan, not the window.

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

	if (-not (Get-Command Get-DesktopFromWindow -ErrorAction SilentlyContinue)) {
		if (Get-Command Import-VirtualDesktopModule -ErrorAction SilentlyContinue) {
			[void](Import-VirtualDesktopModule -Silent)
		}
	}

	if (-not ((Get-Command Get-DesktopFromWindow -ErrorAction SilentlyContinue) -and
			(Get-Command Get-DesktopIndex -ErrorAction SilentlyContinue))) {
		return -1
	}

	try {
		$desktop = Get-DesktopFromWindow -Hwnd $WindowHandle.ToInt64()
		if (-not $desktop) { return -1 }

		$index = Get-DesktopIndex -Desktop $desktop
		if ($null -eq $index) { return -1 }

		return [int]$index
	}
	catch {
		return -1
	}
}
