function Reset-VirtualDesktopComProxy {
	<#
	.SYNOPSIS
		Reconnects the VirtualDesktop module's cached COM proxies to the current shell.

	.DESCRIPTION
		The VirtualDesktop module compiles a C# DesktopManager class whose static
		constructor creates COM proxies to the shell's virtual desktop manager (hosted
		by explorer.exe) and caches them in static fields - once per process. When
		Explorer restarts (taskbar configuration, icon-cache rebuild, theme changes),
		those proxies disconnect permanently and every VirtualDesktop call fails with
		"The RPC server is unavailable" (0x800706BA). Re-importing the module cannot
		recover this: Add-Type caches the compiled assembly, so the static constructor
		never runs again for the lifetime of the process.

		This function replays the static constructor via reflection - it creates a
		fresh ImmersiveShell service provider and overwrites the cached static COM
		fields (VirtualDesktopManagerInternal, VirtualDesktopManager,
		ApplicationViewCollection, VirtualDesktopPinnedApps, and the Windows 10-only
		VirtualDesktopManagerInternal2) with newly connected proxies. The session
		recovers in place; no new shell is required.

		Returns $true when the compiled types are not loaded yet (the first real call
		will create fresh proxies on its own) or when every field was rebuilt. Returns
		$false when the rebuild failed - typically because Explorer is still starting
		up and has not re-registered its COM classes; safe to retry after a delay.

	.EXAMPLE
		if (Test-RpcUnavailableError $_) { [void](Reset-VirtualDesktopComProxy) }
		# Reconnects the session's COM proxies after an RPC failure before retrying.

	.OUTPUTS
		Boolean. $true if the session's COM proxies are expected to be fresh, $false when the rebuild failed.
	#>
	[CmdletBinding()]
	[OutputType([bool])]
	param ()

	# The public Desktop class anchors type resolution; the internal plumbing types are
	# resolved through its assembly. No anchor means the module has not compiled its
	# types in this process yet, so there is no stale state to reconnect.
	$desktopType = ([System.Management.Automation.PSTypeName]'VirtualDesktop.Desktop').Type
	$managerType = if ($desktopType) { $desktopType.Assembly.GetType('VirtualDesktop.DesktopManager', $false) } else { $null }

	if (-not $managerType) {
		Write-LogDebug "  VirtualDesktop COM types not loaded yet - nothing to reconnect" -Style Step
		return $true
	}

	$bindingFlags = [System.Reflection.BindingFlags]'NonPublic,Public,Static'

	try {
		$assembly = $managerType.Assembly
		$guidsType = $assembly.GetType('VirtualDesktop.Guids')
		$queryService = $assembly.GetType('VirtualDesktop.IServiceProvider10').GetMethod('QueryService')

		$shellClsid = [Guid]$guidsType.GetField('CLSID_ImmersiveShell', $bindingFlags).GetValue($null)
		$shellProvider = [Activator]::CreateInstance([Type]::GetTypeFromCLSID($shellClsid))

		# Mirrors the DesktopManager static constructor: QueryService for each
		# shell-hosted interface, plus a plain CoCreateInstance for
		# IVirtualDesktopManager. Interface GUIDs come from the fields' own types so
		# this tracks whichever interface set the installed module version compiled.
		$managerInternalClsid = [Guid]$guidsType.GetField('CLSID_VirtualDesktopManagerInternal', $bindingFlags).GetValue($null)
		$managerInternalField = $managerType.GetField('VirtualDesktopManagerInternal', $bindingFlags)
		$managerInternalField.SetValue($null, $queryService.Invoke($shellProvider, @($managerInternalClsid, $managerInternalField.FieldType.GUID)))

		# Only compiled on Windows 10 builds; the original constructor tolerates this
		# one failing, so a null assignment mirrors its behavior.
		$managerInternal2Field = $managerType.GetField('VirtualDesktopManagerInternal2', $bindingFlags)
		if ($managerInternal2Field) {
			try {
				$managerInternal2Field.SetValue($null, $queryService.Invoke($shellProvider, @($managerInternalClsid, $managerInternal2Field.FieldType.GUID)))
			}
			catch {
				$managerInternal2Field.SetValue($null, $null)
			}
		}

		$viewCollectionField = $managerType.GetField('ApplicationViewCollection', $bindingFlags)
		$viewCollectionField.SetValue($null, $queryService.Invoke($shellProvider, @($viewCollectionField.FieldType.GUID, $viewCollectionField.FieldType.GUID)))

		$pinnedAppsClsid = [Guid]$guidsType.GetField('CLSID_VirtualDesktopPinnedApps', $bindingFlags).GetValue($null)
		$pinnedAppsField = $managerType.GetField('VirtualDesktopPinnedApps', $bindingFlags)
		$pinnedAppsField.SetValue($null, $queryService.Invoke($shellProvider, @($pinnedAppsClsid, $pinnedAppsField.FieldType.GUID)))

		$managerClsid = [Guid]$guidsType.GetField('CLSID_VirtualDesktopManager', $bindingFlags).GetValue($null)
		$managerType.GetField('VirtualDesktopManager', $bindingFlags).SetValue($null, [Activator]::CreateInstance([Type]::GetTypeFromCLSID($managerClsid)))

		Write-LogDebug "  Reconnected VirtualDesktop COM proxies to the current shell" -Style Success
		return $true
	}
	catch {
		Write-LogDebug "  Could not reconnect VirtualDesktop COM proxies => [$($_.Exception.Message)]" -Style Warning
		return $false
	}
}
