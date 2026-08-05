function Set-ShortcutAumid {
	<#
	.SYNOPSIS
		Creates or updates a .lnk shortcut and stamps an explicit AppUserModelID on it.

	.DESCRIPTION
		The taskbar groups a pinned icon with a running window only when the two share an
		application identity (AppUserModelID). An app that registers its own identity at
		startup via SetCurrentProcessExplicitAppUserModelID - Eclipse/SWT apps such as
		DBeaver, and some Java and Electron apps - advertises an AUMID that can never match
		a pin created from its exe path, so launching it opens a second, separate taskbar
		icon next to its own pin. Stamping the pin's shortcut with the app's runtime AUMID
		(the System.AppUserModel.ID property, the same one the manual "Pin to taskbar" flow
		records) gives both sides one identity, and the running window docks onto the pin.

		With -TargetPath, the shortcut is created first when missing (parent folder
		included) and its target and working directory are set; without it, LinkPath must
		already exist. The property is written through the shell's IPropertyStore on the
		shortcut file and persisted into the .lnk itself, so it travels with any copy
		Explorer makes when applying a taskbar layout. Throws on any COM failure - callers
		decide whether that is fatal.

	.PARAMETER LinkPath
		Full path of the .lnk file to stamp (and create, when -TargetPath is given).

	.PARAMETER TargetPath
		Executable the shortcut should launch. When given, the shortcut is created if
		missing and its target and working directory are (re)set before stamping. When
		omitted, LinkPath must already exist.

	.PARAMETER Aumid
		The explicit AppUserModelID to stamp - the identity the running app registers.
		Discover it via Get-StartApps, or from the app's jump-list file name (see
		docs/configuration/configuration-reference.md, Taskbar Configuration).

	.EXAMPLE
		Set-ShortcutAumid -LinkPath "C:\ProgramData\provisioning\TaskbarPins\DBeaver.lnk" -TargetPath "$env:LOCALAPPDATA\DBeaver\dbeaver.exe" -Aumid "DBeaver"
		Creates the shortcut and stamps DBeaver's runtime identity on it.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$LinkPath,

		[Parameter(Mandatory = $false)]
		[string]$TargetPath,

		[Parameter(Mandatory = $true)]
		[string]$Aumid
	)

	if (-not ([System.Management.Automation.PSTypeName]'ShortcutAumidHelper').Type) {
		Add-Type @"
			using System;
			using System.Runtime.InteropServices;

			[StructLayout(LayoutKind.Sequential, Pack = 4)]
			public struct ShortcutPropertyKey {
				public Guid fmtid;
				public uint pid;
				public ShortcutPropertyKey(Guid f, uint p) { fmtid = f; pid = p; }
			}

			// Header layout of PROPVARIANT: 8 bytes (vt + reserved) before the data union,
			// identical on x86 and x64, so the fixed offset is safe for both.
			[StructLayout(LayoutKind.Explicit)]
			public struct ShortcutPropVariant {
				[FieldOffset(0)] public ushort vt;
				[FieldOffset(8)] public IntPtr pointerValue;
			}

			[ComImport, Guid("886d8eeb-8cf2-4446-8d02-cdba1dbdcf99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
			public interface IShortcutPropertyStore {
				int GetCount(out uint count);
				int GetAt(uint index, out ShortcutPropertyKey key);
				int GetValue(ref ShortcutPropertyKey key, out ShortcutPropVariant value);
				int SetValue(ref ShortcutPropertyKey key, ref ShortcutPropVariant value);
				int Commit();
			}

			[ComImport, Guid("0000010b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
			public interface IShortcutPersistFile {
				int GetClassID(out Guid classId);
				int IsDirty();
				int Load([MarshalAs(UnmanagedType.LPWStr)] string fileName, uint mode);
				int Save([MarshalAs(UnmanagedType.LPWStr)] string fileName, bool remember);
				int SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string fileName);
				int GetCurFile(out IntPtr fileName);
			}

			[ComImport, Guid("00021401-0000-0000-C000-000000000046")]
			public class ShortcutShellLink { }

			public static class ShortcutAumidHelper {
				static readonly ShortcutPropertyKey PKEY_AppUserModel_ID =
					new ShortcutPropertyKey(new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 5);
				const ushort VT_LPWSTR = 31;
				const uint STGM_READWRITE = 0x00000002;

				public static void Set(string linkPath, string aumid) {
					var link = new ShortcutShellLink();
					try {
						var persistFile = (IShortcutPersistFile)link;
						Check(persistFile.Load(linkPath, STGM_READWRITE));
						var store = (IShortcutPropertyStore)link;
						var key = PKEY_AppUserModel_ID;
						var value = new ShortcutPropVariant { vt = VT_LPWSTR, pointerValue = Marshal.StringToCoTaskMemUni(aumid) };
						try {
							Check(store.SetValue(ref key, ref value));
							Check(store.Commit());
						}
						finally { Marshal.FreeCoTaskMem(value.pointerValue); }
						Check(persistFile.Save(linkPath, true));
					}
					finally { Marshal.ReleaseComObject(link); }
				}

				static void Check(int hr) {
					if (hr != 0) Marshal.ThrowExceptionForHR(hr);
				}
			}
"@
	}

	if ($TargetPath) {
		$linkDir = Split-Path -Parent $LinkPath
		if ($linkDir -and -not (Test-Path $linkDir)) {
			New-Item -Path $linkDir -ItemType Directory -Force | Out-Null
		}

		$shell = New-Object -ComObject WScript.Shell
		$shortcut = $shell.CreateShortcut($LinkPath)
		$shortcut.TargetPath = $TargetPath
		$shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
		$shortcut.Save()
	}
	elseif (-not (Test-Path $LinkPath)) {
		throw "Shortcut [$LinkPath] does not exist and no -TargetPath was given to create it!"
	}

	[ShortcutAumidHelper]::Set($LinkPath, $Aumid)
}
