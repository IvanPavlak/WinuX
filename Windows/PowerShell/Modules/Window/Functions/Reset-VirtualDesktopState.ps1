function Reset-VirtualDesktopState {
	<#
	.SYNOPSIS
		Restores a working VirtualDesktop session in place - fresh COM proxies and a fresh module load.

	.DESCRIPTION
		Recovers the current session after the VirtualDesktop COM/RPC state has gone
		stale - the "RPC server is unavailable (0x800706BA)" family of failures that an
		Explorer restart leaves behind in long-running shells.

		The recovery has two layers:

		1. Reset-VirtualDesktopComProxy reconnects the compiled DesktopManager type's
		   cached static COM proxies to the current shell via reflection. This is the
		   step that actually repairs a stale session: the module creates its COM
		   objects once per process in a static constructor, so re-importing the
		   module alone can never refresh them.
		2. The VirtualDesktop module is removed, the module-scoped lazy-load cache
		   ($script:VirtualDesktopState) is cleared, and the module is re-imported via
		   Import-VirtualDesktopModule so the cmdlet layer is fresh too.

		When Test-VirtualDesktopComHealth is available, a live in-process roundtrip
		verifies the session actually works before success is reported, so callers can
		trust $true to mean "VirtualDesktop calls will work now".

	.OUTPUTS
		Boolean. $true if the VirtualDesktop session is ready after the reset, otherwise $false.

	.EXAMPLE
		if (Reset-VirtualDesktopState) { Switch-Desktop -Desktop 0 }
		# Reconnects COM proxies, reloads the module, and only switches when verified ready.
	#>
	[CmdletBinding()]
	param()

	# Layer 1: reconnect the compiled type's cached COM proxies - the state that is
	# actually stale after an Explorer restart.
	$comProxiesReady = $true
	if (Get-Command Reset-VirtualDesktopComProxy -ErrorAction SilentlyContinue) {
		$comProxiesReady = [bool](Reset-VirtualDesktopComProxy)
	}

	# Layer 2: reload the cmdlet layer.
	try {
		Remove-Module -Name VirtualDesktop -Force -ErrorAction SilentlyContinue
	}
	catch {
		# Ignore removal failures - the module may not currently be loaded.
	}

	# Invalidate the lazy-load cache so Import-VirtualDesktopModule re-establishes a fresh session.
	$script:VirtualDesktopState.Checked = $false
	$script:VirtualDesktopState.Available = $false
	$script:VirtualDesktopState.Loaded = $false

	if (-not (Import-VirtualDesktopModule -Silent)) {
		return $false
	}

	if (-not $comProxiesReady) {
		return $false
	}

	# Verify with a live roundtrip - a reset that leaves the session broken must not
	# report success. The probe runs in-process (it shares this session's COM state)
	# under a timeout, so a hung endpoint cannot wedge the recovery path either.
	if (Get-Command Test-VirtualDesktopComHealth -ErrorAction SilentlyContinue) {
		$probe = Test-VirtualDesktopComHealth -TimeoutMs 2500
		if (-not $probe.Healthy) {
			Write-LogDebug "  VirtualDesktop session still unhealthy after reset => [$($probe.Error)]" -Style Warning
			return $false
		}
	}

	return $true
}
