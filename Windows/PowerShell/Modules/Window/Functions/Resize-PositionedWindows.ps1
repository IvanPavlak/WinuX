function Resize-PositionedWindows {
	<#
	.SYNOPSIS
		Reapplies inset resize bounds to all tracked positioned windows.

	.DESCRIPTION
		Uses the same Resize-Windows target-bounds path as Set-WindowLayouts and
		Snap-AllWindows so every pre-snap resize comes from one source of truth.

	.PARAMETER InsetPercent
		The inset percentage applied on each side. Default is 0.05 (5 percent).

	.PARAMETER Tolerance
		Pixel tolerance for deciding whether a window is already at the adjusted
		pre-snap position. Default is the module's shared position verification tolerance.
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[ValidateRange(0.0, 0.49)]
		[double]$InsetPercent = 0.05,

		[Parameter()]
		[int]$Tolerance = $script:WindowModuleTolerances.PositionVerificationPx
	)

	if (-not $script:PositionedWindowHandles -or $script:PositionedWindowHandles.Count -eq 0) {
		return [PSCustomObject]@{
			ResizedCount  = 0
			SkippedCount  = 0
			FailedWindows = @()
		}
	}

	Write-LogDebug "[Resizing Positioned Windows Before Snap]"

	$resizedCount = 0
	$skippedCount = 0
	$failedWindows = [System.Collections.Generic.List[object]]::new()

	foreach ($windowState in $script:PositionedWindowHandles) {
		$null = Resize-Windows `
			-WindowHandle $windowState.Handle `
			-TargetX $windowState.ExpectedX `
			-TargetY $windowState.ExpectedY `
			-TargetWidth $windowState.ExpectedWidth `
			-TargetHeight $windowState.ExpectedHeight `
			-InsetPercent $InsetPercent `
			-SkipIfAlreadyPositioned `
			-Tolerance $Tolerance
		$result = $script:LastResizeWindowsResult

		if ($result) {
			$resizedCount += $result.ResizedCount
			$skippedCount += $result.SkippedCount
			foreach ($failedWindow in $result.FailedWindows) {
				$failedWindows.Add($failedWindow)
			}
		}
	}

	Write-LogDebug "=> Pre-snap resize complete [$resizedCount] resized$(if ($skippedCount -gt 0) { ", $skippedCount skipped" })" -Style Success

	return [PSCustomObject]@{
		ResizedCount  = $resizedCount
		SkippedCount  = $skippedCount
		FailedWindows = $failedWindows
	}
}
