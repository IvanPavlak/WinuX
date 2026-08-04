function Initialize-Win32BrowserHelperType {
	<#
	.SYNOPSIS
		Ensures the Win32 browser window helper type is available.

	.DESCRIPTION
		Adds the `Win32BrowserHelper` C# type used by browser window discovery and
		graceful window closure. The type is added only once per session.

		The text APIs marshal as Unicode: without an explicit CharSet the default
		is ANSI, which mangles non-ANSI title characters to `?` - including the
		zero-width space (U+200B) Edge embeds in "Microsoft Edge" window titles.

	.EXAMPLE
		Initialize-Win32BrowserHelperType
		Loads the Win32 browser helper type if it has not already been added.
	#>
	[CmdletBinding()]
	param()

	if (-not ([System.Management.Automation.PSTypeName]'Win32BrowserHelper').Type) {
		Add-Type @"
			using System;
			using System.Runtime.InteropServices;
			using System.Text;
			public class Win32BrowserHelper {
				[DllImport("user32.dll")]
				public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

				[DllImport("user32.dll")]
				public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

				[DllImport("user32.dll")]
				public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

				[DllImport("user32.dll", CharSet = CharSet.Unicode)]
				public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

				[DllImport("user32.dll", CharSet = CharSet.Unicode)]
				public static extern int GetWindowTextLength(IntPtr hWnd);

				[DllImport("user32.dll")]
				public static extern bool IsWindowVisible(IntPtr hWnd);

				public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
			}
"@
	}
}
