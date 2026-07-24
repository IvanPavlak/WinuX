function Terminate-WindowsTerminalTabs {
	<#
    .SYNOPSIS
        Closes Windows Terminal tabs.

    .DESCRIPTION
        Temporarily renames the current tab to a unique ID, then cycles through
        all other tabs using keyboard shortcuts (Ctrl+Tab). It closes any tab
        that does not match the unique ID. If -IncludeCurrent is specified,
        it also closes the current tab at the end.

    .PARAMETER IncludeCurrent
        If specified, the current tab will also be closed after all others are processed.

    .PARAMETER OnlyCurrent
        If specified, closes only the current (calling) tab without affecting any other tabs.
        Useful when a new terminal window has been opened and the original calling tab is redundant.

	.PARAMETER CloseWaitSeconds
		Waits before closing the current tab when `-OnlyCurrent` or `-IncludeCurrent`
		is used. This gives the caller time to read the final status output before the
		terminal closes.
    #>
	[CmdletBinding()]
	param(
		[Parameter()]
		[switch]$IncludeCurrent,

		[Parameter()]
		[switch]$OnlyCurrent,

		[Parameter()]
		[ValidateRange(0, 300)]
		[int]$CloseWaitSeconds = 0
	)

	$originalHostTitle = $Host.UI.RawUI.WindowTitle

	if ($OnlyCurrent) {
		Write-LogTitle "Closing current terminal tab" -BlankLineAfter
		try {
			if ($CloseWaitSeconds -gt 0) {
				Countdown -Seconds $CloseWaitSeconds
			}

			# Deterministic close path: exit the current shell process directly.
			# This avoids focus-dependent SendKeys/AppActivate behavior that can close
			# a different tab when another app/window currently has focus.
			Write-LogDebug "Closing current shell via process exit seam" -Style Success

			Invoke-TerminateWindowsTerminalTabsExit
		}
		catch {
			Write-LogError "Error closing current terminal tab: $($_.Exception.Message)"
			Write-LogDebug "   Stack trace => $($_.ScriptStackTrace)" -Style Error
		}
		finally {
			try { $Host.UI.RawUI.WindowTitle = $originalHostTitle } catch {}
		}
		return
	}

	Write-LogTitle "Terminating Windows Terminal Tabs"

	# Identify the WindowsTerminal process actually hosting this shell by walking up the
	# parent-process chain from $PID (PS7's Process.Parent - no WMI/CIM roundtrips; the old
	# Get-CimInstance walk cost 0.2-0.8s and ran even for -OnlyCurrent, which never uses it -
	# hence resolved here, below the -OnlyCurrent early exit). Without this, when multiple WT
	# processes are running (e.g. elevated + non-elevated, or several user WT windows),
	# `Get-Process WindowsTerminal | Select-Object -First 1` may pick the wrong one, causing
	# Ctrl+W to be sent to our own window and killing the current shell mid-execution.
	$hostingWtPid = $null
	try {
		$walkProcess = Get-Process -Id $PID -ErrorAction Stop
		for ($i = 0; $i -lt 16 -and $walkProcess; $i++) {
			$parentProcess = $walkProcess.Parent
			if (-not $parentProcess) { break }
			if ($parentProcess.ProcessName -eq 'WindowsTerminal') {
				$hostingWtPid = [int]$parentProcess.Id
				break
			}
			$walkProcess = $parentProcess
		}
	}
	catch {
		Write-LogWarning "Warning: Failed to resolve hosting Windows Terminal process. Falling back to process-name detection."
		Write-LogDebug "   Details => $($_.Exception.Message)" -Style Warning
	}

	try {
		# Prefer the WT process hosting this shell (resolved above). Fall back to
		# first WindowsTerminal process only when the parent-chain walk failed.
		if ($hostingWtPid) {
			$wtProcess = Get-Process -Id $hostingWtPid -ErrorAction SilentlyContinue
		}
		if (-not $wtProcess) {
			$wtProcess = Get-Process | Where-Object { $_.ProcessName -eq "WindowsTerminal" } | Select-Object -First 1
		}

		if (-not $wtProcess) {
			Write-LogError "Failed => could not find a running Windows Terminal process to operate on (it may not be running, or process detection failed)."
			return
		}

		Add-Type -AssemblyName System.Windows.Forms
		[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.VisualBasic")

		$uniqueId = "ActiveTab_" + [Guid]::NewGuid().ToString()
		$Host.UI.RawUI.WindowTitle = $uniqueId
		Start-Sleep -Milliseconds 25

		# Restrict the "initial" (hosting) window to the resolved WT process so we
		# never mistake another WT window for ours when several are running.
		$allWtWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue)
		$initialWindow = $allWtWindows | Where-Object { $_.ProcessId -eq $wtProcess.Id } | Select-Object -First 1
		if (-not $initialWindow) { $initialWindow = $allWtWindows | Select-Object -First 1 }
		$startingTitle = if ($initialWindow) { $initialWindow.Title } else { $null }
		$currentWindowHandle = if ($initialWindow) { $initialWindow.Handle } else { [IntPtr]::Zero }

		if (-not $startingTitle) {
			Write-LogError "Failed => could not read the Windows Terminal window title (Get-WindowHandle returned no titled window for process ID [$($wtProcess.Id)]). Cannot identify which tab is current, so no tabs were closed."
			return
		}

		# Detect if the marker is reflected. Prefer the UIA tab titles: they identify OUR tab
		# precisely even when it is not the active tab (the window title only mirrors the
		# ACTIVE tab). Tabs opened with --suppressApplicationTitle will not reflect
		# $Host.UI.RawUI.WindowTitle changes at all - in that case fall back to using the
		# original (active) tab title as the identifier, as before.
		$uiaTabTitles = Get-WindowsTerminalTabTitles -WindowHandle $currentWindowHandle
		$markerVisible = if ($null -ne $uiaTabTitles) {
			[bool]($uiaTabTitles | Where-Object { $_ -like "*$uniqueId*" } | Select-Object -First 1)
		}
		else {
			$startingTitle -like "*$uniqueId*"
		}

		if (Test-LogVerbose) {
			Write-LogDebug "Marked current tab with unique ID => [$uniqueId]" -Style Success
			if (-not $markerVisible) {
				Write-LogDebug "Marker not reflected in tab titles (suppressApplicationTitle active), using original title [$startingTitle] as identifier" -Style Warning
			}
		}

		$closedTabs = @()
		$closeFailures = @()

		$isOurTabTitle = {
			param([string]$Title)
			if ($markerVisible) { $Title -like "*$uniqueId*" } else { $Title -eq $startingTitle }
		}

		# --- UIA-first pass over the current window: close every non-marked tab via its
		# close button - no focus change, no synthesized keystrokes (Ctrl+W typed into
		# whatever window has focus was the biggest input hazard of this function).
		# Any UIA miss falls back to the legacy Ctrl+Tab cycling pass below.
		$legacyPassNeeded = $true
		if ($null -ne $uiaTabTitles) {
			$legacyPassNeeded = $false

			foreach ($tabTitle in $uiaTabTitles) {
				if (& $isOurTabTitle $tabTitle) { continue }

				Write-LogDebug "-> Closing tab via UIA: [$tabTitle]" -Style Warning

				if (Close-WindowsTerminalTab -WindowHandle $currentWindowHandle -TabTitle $tabTitle) {
					$closedTabs += $tabTitle
				}
				else {
					$closeFailures += "Tab [$tabTitle] in the current window could not be closed via UI Automation"
					$legacyPassNeeded = $true
				}

				# Let WT remove the tab from the strip before invoking the next close button.
				Start-Sleep -Milliseconds 25
			}

			# Verify: any non-marked tab still present means the UIA pass missed something.
			$remainingTitles = Get-WindowsTerminalTabTitles -WindowHandle $currentWindowHandle
			if ($null -ne $remainingTitles) {
				$leftoverTabs = @($remainingTitles | Where-Object { -not (& $isOurTabTitle $_) })
				if ($leftoverTabs.Count -gt 0) {
					$legacyPassNeeded = $true
				}
			}
		}

		if ($legacyPassNeeded) {
			# Legacy fallback: focus the window and cycle with Ctrl+Tab, closing as we go.
			[Microsoft.VisualBasic.Interaction]::AppActivate($wtProcess.Id)
			Start-Sleep -Milliseconds 25

			$maxIterations = 50
			$iteration = 0
			$consecutiveMarkerHits = 0

			while ($iteration -lt $maxIterations) {
				$iteration++

				[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
				Start-Sleep -Milliseconds 25

				$currentWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
				$currentTitle = if ($currentWindow) { $currentWindow.Title } else { $null }

				if (-not $currentTitle) {
					Write-LogWarning "Warning: lost the Windows Terminal window title at iteration $iteration (window may have closed or focus was lost); stopping the tab-cycling pass early."
					break
				}

				Write-LogDebug "  Iteration $iteration => Current tab: [$currentTitle]" -Style Step

				$isCurrentTab = & $isOurTabTitle $currentTitle

				if ($isCurrentTab) {
					$consecutiveMarkerHits++
					Write-LogDebug "-> This is our marked tab (hit #$consecutiveMarkerHits)" -Style Success

					if ($consecutiveMarkerHits -ge 2) {
						Write-LogDebug "-> Cycled through all tabs - done!" -Style Success
						break
					}
					continue
				}

				$consecutiveMarkerHits = 0

				Write-LogDebug "-> Closing this tab" -Style Warning

				[System.Windows.Forms.SendKeys]::SendWait("^c")
				Start-Sleep -Milliseconds 25
				[System.Windows.Forms.SendKeys]::SendWait("^w")
				Start-Sleep -Milliseconds 25

				$postCloseWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
				$postCloseTitle = if ($postCloseWindow) { $postCloseWindow.Title } else { $null }

				if ($postCloseTitle -and $postCloseTitle -eq $currentTitle) {
					$closeFailures += "Active tab [$currentTitle] in the current window did not close on the initial attempt"
					Write-LogDebug "Warning: Close attempt did not change the active tab; [$currentTitle] is still active" -Style Warning
				}
				else {
					$closedTabs += $currentTitle
				}
			}
		}

		# Close tabs in other Windows Terminal windows
		# Ctrl+Tab only cycles within the current window, so other WT windows must be handled separately
		$otherWtWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
				Where-Object { $_.Handle -ne $currentWindowHandle })

		if ($otherWtWindows.Count -gt 0) {
			Write-LogDebug "  Found $($otherWtWindows.Count) other Windows Terminal window(s) to process"

			foreach ($otherWin in $otherWtWindows) {
				Write-LogDebug "  Processing other WT window: [$($otherWin.Title)]" -Style Step

				try {
					# UIA-first: close every tab of this window via its close button (the window
					# disappears when its last tab closes) - no focus change, no keystrokes.
					$otherWindowHandled = $false
					$otherTabTitles = Get-WindowsTerminalTabTitles -WindowHandle $otherWin.Handle

					if ($null -ne $otherTabTitles) {
						$otherWindowHandled = $true

						foreach ($tabTitle in $otherTabTitles) {
							Write-LogDebug "-> Closing tab via UIA: [$tabTitle]" -Style Warning

							if (Close-WindowsTerminalTab -WindowHandle $otherWin.Handle -TabTitle $tabTitle) {
								$closedTabs += $tabTitle
							}
							else {
								$closeFailures += "Tab [$tabTitle] in window [$($otherWin.Title)] could not be closed via UI Automation"
								$otherWindowHandled = $false
							}

							Start-Sleep -Milliseconds 25
						}

						# The window must be gone once its last tab closed - re-check with a
						# fresh enumeration (the window cache may still hold the dead handle).
						Start-Sleep -Milliseconds 75
						Clear-WindowCache
						$uiaSurvivor = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
							Where-Object { $_.Handle -eq $otherWin.Handle } |
							Select-Object -First 1
						if ($uiaSurvivor) {
							$otherWindowHandled = $false
						}
						else {
							Write-LogDebug "-> Window closed" -Style Success
						}
					}

					if ($otherWindowHandled) {
						continue
					}

					# Legacy fallback: focus the window and close tabs with Ctrl+W.
					[void][WindowModule.Native]::SetForegroundWindow($otherWin.Handle)
					Start-Sleep -Milliseconds 25

					# Close all tabs in this window by repeatedly sending Ctrl+W
					# When the last tab is closed, the window disappears
					$maxCloseAttempts = 30
					for ($c = 0; $c -lt $maxCloseAttempts; $c++) {
						# Check if the window still exists
						$stillExists = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
							Where-Object { $_.Handle -eq $otherWin.Handle }

						if (-not $stillExists) {
							Write-LogDebug "-> Window closed" -Style Success
							break
						}

						$tabTitle = $stillExists.Title
						Write-LogDebug "-> Closing tab: [$tabTitle]" -Style Warning

						[System.Windows.Forms.SendKeys]::SendWait("^c")
						Start-Sleep -Milliseconds 25
						[System.Windows.Forms.SendKeys]::SendWait("^w")
						Start-Sleep -Milliseconds 25

						$postCloseWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
							Where-Object { $_.Handle -eq $otherWin.Handle } |
							Select-Object -First 1

						if (-not $postCloseWindow) {
							$closedTabs += $tabTitle
							Write-LogDebug "-> Window closed" -Style Success
							break
						}

						if ($postCloseWindow.Title -eq $tabTitle) {
							$closeFailures += "Tab [$tabTitle] in window [$($otherWin.Title)] did not close on attempt $($c + 1)"
							Write-LogDebug "Warning: Close attempt did not change the active tab in this window; [$tabTitle] is still active" -Style Warning
						}
						else {
							$closedTabs += $tabTitle
						}
					}

					$survivingWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
						Where-Object { $_.Handle -eq $otherWin.Handle } |
						Select-Object -First 1
					if ($survivingWindow) {
						$closeFailures += "Window [$($otherWin.Title)] remained open after $maxCloseAttempts close attempt(s); active tab [$($survivingWindow.Title)]"
						Write-LogWarning "Warning: Window [$($otherWin.Title)] remained open after $maxCloseAttempts close attempt(s); active tab [$($survivingWindow.Title)]"
					}
				}
				catch {
					Write-LogError "Error processing Windows Terminal window [$($otherWin.Title)]: $($_.Exception.Message)"
					Write-LogDebug "Stack trace => $($_.ScriptStackTrace)" -Style Error
				}
			}
		}

		# The retry-verification pass below steals focus and types into windows - run it only
		# when something actually survived the close passes (or a failure was recorded). When
		# the UIA passes verified everything closed, skip it entirely: it used to add a
		# guaranteed ~0.3-0.5s of Ctrl+Tab cycling to every clean invocation.
		Start-Sleep -Milliseconds 50
		Clear-WindowCache
		$remainingAfterMainPass = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
				Where-Object { $_.Handle -ne $currentWindowHandle })
		$currentTitlesAfterPass = Get-WindowsTerminalTabTitles -WindowHandle $currentWindowHandle
		$currentWindowLeftovers = @()
		if ($null -ne $currentTitlesAfterPass) {
			$currentWindowLeftovers = @($currentTitlesAfterPass | Where-Object { -not (& $isOurTabTitle $_) })
		}
		$needsRetryVerification = ($closeFailures.Count -gt 0) -or
			($remainingAfterMainPass.Count -gt 0) -or
			($currentWindowLeftovers.Count -gt 0) -or
			($null -eq $currentTitlesAfterPass -and $legacyPassNeeded)

		if (-not $needsRetryVerification -and (Test-LogVerbose)) {
			Write-LogDebug "All tabs verified closed - skipping the SendKeys verification pass" -Style Success
		}

		# Retry verification: re-check and close any tabs that survived the initial pass.
		# SendKeys-based automation can miss inputs when the UI is busy (e.g., during ReRun-LastCommand).
		$maxRetries = 3
		for ($retryAttempt = 1; $needsRetryVerification -and $retryAttempt -le $maxRetries; $retryAttempt++) {
			$retryDelayMs = 50 * $retryAttempt
			Start-Sleep -Milliseconds $retryDelayMs

			# Check for remaining other WT windows
			$remainingOtherWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
					Where-Object { $_.Handle -ne $currentWindowHandle })

			foreach ($remainingWin in $remainingOtherWindows) {
				try {
					[void][WindowModule.Native]::SetForegroundWindow($remainingWin.Handle)
					Start-Sleep -Milliseconds $retryDelayMs

					for ($c = 0; $c -lt 30; $c++) {
						$stillExists = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
							Where-Object { $_.Handle -eq $remainingWin.Handle }

						if (-not $stillExists) { break }

						Write-LogDebug "[Retry $retryAttempt] Closing window tab: [$($stillExists.Title)]" -Style Warning

						[System.Windows.Forms.SendKeys]::SendWait("^c")
						Start-Sleep -Milliseconds $retryDelayMs
						[System.Windows.Forms.SendKeys]::SendWait("^w")
						Start-Sleep -Milliseconds $retryDelayMs

						$postCloseWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
							Where-Object { $_.Handle -eq $remainingWin.Handle } |
							Select-Object -First 1

						if (-not $postCloseWindow) {
							$closedTabs += $stillExists.Title
							break
						}

						if ($postCloseWindow.Title -eq $stillExists.Title) {
							$closeFailures += "Retry $retryAttempt could not close tab [$($stillExists.Title)] in window [$($remainingWin.Title)]"
							Write-LogDebug "Warning: Retry $retryAttempt did not change the active tab in window [$($remainingWin.Title)]" -Style Warning
						}
						else {
							$closedTabs += $stillExists.Title
						}
					}
				}
				catch {
					Write-LogError "Error during retry cleanup for window [$($remainingWin.Title)]: $($_.Exception.Message)"
					Write-LogDebug "Stack trace => $($_.ScriptStackTrace)" -Style Error
				}
			}

			# Re-activate our window and verify no other tabs remain
			try { [Microsoft.VisualBasic.Interaction]::AppActivate($wtProcess.Id) } catch {}
			Start-Sleep -Milliseconds $retryDelayMs

			$hasRemainingTabs = $false
			$retryConsecutiveHits = 0

			for ($v = 0; $v -lt 50; $v++) {
				[System.Windows.Forms.SendKeys]::SendWait("^{TAB}")
				Start-Sleep -Milliseconds $retryDelayMs

				$verifyWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
				$verifyTitle = if ($verifyWindow) { $verifyWindow.Title } else { $null }

				if (-not $verifyTitle) { break }

				$isOurTab = if ($markerVisible) {
					$verifyTitle -like "*$uniqueId*"
				}
				else {
					$verifyTitle -eq $startingTitle
				}

				if ($isOurTab) {
					$retryConsecutiveHits++
					if ($retryConsecutiveHits -ge 2) { break }
					continue
				}

				$retryConsecutiveHits = 0
				$hasRemainingTabs = $true

				Write-LogDebug "[Retry $retryAttempt] Closing missed tab: [$verifyTitle]" -Style Warning

				[System.Windows.Forms.SendKeys]::SendWait("^c")
				Start-Sleep -Milliseconds $retryDelayMs
				[System.Windows.Forms.SendKeys]::SendWait("^w")
				Start-Sleep -Milliseconds $retryDelayMs

				$postCloseVerifyWindow = Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue | Select-Object -First 1
				$postCloseVerifyTitle = if ($postCloseVerifyWindow) { $postCloseVerifyWindow.Title } else { $null }

				if ($postCloseVerifyTitle -and $postCloseVerifyTitle -eq $verifyTitle) {
					$closeFailures += "Retry $retryAttempt could not close active tab [$verifyTitle] in the current window"
					Write-LogDebug "Warning: Retry $retryAttempt did not change the active tab; [$verifyTitle] is still active" -Style Warning
				}
				else {
					$closedTabs += $verifyTitle
				}
			}

			$stillRemainingWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
					Where-Object { $_.Handle -ne $currentWindowHandle })

			if (-not $hasRemainingTabs -and $stillRemainingWindows.Count -eq 0) {
				if ((Test-LogVerbose) -and $retryAttempt -ge 1) {
					Write-LogDebug "All tabs verified closed (verification pass $retryAttempt)" -Style Success
				}
				break
			}

			if (Test-LogVerbose) {
				$remaining = @()
				if ($hasRemainingTabs) { $remaining += "unclosed tabs in current window" }
				if ($stillRemainingWindows.Count -gt 0) { $remaining += "$($stillRemainingWindows.Count) other window(s)" }
				Write-LogDebug "[Retry $retryAttempt/$maxRetries] Still remaining: $($remaining -join ', ')" -Style Warning
			}
		}

		$remainingOtherWindows = @(Get-WindowHandle -ProcessName "WindowsTerminal" -ErrorAction SilentlyContinue |
				Where-Object { $_.Handle -ne $currentWindowHandle })
		if ($remainingOtherWindows.Count -gt 0 -or $closeFailures.Count -gt 0) {
			Write-LogWarning "Warning: Windows Terminal cleanup left one or more tabs or windows open."
			$closeFailures |
				Select-Object -Unique |
				ForEach-Object {
					Write-Host -ForegroundColor DarkYellow "   • $_"
				}

			if ($remainingOtherWindows.Count -gt 0) {
				$remainingOtherWindows | ForEach-Object {
					Write-Host -ForegroundColor DarkYellow "   • Remaining window => [$($_.Title)]"
				}
			}
		}

		if ($IncludeCurrent) {
			Invoke-TerminateWindowsTerminalTabsIncludeCurrentCleanup -ClosedTabs $closedTabs -StartingTitle $startingTitle -OriginalHostTitle $originalHostTitle -CloseWaitSeconds $CloseWaitSeconds
			return
		}

		if ($closedTabs.Count -gt 0) {
			Write-LogSuccess "Closed [$($closedTabs.Count)] terminal tab(s)"
		}
		else {
			Write-LogWarning "No other terminal tabs to close"
		}
	}
	catch {
		Write-LogError "Error closing terminal tabs: $($_.Exception.Message)"
		Write-LogDebug "Stack trace => $($_.ScriptStackTrace)" -Style Error
	}
	finally {
		try {
			$Host.UI.RawUI.WindowTitle = $originalHostTitle
			#Set-Location -Path ([Environment]::GetFolderPath('Desktop'))
		}
		catch {}
	}
}
