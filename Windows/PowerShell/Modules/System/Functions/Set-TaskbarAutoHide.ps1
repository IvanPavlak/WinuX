function Set-TaskbarAutoHide {
	<#
	.SYNOPSIS
		Enables or disables taskbar auto-hide for the current user.

	.DESCRIPTION
		Sets the taskbar auto-hide state via SHAppBarMessage (ABM_SETSTATE), the same
		mechanism the Taskbar settings page uses. The change applies to the live Explorer
		session immediately and Explorer persists it (StuckRects3) on exit, so it survives
		reboots.

		With `-Auto`, reads the `TaskbarAutoHide` boolean from Configuration.psd1 /
		Configuration.local.psd1. When the key is absent or `$false`, the function changes
		NOTHING - the machine keeps its current taskbar behavior. This keeps the upstream
		default vanilla; a fork opts in via its local configuration.

		Why this exists: FancyZones lays zones over the monitor WORK AREA (screen minus
		taskbar). The Window module computes zone geometry from the same work area, so
		auto-hide is purely cosmetic for correctness - but machines that always ran with
		auto-hide get identical UX on fresh installs when this is enabled in config.

		Idempotent - checks the current state and returns early when nothing needs to change.

	.PARAMETER Auto
		Resolve the desired state from the `TaskbarAutoHide` configuration key. Absent or
		`$false` means "leave the taskbar alone".

	.PARAMETER Enabled
		Explicitly enable ($true) or disable ($false) taskbar auto-hide.

	.EXAMPLE
		Set-TaskbarAutoHide -Auto
		Applies the configured preference (no-op unless TaskbarAutoHide = $true in config).

	.EXAMPLE
		Set-TaskbarAutoHide -Enabled $true
		Enables taskbar auto-hide immediately.
	#>
	[CmdletBinding(DefaultParameterSetName = 'Explicit')]
	param(
		[Parameter(ParameterSetName = 'Auto', Mandatory = $true)]
		[switch]$Auto,

		[Parameter(ParameterSetName = 'Explicit', Mandatory = $true)]
		[bool]$Enabled
	)

	Write-LogTitle "Configuring Taskbar Auto-Hide"

	if ($Auto) {
		$configured = $global:Configuration.TaskbarAutoHide
		if (-not $configured) {
			Write-LogWarning "TaskbarAutoHide is not enabled in configuration - leaving the taskbar as-is!"
			return
		}
		$Enabled = $true
	}

	if (-not ([System.Management.Automation.PSTypeName]'TaskbarModule.AppBar').Type) {
		Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace TaskbarModule {
	public static class AppBar {
		[StructLayout(LayoutKind.Sequential)]
		public struct RECT { public int left, top, right, bottom; }

		[StructLayout(LayoutKind.Sequential)]
		public struct APPBARDATA {
			public uint cbSize;
			public IntPtr hWnd;
			public uint uCallbackMessage;
			public uint uEdge;
			public RECT rc;
			public IntPtr lParam;
		}

		[DllImport("shell32.dll")]
		public static extern IntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);

		public const uint ABM_GETSTATE = 0x00000004;
		public const uint ABM_SETSTATE = 0x0000000A;
		public const int ABS_AUTOHIDE = 0x1;
		public const int ABS_ALWAYSONTOP = 0x2;

		public static int GetState() {
			APPBARDATA data = new APPBARDATA();
			data.cbSize = (uint)Marshal.SizeOf(typeof(APPBARDATA));
			return (int)SHAppBarMessage(ABM_GETSTATE, ref data);
		}

		public static void SetState(int state) {
			APPBARDATA data = new APPBARDATA();
			data.cbSize = (uint)Marshal.SizeOf(typeof(APPBARDATA));
			data.lParam = (IntPtr)state;
			SHAppBarMessage(ABM_SETSTATE, ref data);
		}
	}
}
"@
	}

	try {
		$currentState = [TaskbarModule.AppBar]::GetState()
		$autoHideActive = ($currentState -band [TaskbarModule.AppBar]::ABS_AUTOHIDE) -ne 0

		if ($autoHideActive -eq $Enabled) {
			Write-LogSuccess "Taskbar auto-hide already $(if ($Enabled) { 'enabled' } else { 'disabled' })!"
			return
		}

		$targetState = if ($Enabled) { [TaskbarModule.AppBar]::ABS_AUTOHIDE } else { [TaskbarModule.AppBar]::ABS_ALWAYSONTOP }
		[TaskbarModule.AppBar]::SetState($targetState)

		Start-Sleep -Milliseconds 500

		$verifyState = [TaskbarModule.AppBar]::GetState()
		$verifyActive = ($verifyState -band [TaskbarModule.AppBar]::ABS_AUTOHIDE) -ne 0

		if ($verifyActive -eq $Enabled) {
			Write-LogSuccess "Taskbar auto-hide $(if ($Enabled) { 'enabled' } else { 'disabled' }) successfully!"
		}
		else {
			Write-LogWarning "Taskbar auto-hide state did not change (Explorer may not be running yet) - it will be retried on the next Bootstrap run."
		}
	}
	catch {
		Write-LogWarning "Could not set taskbar auto-hide => $($_.Exception.Message)"
	}
}
