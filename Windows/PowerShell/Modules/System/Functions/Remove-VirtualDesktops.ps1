# VirtualDesktop RPC can go stale after COM-heavy desktop operations; cleanup uses
# live endpoint probing plus current-session module reset between RPC retries.
function Remove-VirtualDesktops {
	<#
	.SYNOPSIS
		Removes virtual desktops - all except the first, or only empty ones.

	.DESCRIPTION
		By default, removes all virtual desktops except desktop 0, effectively resetting to a single desktop state.

		With -EmptyOnly, removes only virtual desktops that have no visible windows on them. This is useful for
		ensuring idempotency when retrying workspace setups (e.g., alongside mode), where a previous failed run
		may have created extra desktops that remain empty. Empty desktops are removed from right to left to
		preserve index ordering. At least one desktop is always preserved (Windows requires a minimum of one).
		If desktop 0 is empty but others have windows, desktop 0 is removed last and remaining desktops shift left.

		Window detection uses Get-WindowHandle (EnumWindows-based, from the Window module) when available,
		which reliably captures ALL visible windows across all desktops - including multiple browser windows,
		multiple VSCode windows, etc. Falls back to Get-Process MainWindowHandle if the Window module isn't
		loaded, though this fallback only sees one window per process and may incorrectly treat desktops
		with secondary windows as empty.

		Desktop counts come from Get-DesktopCount rather than Get-DesktopList: only the count is ever used,
		and Get-DesktopList pays a per-desktop registry name lookup plus a wallpaper query over COM.

		Before cleanup, runs Test-RpcServerHealth -Probe so the preflight verifies
		the live VirtualDesktop RPC endpoint instead of only checking that Windows
		RPC services are Running. If preflight recovery unloads the VirtualDesktop
		module, cmdlets are rehydrated before cleanup continues. VirtualDesktop
		operations are retried with exponential backoff; if an operation reports
		0x800706BA / 0x800706BE, the current session's VirtualDesktop module state
		is reset before the next attempt to recover stale COM proxies without
		requiring a fresh shell.

		The -EmptyOnly occupancy scan is retried as a whole rather than per window. A per-window lookup
		that fails on its own merits - a window closed mid-scan, or a shell window such as "Windows Input
		Experience" that always answers TYPE_E_ELEMENTNOTFOUND - can never succeed on a retry, so it is
		skipped immediately instead of sleeping through a backoff ladder that cost seconds per run. Only a
		genuine RPC failure restarts the scan, after the ladder has reset this session's COM state. If RPC
		is still unavailable once the ladder is exhausted, the cleanup aborts and returns $false rather
		than treating unknowable occupancy as "empty".

		With -Index, removes exactly the named 0-based desktop indexes regardless of whether anything is
		still on them, highest first so the remaining targets do not shift. Windows relocates windows
		off a removed desktop rather than closing them. This is the mode Close-Workspace uses: a
		workspace's own desktops go with it, and the one window a teardown cannot close first - the
		shell it is running in - is moved rather than stranded on a desktop nothing will ever sweep.
		-Index wins over -EmptyOnly. At least one desktop is always kept, and an index that no longer
		exists is skipped. Supplying -Index with nothing usable in it (an empty array, or only
		negative values) removes NOTHING - it is never treated as "no index was given", which would
		turn asking for nothing into removing every desktop.

		All three modes return nothing on success and $false on failure.

	.PARAMETER EmptyOnly
		When specified, only removes virtual desktops that have no visible windows on them.
		Iterates from the rightmost desktop toward desktop 0. At least one desktop is always kept.

	.PARAMETER Index
		0-based desktop indexes to remove outright, whether or not they still hold windows. Removed
		highest first. Takes precedence over -EmptyOnly.

	.EXAMPLE
		Remove-VirtualDesktops
		# Removes all desktops except desktop 0

	.EXAMPLE
		Remove-VirtualDesktops -EmptyOnly
		# Removes only desktops that have no windows on them

	.EXAMPLE
		Remove-VirtualDesktops -Index 3, 4, 5
		# Removes a workspace's own three desktops, occupied or not
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param (
		[Parameter()]
		[switch]$EmptyOnly,

		[Parameter()]
		[int[]]$Index
	)

	$explicitIndexes = @($Index | Where-Object { $null -ne $_ -and $_ -ge 0 } | Sort-Object -Unique -Descending)

	# Keyed on whether -Index was SUPPLIED, not on whether it yielded anything usable. Deciding it by
	# the resolved count would make "-Index @()" - or an index list that filtered down to nothing -
	# fall through to the default mode, i.e. silently turn "remove these desktops" into "remove EVERY
	# desktop". Asking for nothing must do nothing.
	$byIndex = $PSBoundParameters.ContainsKey('Index')

	$modeLabel = if ($byIndex) {
		if ($explicitIndexes.Count -gt 0) { " (index $((@($explicitIndexes | Sort-Object)) -join ', '))" } else { ' (no usable index)' }
	}
	elseif ($EmptyOnly) { ' (empty only)' }
	else { '' }

	Write-LogTitle "Removing Virtual Desktops$modeLabel"

	if (Get-Command Import-VirtualDesktopModule -ErrorAction SilentlyContinue) {
		if (-not (Import-VirtualDesktopModule -Silent)) {
			Write-LogDebug "Could not remove virtual desktops => [VirtualDesktop module is unavailable]" -Style Error
			return $false
		}
	}

	$rpcPolicy = if (Get-Command Get-RpcRetryPolicy -ErrorAction SilentlyContinue) {
		Get-RpcRetryPolicy -OperationLabel "desktop cleanup" -MaxAttempts 5 -InitialDelayMs 250 -Probe
	}
	else {
		@{ MaxAttempts = 5; InitialDelayMs = 250 }
	}
	if (-not (Get-Command Get-DesktopCount -ErrorAction SilentlyContinue)) {
		if (Get-Command Reset-VirtualDesktopState -ErrorAction SilentlyContinue) {
			[void](Reset-VirtualDesktopState)
		}
		elseif (Get-Command Import-VirtualDesktopModule -ErrorAction SilentlyContinue) {
			[void](Import-VirtualDesktopModule -Silent)
		}
		else {
			Import-Module VirtualDesktop -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
		}
	}
	$rpcMaxAttempts = [int]$rpcPolicy.MaxAttempts
	$rpcInitialDelayMs = [int]$rpcPolicy.InitialDelayMs
	$useRetry = [bool](Get-Command Invoke-WithRetry -ErrorAction SilentlyContinue)
	$useOptionalRetryHelper = [bool](Get-Command Invoke-WithOptionalRetry -ErrorAction SilentlyContinue)
	$useRpcErrorClassifier = [bool](Get-Command Test-RpcUnavailableError -ErrorAction SilentlyContinue)
	$rpcUnavailablePattern = '0x800706BA|0x800706BE|0x80010108|RPC server is unavailable|The remote procedure call failed'

	# Test-RpcUnavailableError walks the InnerException chain and HRESULTs, so
	# wrapped RPC failures (e.g. a TypeInitializationException around the COM
	# error) still classify correctly; the message match is the fallback.
	$testRpcFailure = {
		param($ErrorRecord)

		if ($useRpcErrorClassifier) {
			return [bool](Test-RpcUnavailableError $ErrorRecord)
		}

		$errorMessage = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
		return [bool]($errorMessage -match $rpcUnavailablePattern)
	}
	$recoverVirtualDesktopRpc = {
		param($ErrorRecord, [int]$Attempt)

		if (-not (& $testRpcFailure $ErrorRecord)) {
			return
		}

		Write-LogDebug "  RPC endpoint unavailable during desktop cleanup; resetting VirtualDesktop state before retry $($Attempt + 1)" -Style Warning -NoLeadingNewline

		if (Get-Command Reset-VirtualDesktopState -ErrorAction SilentlyContinue) {
			[void](Reset-VirtualDesktopState)
			return
		}

		try {
			Remove-Module -Name VirtualDesktop -Force -ErrorAction SilentlyContinue
			Import-Module VirtualDesktop -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
		}
		catch {
			# Best-effort recovery before the next retry attempt.
		}
	}
	$invokeDesktopOperation = {
		param([scriptblock]$Operation)

		if ($useOptionalRetryHelper) {
			return Invoke-WithOptionalRetry -EnableRetry:$useRetry -ScriptBlock $Operation -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs -OnRetry $recoverVirtualDesktopRpc
		}

		if ($useRetry) {
			return Invoke-WithRetry -ScriptBlock $Operation -MaxAttempts $rpcMaxAttempts -InitialDelayMs $rpcInitialDelayMs -OnRetry $recoverVirtualDesktopRpc
		}

		return & $Operation
	}

	try {
		# Track removed desktops so the normal-mode summary can list them.
		$removedDesktops = @()
		$desktopCount = [int](& $invokeDesktopOperation { Get-DesktopCount })

		if ($byIndex) {
			if ($explicitIndexes.Count -eq 0) {
				Write-LogDebug "No usable desktop index requested - nothing to remove" -Style Warning
				return
			}

			# Named desktops, removed highest index first so the lower ones this call still has to
			# remove do not shift out from under it. Windows relocates whatever is still on a removed
			# desktop to an adjacent one rather than closing it, which is the wanted behaviour for the
			# one window a workspace teardown cannot close before it removes its desktops: the shell
			# it is running in. Anything else still standing there refused a WM_CLOSE and is reported
			# by the caller.
			foreach ($desktopToRemove in $explicitIndexes) {
				if ($desktopCount -le 1) {
					Write-LogDebug " Only one desktop left - keeping desktop [0]" -Style Warning -NoLeadingNewline
					break
				}

				if ($desktopToRemove -ge $desktopCount) {
					Write-LogDebug " Desktop [$desktopToRemove] no longer exists - skipping" -Style Warning -NoLeadingNewline
					continue
				}

				Write-LogDebug " Removing desktop [$desktopToRemove]!" -Style Error -NoLeadingNewline

				& $invokeDesktopOperation { Remove-Desktop -Desktop $desktopToRemove -Verbose:$false -ErrorAction Stop } | Out-Null
				$removedDesktops += "Desktop [$desktopToRemove]"
				$desktopCount = [int](& $invokeDesktopOperation { Get-DesktopCount })
			}

			if (-not (Test-LogVerbose) -and $removedDesktops.Count -gt 0) {
				Write-LogSuccess "Removed $($removedDesktops.Count) virtual desktop(s)!"
				Write-LogList -Items $removedDesktops
			}

			# Nothing is returned, exactly as the other two modes behave. Reporting which indexes went
			# would only be worth it for a caller re-mapping stored desktop indexes, and there is no
			# such caller: Close-Workspace resolves a workspace's desktops live from window handles
			# precisely so that no index is ever stored to go stale.
			return
		}

		if ($EmptyOnly) {
			if ($desktopCount -le 1) {
				Write-LogDebug "Only one desktop exists - nothing to clean up" -Style Success
				return
			}

			# Get all visible windows and map them to their desktops
			# Prefer Get-WindowHandle (Window module, EnumWindows-based) - captures ALL visible windows
			# including multiple windows of the same process on different desktops (e.g., two VSCode windows)
			# Falls back to Get-Process MainWindowHandle which only returns one handle per process
			$windowHandles = @()
			if (Get-Command Get-WindowHandle -ErrorAction SilentlyContinue) {
				$allWindows = Get-WindowHandle -ErrorAction SilentlyContinue
				if ($allWindows) {
					$windowHandles = @($allWindows.Handle | Where-Object { $null -ne $_ -and $_ -ne [IntPtr]::Zero })
				}
			}
			else {
				Write-LogDebug " Get-WindowHandle not available - falling back to Get-Process (may miss secondary windows)" -Style Warning
				$windowHandles = @(Get-Process -ErrorAction SilentlyContinue |
						Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
						Select-Object -ExpandProperty MainWindowHandle)
			}

			# The set of desktop indices that have at least one visible window.
			$occupiedDesktops = New-Object 'System.Collections.Generic.HashSet[int]'

			# One retry ladder for the whole scan instead of one per window: per-window
			# failures are permanent (see the RPC notes in the help), so retrying them
			# only burns backoff delays. A rescan restarts from a clean set.
			$scanWindowOccupancy = {
				$occupiedDesktops.Clear()

				# Get-DesktopIndex re-enumerates every desktop over COM on each call, so
				# resolve each distinct desktop once and reuse the answer for every other
				# window sitting on it.
				$indexByDesktop = @{}

				foreach ($hwnd in $windowHandles) {
					$desktop = $null
					try {
						$desktop = Get-DesktopFromWindow -Hwnd $hwnd -ErrorAction Stop
					}
					catch {
						# Window closed between enumeration and lookup, or a shell window the
						# desktop manager refuses to place - skip it; only RPC failures are
						# worth another attempt.
						if (& $testRpcFailure $_) { throw }
					}

					if ($desktop) {
						$index = $indexByDesktop[$desktop]
						if ($null -eq $index) {
							try {
								$index = [int](Get-DesktopIndex -Desktop $desktop -ErrorAction Stop)
							}
							catch {
								if (& $testRpcFailure $_) { throw }
								$index = -1
							}
							$indexByDesktop[$desktop] = $index
						}

						if ($index -ge 0) {
							[void]$occupiedDesktops.Add($index)
						}
					}

					# Every desktop is spoken for - the remaining windows cannot change the outcome.
					if ($occupiedDesktops.Count -ge $desktopCount) {
						break
					}
				}
			}

			$occupancyTrusted = $true
			try {
				[void](& $invokeDesktopOperation $scanWindowOccupancy)
			}
			catch {
				if (-not (& $testRpcFailure $_)) { throw }
				$occupancyTrusted = $false
			}

			if (-not $occupancyTrusted) {
				# With occupancy unknowable, removing "empty" desktops could remove occupied
				# ones - abort the cleanup entirely and report failure once.
				Write-LogDebug "Aborting empty-desktop cleanup - VirtualDesktop RPC stayed unavailable after retry recovery (window occupancy cannot be trusted)" -Style Error
				return $false
			}

			Write-LogDebug " Found $($windowHandles.Count) window(s), $($occupiedDesktops.Count) occupied desktop(s) out of $desktopCount" -Style Success

			$removedCount = 0

			# Remove empty desktops from right to left (right-to-left preserves indices for remaining desktops)
			for ($i = $desktopCount - 1; $i -ge 1; $i--) {
				if (-not $occupiedDesktops.Contains($i)) {
					Write-LogDebug " Removing empty desktop [$i]!" -Style Error -NoLeadingNewline
					& $invokeDesktopOperation { Remove-Desktop -Desktop $i -Verbose:$false -ErrorAction Stop } | Out-Null
					$removedCount++
					$removedDesktops += "Desktop [$i]"
				}
				else {
					Write-LogDebug " Desktop [$i] has windows!" -Style Warning -NoLeadingNewline
				}
			}

			# Handle desktop 0: remove it if empty AND at least one other desktop still exists
			# When desktop 0 is removed, Windows shifts all remaining desktops left (desktop 1 becomes 0, etc.)
			# The live count is only re-read when desktop 0 is actually a removal candidate.
			if ($occupiedDesktops.Contains(0)) {
				Write-LogDebug " Desktop [0] has windows!" -Style Warning
			}
			else {
				$remainingDesktops = [int](& $invokeDesktopOperation { Get-DesktopCount })
				if ($remainingDesktops -gt 1) {
					Write-LogDebug " Removing empty desktop [0]!" -Style Error -NoLeadingNewline
					& $invokeDesktopOperation { Remove-Desktop -Desktop 0 -Verbose:$false -ErrorAction Stop } | Out-Null
					$removedCount++
					$removedDesktops += "Desktop [0]"
				}
				else {
					Write-LogDebug " Desktop [0] is the last desktop - keeping" -Style Warning
				}
			}

			Write-LogDebug "Removed $removedCount empty virtual desktop(s)" -Style Success
		}
		else {
			# Original behavior: remove all except desktop 0
			Write-LogDebug " Found $desktopCount desktop(s) to clean up; keeping desktop [0] and removing the rest" -Style Success

			while ($desktopCount -gt 1) {
				$desktopToRemove = $desktopCount - 1

				Write-LogDebug " Removing desktop [$desktopToRemove]!" -Style Error -NoLeadingNewline

				& $invokeDesktopOperation { Remove-Desktop -Desktop $desktopToRemove -Verbose:$false -ErrorAction Stop } | Out-Null
				$removedDesktops += "Desktop [$desktopToRemove]"
				$desktopCount = [int](& $invokeDesktopOperation { Get-DesktopCount })
			}

			Write-LogDebug " Desktop [0] is the last desktop - keeping" -Style Warning -NoLeadingNewline

			Write-LogDebug "Removed Virtual Desktops successfully!" -Style Success
		}

		# Normal-mode summary + bulleted list of the desktops removed (verbose mode already
		# narrates each removal above via Write-LogDebug).
		if (-not (Test-LogVerbose) -and $removedDesktops.Count -gt 0) {
			Write-LogSuccess "Removed $($removedDesktops.Count) virtual desktop(s)!"
			Write-LogList -Items $removedDesktops
		}
	}
	catch {
		$errorMessage = if ($_.Exception) { $_.Exception.Message } else { [string]$_ }
		if ($errorMessage -match $rpcUnavailablePattern) {
			Write-LogDebug "Could not remove virtual desktops => [VirtualDesktop RPC endpoint stayed unavailable after live preflight and retry recovery: $errorMessage]" -Style Error
		}
		else {
			Write-LogDebug "Could not remove virtual desktops => [$errorMessage]" -Style Error
		}
		return $false
	}
}
