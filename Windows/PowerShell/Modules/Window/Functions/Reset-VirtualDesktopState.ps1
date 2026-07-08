function Reset-VirtualDesktopState {
	<#
	.SYNOPSIS
		Forces a fresh reload of the VirtualDesktop module to recover stale COM state.

	.DESCRIPTION
		Removes the VirtualDesktop module, clears the module-scoped lazy-load cache
		($script:VirtualDesktopState), and re-imports it via Import-VirtualDesktopModule.
		This reproduces the "fresh shell" recovery for cases where the VirtualDesktop
		COM/RPC session has gone stale mid-session - a known cause of Switch-Desktop
		silently failing in long-running shells while succeeding from a new shell.
		Returns whether the module is loaded and ready after the reset.

	.OUTPUTS
		Boolean. $true if the VirtualDesktop module is ready after the reset, otherwise $false.

	.EXAMPLE
		if (Reset-VirtualDesktopState) { Switch-Desktop -Desktop 0 }
		# Reloads the module and only switches when it is ready again.
	#>
	[CmdletBinding()]
	param()

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

	return [bool](Import-VirtualDesktopModule -Silent)
}
