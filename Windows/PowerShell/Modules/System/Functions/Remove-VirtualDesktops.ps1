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

		Before cleanup, runs Test-RpcServerHealth -Probe so the preflight verifies
		the live VirtualDesktop RPC endpoint instead of only checking that Windows
		RPC services are Running. If preflight recovery unloads the VirtualDesktop
		module, cmdlets are rehydrated before cleanup continues. VirtualDesktop
		operations are retried with exponential backoff; if an operation reports
		0x800706BA / 0x800706BE, the current session's VirtualDesktop module state
		is reset before the next attempt to recover stale COM proxies without
		requiring a fresh shell.

	.PARAMETER EmptyOnly
		When specified, only removes virtual desktops that have no visible windows on them.
		Iterates from the rightmost desktop toward desktop 0. At least one desktop is always kept.

	.EXAMPLE
		Remove-VirtualDesktops
		# Removes all desktops except desktop 0

	.EXAMPLE
		Remove-VirtualDesktops -EmptyOnly
		# Removes only desktops that have no windows on them
	#>
	[CmdletBinding()]
	param (
		[Parameter()]
		[switch]$EmptyOnly
	)

	Write-LogTitle "Removing Virtual Desktops$(if ($EmptyOnly) { ' (empty only)' })"

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
	if (-not (Get-Command Get-DesktopList -ErrorAction SilentlyContinue)) {
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
	$rpcUnavailablePattern = '0x800706BA|0x800706BE|0x80010108|RPC server is unavailable|The remote procedure call failed'
	$recoverVirtualDesktopRpc = {
		param($ErrorRecord, [int]$Attempt)

		# Test-RpcUnavailableError walks the InnerException chain and HRESULTs, so
		# wrapped RPC failures (e.g. a TypeInitializationException around the COM
		# error) still trigger recovery; the message match is the fallback.
		$isRpcFailure = if (Get-Command Test-RpcUnavailableError -ErrorAction SilentlyContinue) {
			Test-RpcUnavailableError $ErrorRecord
		}
		else {
			$errorMessage = if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
			$errorMessage -match $rpcUnavailablePattern
		}
		if (-not $isRpcFailure) {
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
		$desktops = & $invokeDesktopOperation { Get-DesktopList }

		if ($EmptyOnly) {
			if ($desktops.Count -le 1) {
				Write-LogDebug "Only one desktop exists - nothing to clean up" -Style Success
				return
			}

			# Build a set of desktop indices that have at least one visible window
			$occupiedDesktops = New-Object 'System.Collections.Generic.HashSet[int]'

			# Get all visible windows and map them to their desktops
			# Prefer Get-WindowHandle (Window module, EnumWindows-based) - captures ALL visible windows
			# including multiple windows of the same process on different desktops (e.g., two VSCode windows)
			# Falls back to Get-Process MainWindowHandle which only returns one handle per process
			$windowHandles = @()
			if (Get-Command Get-WindowHandle -ErrorAction SilentlyContinue) {
				$allWindows = Get-WindowHandle -ErrorAction SilentlyContinue
				if ($allWindows) {
					$windowHandles = @($allWindows | Select-Object -ExpandProperty Handle)
				}
			}
			else {
				Write-LogDebug " Get-WindowHandle not available - falling back to Get-Process (may miss secondary windows)" -Style Warning
				$windowHandles = @(Get-Process -ErrorAction SilentlyContinue |
						Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } |
						Select-Object -ExpandProperty MainWindowHandle)
			}

			$rpcCircuitBroken = $false
			foreach ($hwnd in $windowHandles) {
				try {
					$desktop = & $invokeDesktopOperation { Get-DesktopFromWindow -Hwnd $hwnd }
					if ($desktop) {
						$index = & $invokeDesktopOperation { Get-DesktopIndex -Desktop $desktop }
						if ($index -ge 0) {
							[void]$occupiedDesktops.Add($index)
						}
					}
				}
				catch {
					# Window may have been closed or become invalid between enumeration and
					# check - that is fine to skip. But an RPC-unavailable failure that
					# survived the FULL retry ladder (with per-retry module resets) means
					# every remaining per-window call will fail the same multi-second way:
					# trip a circuit breaker instead of grinding through the whole list.
					$isRpcDead = if (Get-Command Test-RpcUnavailableError -ErrorAction SilentlyContinue) {
						Test-RpcUnavailableError $_
					}
					else {
						$_.Exception -and $_.Exception.Message -match $rpcUnavailablePattern
					}

					if ($isRpcDead) {
						$rpcCircuitBroken = $true
						break
					}
				}
			}

			if ($rpcCircuitBroken) {
				# With occupancy unknowable, removing "empty" desktops could remove occupied
				# ones - abort the cleanup entirely and report failure once.
				Write-LogDebug "Aborting empty-desktop cleanup - VirtualDesktop RPC stayed unavailable after retry recovery (window occupancy cannot be trusted)" -Style Error
				return $false
			}

			Write-LogDebug " Found $($windowHandles.Count) window(s), $($occupiedDesktops.Count) occupied desktop(s) out of $($desktops.Count)" -Style Success

			$removedCount = 0

			# Remove empty desktops from right to left (right-to-left preserves indices for remaining desktops)
			for ($i = $desktops.Count - 1; $i -ge 1; $i--) {
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
			$remainingDesktopList = & $invokeDesktopOperation { Get-DesktopList }
			$remainingDesktops = ($remainingDesktopList | Measure-Object).Count
			if ($remainingDesktops -gt 1 -and -not $occupiedDesktops.Contains(0)) {
				Write-LogDebug " Removing empty desktop [0]!" -Style Error -NoLeadingNewline
				& $invokeDesktopOperation { Remove-Desktop -Desktop 0 -Verbose:$false -ErrorAction Stop } | Out-Null
				$removedCount++
				$removedDesktops += "Desktop [0]"
			}
			else {
				if ($remainingDesktops -le 1) {
					Write-LogDebug " Desktop [0] is the last desktop - keeping" -Style Warning
				}
				else {
					Write-LogDebug " Desktop [0] has windows!" -Style Warning
				}
			}

			Write-LogDebug "Removed $removedCount empty virtual desktop(s)" -Style Success
		}
		else {
			# Original behavior: remove all except desktop 0
			Write-LogDebug " Found $($desktops.Count) desktop(s) to clean up; keeping desktop [0] and removing the rest" -Style Success

			while ($desktops.Count -gt 1) {
				$desktopToRemove = $desktops.Count - 1

				Write-LogDebug " Removing desktop [$desktopToRemove]!" -Style Error -NoLeadingNewline

				& $invokeDesktopOperation { Remove-Desktop -Desktop $desktopToRemove -Verbose:$false -ErrorAction Stop } | Out-Null
				$removedDesktops += "Desktop [$desktopToRemove]"
				$desktops = & $invokeDesktopOperation { Get-DesktopList }
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
