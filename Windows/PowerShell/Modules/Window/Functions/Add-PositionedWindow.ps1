function Add-PositionedWindow {
	<#
	.SYNOPSIS
		Adds a window handle to the positioned windows tracking set.

	.DESCRIPTION
		Registers a window handle as having been positioned by Set-WindowLayouts.
		Stores the expected window state (position, dimensions, title) for validation
		before snapping. This allows Snap-AllWindows to verify windows are still in
		the expected state and retry positioning if needed.

	.PARAMETER WindowHandle
		The IntPtr handle of the window to track.

	.PARAMETER ExpectedX
		The expected X position of the window.

	.PARAMETER ExpectedY
		The expected Y position of the window.

	.PARAMETER ExpectedWidth
		The expected width of the window.

	.PARAMETER ExpectedHeight
		The expected height of the window.

	.PARAMETER WindowTitle
		The title of the window for identification.

	.PARAMETER DesktopNumber
		The virtual desktop number (0-based) where the window was moved.

	.PARAMETER ExpectedProcessName
		Optional process name fingerprint captured during positioning.

	.PARAMETER ExpectedProcessId
		Optional process ID fingerprint captured during positioning.

	.EXAMPLE
		Add-PositionedWindow -WindowHandle $window.Handle -ExpectedX 100 -ExpectedY 200 -ExpectedWidth 800 -ExpectedHeight 600 -WindowTitle "MyApp" -DesktopNumber 0
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[IntPtr]$WindowHandle,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedX,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedY,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedWidth,

		[Parameter(Mandatory = $true)]
		[int]$ExpectedHeight,

		[Parameter(Mandatory = $true)]
		[string]$WindowTitle,

		[Parameter()]
		[int]$DesktopNumber = 0,

		[Parameter()]
		[string]$ExpectedProcessName,

		[Parameter()]
		[uint32]$ExpectedProcessId = 0
	)

	if (-not $script:PositionedWindowHandles) {
		$script:PositionedWindowHandles = [System.Collections.ArrayList]::new()
	}

	# Check if handle already exists and remove it (to update with new expected state)
	$existingIndex = -1
	for ($i = 0; $i -lt $script:PositionedWindowHandles.Count; $i++) {
		if ($script:PositionedWindowHandles[$i].Handle -eq $WindowHandle) {
			$existingIndex = $i
			break
		}
	}

	if ($existingIndex -ge 0) {
		$script:PositionedWindowHandles.RemoveAt($existingIndex)
	}

	# Add window state
	$windowState = @{
		Handle         = $WindowHandle
		ExpectedX      = $ExpectedX
		ExpectedY      = $ExpectedY
		ExpectedWidth  = $ExpectedWidth
		ExpectedHeight = $ExpectedHeight
		WindowTitle    = $WindowTitle
		DesktopNumber  = $DesktopNumber
		ProcessName    = $ExpectedProcessName
		ProcessId      = $ExpectedProcessId
	}

	$script:PositionedWindowHandles.Add($windowState) > $null

	Write-LogDebug "      ✓ Added window [$WindowTitle] (handle: $WindowHandle) to positioned windows tracking at ($ExpectedX, $ExpectedY) ${ExpectedWidth}x${ExpectedHeight} on desktop $DesktopNumber" -Style Success
}
