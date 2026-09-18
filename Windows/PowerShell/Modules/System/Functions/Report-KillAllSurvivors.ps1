function Report-KillAllSurvivors {
	<#
	.SYNOPSIS
		Audits what is still on screen after a Kill-All run and reports it.

	.DESCRIPTION
		The closing check of Kill-All. Once the browser, visible-window and named-process steps
		have all run, nothing that is not deliberately excluded should still own a window. This
		re-enumerates the visible, titled application windows (Get-VisibleWindowProcess), drops
		the ones the run was told to leave alone - processes named in
		Configuration.Universal.VisibleWindowExclusions and windows matching an -Exclude pattern
		(matched by title or process name through Test-WindowTitleMatch) - and reports whatever
		remains as a warning with one line per window.

		Browser windows are NOT exempt here: Terminate-AllBrowserProcesses closes them gracefully
		and waits for them to go, so a browser window still standing at this point is a genuine
		survivor (typically a dialog waiting for an answer) and the user should know.

		Returns the survivors so the caller can word its own closing line; prints nothing when
		there are none.

	.PARAMETER Exclude
		The -Exclude patterns the Kill-All run was given. Windows matching them were meant to
		survive and are not reported.

	.OUTPUTS
		One object per surviving window: ProcessName, Id, Title. Empty when the run was clean.

	.EXAMPLE
		$survivors = @(Report-KillAllSurvivors -Exclude $Exclude)
		if ($survivors.Count -eq 0) { Write-LogSuccess "Kill All finished successfully!" }
	#>
	[CmdletBinding()]
	[OutputType([object[]])]
	param(
		[Parameter()]
		[string[]]$Exclude
	)

	$configuredExclusions = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
	foreach ($exclusion in @(Get-ConfigSetting -Path 'Universal.VisibleWindowExclusions' -Default @())) {
		$null = $configuredExclusions.Add($exclusion)
	}

	$survivors = @()
	foreach ($process in @(Get-VisibleWindowProcess)) {
		if ($configuredExclusions.Contains($process.ProcessName)) { continue }

		foreach ($title in @($process.WindowTitles)) {
			if ($Exclude -and (Test-WindowTitleMatch -ProcessName $process.ProcessName -WindowTitle $title -Patterns $Exclude)) {
				continue
			}

			$survivors += [PSCustomObject]@{
				ProcessName = $process.ProcessName
				Id          = $process.Id
				Title       = $title
			}
		}
	}

	if ($survivors.Count -gt 0) {
		Write-LogWarning "$($survivors.Count) window(s) survived the cleanup:"
		Write-LogList -Items @($survivors | ForEach-Object { "$($_.Title) ($($_.ProcessName), PID $($_.Id))" })
	}

	return $survivors
}
