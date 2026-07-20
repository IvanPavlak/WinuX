using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WindowModule
{
	#region Structures

	[StructLayout(LayoutKind.Sequential)]
	public struct RECT
	{
		public int Left;
		public int Top;
		public int Right;
		public int Bottom;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct POINT
	{
		public int X;
		public int Y;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct WINDOWPLACEMENT
	{
		public int length;
		public int flags;
		public int showCmd;
		public POINT ptMinPosition;
		public POINT ptMaxPosition;
		public RECT rcNormalPosition;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct INPUT
	{
		public uint type;
		public InputUnion u;
	}

	[StructLayout(LayoutKind.Explicit)]
	public struct InputUnion
	{
		[FieldOffset(0)] public MOUSEINPUT mi;
		[FieldOffset(0)] public KEYBDINPUT ki;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct MOUSEINPUT
	{
		public int dx;
		public int dy;
		public uint mouseData;
		public uint dwFlags;
		public uint time;
		public IntPtr dwExtraInfo;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct KEYBDINPUT
	{
		public ushort wVk;
		public ushort wScan;
		public uint dwFlags;
		public uint time;
		public IntPtr dwExtraInfo;
	}

	public class WindowInfo
	{
		public IntPtr Handle { get; set; }
		public string Title { get; set; }
		public string ProcessName { get; set; }
		public uint ProcessId { get; set; }
		public int Left { get; set; }
		public int Top { get; set; }
		public int Right { get; set; }
		public int Bottom { get; set; }
		public int Width { get { return Right - Left; } }
		public int Height { get { return Bottom - Top; } }
	}

	[StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
	public struct DISPLAY_DEVICE
	{
		public int cb;
		[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
		public string DeviceName;
		[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
		public string DeviceString;
		public int StateFlags;
		[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
		public string DeviceID;
		[MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
		public string DeviceKey;
	}

	/// <summary>
	/// Maps a WinForms display name (e.g., "\\.\DISPLAY2") to its EDID hardware identifier
	/// (e.g., "LEN8ABC") and PnP monitor instance, as used by FancyZones applied-layouts.json.
	/// </summary>
	public class MonitorDeviceInfo
	{
		public string DisplayName { get; set; }
		public string EdidCode { get; set; }
		public string MonitorInstance { get; set; }
	}

	#endregion

	#region Native Methods

	public static class Native
	{
		// Delegate for EnumWindows callback
		public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

		// Process name cache for efficient lookups (avoids repeated Process.GetProcessById calls)
		private static Dictionary<uint, string> _processNameCache = new Dictionary<uint, string>();
		private static readonly object _cacheLock = new object();
		private static DateTime _cacheTimestamp = DateTime.MinValue;
		private const int CACHE_MAX_AGE_MS = 100;
		private static readonly HashSet<string> _browserProcessNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
		{
			"chrome",
			"msedge",
			"firefox",
			"brave",
			"opera",
			"opera_gx",
			"vivaldi",
			"arc",
			"zen",
			"waterfox",
			"librewolf",
			"iexplore"
		};

		#region User32 Imports

		[DllImport("user32.dll", CharSet = CharSet.Unicode)]
		public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);

		[DllImport("user32.dll")]
		public static extern bool EnumWindows(EnumWindowsProc enumProc, IntPtr lParam);

		[DllImport("user32.dll")]
		public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

		[DllImport("user32.dll")]
		public static extern int GetWindowTextLength(IntPtr hWnd);

		[DllImport("user32.dll")]
		public static extern bool IsWindowVisible(IntPtr hWnd);

		[DllImport("user32.dll")]
		public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

		[DllImport("user32.dll")]
		public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr lpdwProcessId);

		[DllImport("user32.dll")]
		public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

		[DllImport("user32.dll", SetLastError = true)]
		public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

		[DllImport("user32.dll")]
		public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

		[DllImport("user32.dll")]
		public static extern bool IsZoomed(IntPtr hWnd);

		[DllImport("user32.dll")]
		public static extern bool GetWindowPlacement(IntPtr hWnd, ref WINDOWPLACEMENT lpwndpl);

		[DllImport("user32.dll")]
		public static extern bool SetForegroundWindow(IntPtr hWnd);

		[DllImport("user32.dll")]
		public static extern IntPtr GetForegroundWindow();

		[DllImport("user32.dll")]
		public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

		[DllImport("user32.dll")]
		public static extern bool AllowSetForegroundWindow(int dwProcessId);

		[DllImport("user32.dll")]
		public static extern bool BringWindowToTop(IntPtr hWnd);

		[DllImport("user32.dll")]
		public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

		[DllImport("user32.dll")]
		public static extern bool SetCursorPos(int X, int Y);

		[DllImport("user32.dll")]
		public static extern IntPtr GetDesktopWindow();

		[DllImport("user32.dll")]
		public static extern int GetWindowLong(IntPtr hWnd, int nIndex);

		[DllImport("user32.dll", SetLastError = true)]
		public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

		[DllImport("user32.dll")]
		public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, int dwExtraInfo);

		[DllImport("user32.dll")]
		public static extern short GetAsyncKeyState(int vKey);

		[DllImport("user32.dll", SetLastError = true)]
		public static extern bool SetProcessDpiAwarenessContext(IntPtr value);

		#endregion

		#region Kernel32 Imports

		[DllImport("kernel32.dll")]
		public static extern uint GetCurrentThreadId();

		#endregion

		#region Constants

		// Virtual Key Codes
		public const byte VK_LWIN = 0x5B;
		public const byte VK_RWIN = 0x5C;
		public const byte VK_CONTROL = 0x11;
		public const byte VK_MENU = 0x12;  // Alt key
		public const byte VK_SHIFT = 0x10;
		public const byte VK_LBUTTON = 0x01;
		public const byte VK_LSHIFT = 0xA0;
		public const byte VK_RSHIFT = 0xA1;
		public const byte VK_LCONTROL = 0xA2;
		public const byte VK_RCONTROL = 0xA3;
		public const byte VK_LMENU = 0xA4;
		public const byte VK_RMENU = 0xA5;
		public const byte VK_UP = 0x26;
		public const byte VK_DOWN = 0x28;
		public const byte VK_LEFT = 0x25;
		public const byte VK_RIGHT = 0x27;

		// Key Event Flags
		public const uint KEYEVENTF_KEYUP = 0x0002;
		public const uint KEYEVENTF_EXTENDEDKEY = 0x0001;

		// Input Type
		public const uint INPUT_KEYBOARD = 1;

		// Mouse event flags
		public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
		public const uint MOUSEEVENTF_LEFTUP = 0x0004;
		public const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
		public const uint MOUSEEVENTF_MOVE = 0x0001;

		// Show Window Commands
		public const int SW_HIDE = 0;
		public const int SW_RESTORE = 9;
		public const int SW_NORMAL = 1;
		public const int SW_SHOWNORMAL = 1;
		public const int SW_SHOW = 5;
		public const int SW_MINIMIZE = 6;

		// SetWindowPos Flags
		public const uint SWP_NOSIZE = 0x0001;
		public const uint SWP_NOMOVE = 0x0002;
		public const uint SWP_NOZORDER = 0x0004;
		public const uint SWP_SHOWWINDOW = 0x0040;
		public const uint SWP_NOACTIVATE = 0x0010;
		public const uint SWP_FRAMECHANGED = 0x0020;

		// SetWindowPos Z-Order constants
		public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
		public static readonly IntPtr HWND_NOTOPMOST = new IntPtr(-2);

		// Window Styles
		public const int GWL_EXSTYLE = -20;
		public const int WS_EX_TOOLWINDOW = 0x00000080;
		public const int WS_EX_APPWINDOW = 0x00040000;

		// AllowSetForegroundWindow
		public const int ASFW_ANY = -1;

		#endregion

		#region Cache Management

		/// <summary>
		/// Clears the process name cache. Call when you need fresh process data.
		/// </summary>
		public static void ClearProcessCache()
		{
			lock (_cacheLock)
			{
				_processNameCache.Clear();
				_cacheTimestamp = DateTime.MinValue;
			}
		}

		/// <summary>
		/// Gets a process name with caching to avoid repeated Process.GetProcessById calls.
		/// </summary>
		private static string GetCachedProcessName(uint processId)
		{
			lock (_cacheLock)
			{
				// Check if cache is stale
				if ((DateTime.Now - _cacheTimestamp).TotalMilliseconds > CACHE_MAX_AGE_MS)
				{
					_processNameCache.Clear();
					_cacheTimestamp = DateTime.Now;
				}

				if (_processNameCache.TryGetValue(processId, out string cachedName))
				{
					return cachedName;
				}
			}

			// Not in cache, look up
			string processName = "";
			try
			{
				Process proc = Process.GetProcessById((int)processId);
				processName = proc.ProcessName;
			}
			catch
			{
				// Process may have exited
			}

			lock (_cacheLock)
			{
				_processNameCache[processId] = processName;
			}

			return processName;
		}

		#endregion

		#region Helper Methods

		/// <summary>
		/// Opts the current process into Per-Monitor-V2 DPI awareness so every coordinate
		/// this module reads or writes (GetWindowRect, SetWindowPos, SetCursorPos, screen
		/// bounds) is in physical pixels - the space FancyZones works in. On any display
		/// scale above 100% an unaware process sees virtualized coordinates and snap
		/// verification drifts by the scale factor. Safe to call unconditionally: returns
		/// false (changing nothing) when awareness was already set by a manifest or an
		/// earlier call, and on Windows versions without the API.
		/// </summary>
		public static bool EnablePerMonitorDpiAwareness()
		{
			// DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
			IntPtr perMonitorAwareV2 = new IntPtr(-4);
			try
			{
				return SetProcessDpiAwarenessContext(perMonitorAwareV2);
			}
			catch (Exception)
			{
				// EntryPointNotFoundException on pre-1703 Windows - awareness stays as-is.
				return false;
			}
		}

		/// <summary>
		/// Gets all visible windows with titles, filtering out tool windows.
		/// Now includes process names using cached lookups for performance.
		/// </summary>
		public static List<WindowInfo> GetAllWindows()
		{
			List<WindowInfo> windows = new List<WindowInfo>();
			EnumWindows(delegate (IntPtr hWnd, IntPtr lParam)
			{
				if (IsWindowVisible(hWnd))
				{
					int exStyle = GetWindowLong(hWnd, GWL_EXSTYLE);

					// Skip tool windows unless they have APPWINDOW style
					bool isToolWindow = (exStyle & WS_EX_TOOLWINDOW) != 0;
					bool isAppWindow = (exStyle & WS_EX_APPWINDOW) != 0;
					if (isToolWindow && !isAppWindow) return true;

					int length = GetWindowTextLength(hWnd);
					if (length > 0)
					{
						StringBuilder sb = new StringBuilder(length + 1);
						GetWindowText(hWnd, sb, sb.Capacity);
						uint processId;
						GetWindowThreadProcessId(hWnd, out processId);

						RECT rect;
						GetWindowRect(hWnd, out rect);

						// Get process name using cached lookup
						string processName = GetCachedProcessName(processId);

						windows.Add(new WindowInfo
						{
							Handle = hWnd,
							Title = sb.ToString(),
							ProcessName = processName,
							ProcessId = processId,
							Left = rect.Left,
							Top = rect.Top,
							Right = rect.Right,
							Bottom = rect.Bottom
						});
					}
				}
				return true;
			}, IntPtr.Zero);
			return windows;
		}

		/// <summary>
		/// Enumerates display adapters and their monitors via EnumDisplayDevices to build a mapping
		/// from WinForms DeviceName (e.g., "\\.\DISPLAY2") to the EDID hardware code (e.g., "LEN8ABC")
		/// and PnP monitor-instance used by FancyZones in applied-layouts.json.
		/// </summary>
		public static List<MonitorDeviceInfo> GetMonitorDeviceInfo()
		{
			var result = new List<MonitorDeviceInfo>();

			DISPLAY_DEVICE adapter = new DISPLAY_DEVICE();
			adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));

			for (uint i = 0; EnumDisplayDevices(null, i, ref adapter, 0); i++)
			{
				string adapterName = adapter.DeviceName;
				if (string.IsNullOrEmpty(adapterName)) { adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE)); continue; }
				adapterName = adapterName.TrimEnd('\0');

				DISPLAY_DEVICE monitor = new DISPLAY_DEVICE();
				monitor.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));

				if (EnumDisplayDevices(adapterName, 0, ref monitor, 0))
				{
					string deviceId = monitor.DeviceID;
					if (!string.IsNullOrEmpty(deviceId))
					{
						// DeviceID format: "Monitor\LEN8ABC\{4&...&UID...}" or "Monitor\LEN8ABC\4&...&UID..."
						string[] parts = deviceId.Split('\\');
						if (parts.Length >= 2)
						{
							string monitorInstance = parts.Length >= 3 ? parts[2].Trim('{', '}') : "";
							result.Add(new MonitorDeviceInfo
							{
								DisplayName = adapterName,
								EdidCode = parts[1],
								MonitorInstance = monitorInstance
							});
						}
					}
				}

				adapter.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
			}

			return result;
		}

		/// <summary>
		/// Sets or removes the topmost (always-on-top) flag for a window without moving or resizing it.
		/// </summary>
		public static bool SetWindowTopmost(IntPtr hWnd, bool topmost)
		{
			IntPtr insertAfter = topmost ? HWND_TOPMOST : HWND_NOTOPMOST;
			uint flags = SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE;
			return SetWindowPos(hWnd, insertAfter, 0, 0, 0, 0, flags);
		}

		/// <summary>
		/// Reliable focus acquisition with thread attachment.
		/// </summary>
		public static bool ForceForegroundWindow(IntPtr hWnd)
		{
			uint currentThreadId = GetCurrentThreadId();
			uint targetThreadId = GetWindowThreadProcessId(hWnd, IntPtr.Zero);

			bool attached = false;
			if (currentThreadId != targetThreadId)
			{
				attached = AttachThreadInput(currentThreadId, targetThreadId, true);
			}

			try
			{
				AllowSetForegroundWindow(ASFW_ANY);
				ShowWindow(hWnd, SW_RESTORE);
				BringWindowToTop(hWnd);
				SetForegroundWindow(hWnd);
				return GetForegroundWindow() == hWnd;
			}
			finally
			{
				if (attached)
				{
					AttachThreadInput(currentThreadId, targetThreadId, false);
				}
			}
		}

		/// <summary>
		/// Returns true when the window belongs to a known browser process.
		/// </summary>
		public static bool IsBrowserWindow(IntPtr hWnd)
		{
			uint processId;
			GetWindowThreadProcessId(hWnd, out processId);
			if (processId == 0) return false;

			string processName = GetCachedProcessName(processId);
			if (string.IsNullOrEmpty(processName)) return false;

			return _browserProcessNames.Contains(processName);
		}

		/// <summary>
		/// Sends a key combination using SendInput (batched, faster than keybd_event).
		/// Keys are pressed in order, then released in reverse order.
		/// </summary>
		public static void SendKeyCombination(params byte[] vkCodes)
		{
			int inputCount = vkCodes.Length * 2; // Press + Release for each key
			INPUT[] inputs = new INPUT[inputCount];

			// Press keys
			for (int i = 0; i < vkCodes.Length; i++)
			{
				inputs[i].type = INPUT_KEYBOARD;
				inputs[i].u.ki.wVk = vkCodes[i];
				inputs[i].u.ki.dwFlags = 0; // Key down
			}

			// Release keys in reverse order
			for (int i = 0; i < vkCodes.Length; i++)
			{
				int releaseIndex = vkCodes.Length + i;
				int keyIndex = vkCodes.Length - 1 - i;
				inputs[releaseIndex].type = INPUT_KEYBOARD;
				inputs[releaseIndex].u.ki.wVk = vkCodes[keyIndex];
				inputs[releaseIndex].u.ki.dwFlags = KEYEVENTF_KEYUP;
			}

			uint injected = SendInput((uint)inputCount, inputs, Marshal.SizeOf(typeof(INPUT)));

			// A partially inserted batch (input blocked mid-stream by another thread)
			// can deliver key-downs whose matching key-ups never made it in, leaving a
			// modifier logically held for the whole session. Compensate immediately
			// with an explicit key-up for every key in the combination. Key-ups for
			// keys that never went down are ignored by the input system, so this is
			// safe even when only the down half was cut off. When nothing was inserted
			// (injected == 0) no key is stranded and no compensation is needed.
			if (injected > 0 && injected < (uint)inputCount)
			{
				INPUT[] compensation = new INPUT[vkCodes.Length];
				for (int i = 0; i < vkCodes.Length; i++)
				{
					int keyIndex = vkCodes.Length - 1 - i;
					compensation[i].type = INPUT_KEYBOARD;
					compensation[i].u.ki.wVk = vkCodes[keyIndex];
					compensation[i].u.ki.dwFlags = KEYEVENTF_KEYUP;
				}
				SendInput((uint)compensation.Length, compensation, Marshal.SizeOf(typeof(INPUT)));
			}
		}

		/// <summary>
		/// Modifier keys an interrupted synthesized-input sequence can leave logically
		/// stuck, checked and released as left/right/neutral variants because the input
		/// system tracks each virtual key separately. Extended marks keys whose scan
		/// codes carry the 0xE0 prefix so an injected key-up mirrors the key-down shape.
		/// </summary>
		private sealed class ModifierKeyInfo
		{
			public readonly ushort Vk;
			public readonly string Name;
			public readonly bool Extended;

			public ModifierKeyInfo(ushort vk, string name, bool extended)
			{
				Vk = vk;
				Name = name;
				Extended = extended;
			}
		}

		private static readonly ModifierKeyInfo[] _releasableModifiers = new ModifierKeyInfo[]
		{
			new ModifierKeyInfo(VK_LSHIFT,   "LShift", false),
			new ModifierKeyInfo(VK_RSHIFT,   "RShift", false),
			new ModifierKeyInfo(VK_SHIFT,    "Shift",  false),
			new ModifierKeyInfo(VK_LCONTROL, "LCtrl",  false),
			new ModifierKeyInfo(VK_RCONTROL, "RCtrl",  true),
			new ModifierKeyInfo(VK_CONTROL,  "Ctrl",   false),
			new ModifierKeyInfo(VK_LMENU,    "LAlt",   false),
			new ModifierKeyInfo(VK_RMENU,    "RAlt",   true),
			new ModifierKeyInfo(VK_MENU,     "Alt",    false),
			new ModifierKeyInfo(VK_LWIN,     "LWin",   true),
			new ModifierKeyInfo(VK_RWIN,     "RWin",   true)
		};

		/// <summary>
		/// Names of the modifier keys the session currently reports as held down
		/// (GetAsyncKeyState high bit), whether pressed physically or injected.
		/// Diagnostic companion to ReleaseModifierKeys - performs no injection.
		/// </summary>
		public static List<string> GetStuckModifierKeys()
		{
			List<string> down = new List<string>();
			foreach (ModifierKeyInfo mod in _releasableModifiers)
			{
				if ((GetAsyncKeyState(mod.Vk) & 0x8000) != 0)
				{
					down.Add(mod.Name);
				}
			}
			return down;
		}

		/// <summary>
		/// Releases every modifier key the session currently reports as held down by
		/// injecting the matching key-up events in a single SendInput batch. This clears
		/// a modifier left logically stuck by an interrupted synthesized-input sequence -
		/// the same keyboard state a sign-out/sign-in resets - without touching toggle
		/// keys such as Caps Lock. Keys that are not held are never sent, so a quiescent
		/// keyboard makes this a read-only no-op. Optionally releases a stuck left mouse
		/// button (an interrupted ShiftDragSnap strands it in the pressed state).
		/// Returns the names of the keys that were released; empty when none were stuck.
		/// </summary>
		public static List<string> ReleaseModifierKeys(bool includeMouseButton)
		{
			List<string> released = new List<string>();
			List<INPUT> inputs = new List<INPUT>();

			foreach (ModifierKeyInfo mod in _releasableModifiers)
			{
				if ((GetAsyncKeyState(mod.Vk) & 0x8000) == 0)
				{
					continue;
				}

				INPUT input = new INPUT();
				input.type = INPUT_KEYBOARD;
				input.u.ki.wVk = mod.Vk;
				input.u.ki.dwFlags = mod.Extended ? (KEYEVENTF_KEYUP | KEYEVENTF_EXTENDEDKEY) : KEYEVENTF_KEYUP;
				inputs.Add(input);
				released.Add(mod.Name);
			}

			if (inputs.Count > 0)
			{
				SendInput((uint)inputs.Count, inputs.ToArray(), Marshal.SizeOf(typeof(INPUT)));
			}

			if (includeMouseButton && (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0)
			{
				mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
				released.Add("LButton");
			}

			return released;
		}

		/// <summary>
		/// Releases stuck modifier keys only (keyboard state, no mouse buttons).
		/// </summary>
		public static List<string> ReleaseModifierKeys()
		{
			return ReleaseModifierKeys(false);
		}

		/// <summary>
		/// Sends Win+Ctrl+Alt+Number for FancyZones layout switching.
		/// </summary>
		public static void SendFancyZonesLayoutShortcut(int layoutNumber)
		{
			if (layoutNumber < 0 || layoutNumber > 9) return;

			byte numberKey = (byte)(0x30 + layoutNumber); // 0x30 = '0'
			SendKeyCombination(VK_LWIN, VK_CONTROL, VK_MENU, numberKey);
		}

		/// <summary>
		/// Sends Win+Arrow key for window snapping.
		/// </summary>
		public static void SendSnapKey(bool up)
		{
			byte arrowKey = up ? VK_UP : VK_DOWN;
			SendKeyCombination(VK_LWIN, arrowKey);
		}

		/// <summary>
		/// Shift-drag snap: simulates holding Shift and dragging the window to trigger FancyZones.
		/// Consolidated from Snap-AllWindows to avoid duplicate type definitions.
		/// </summary>
		public static bool ShiftDragSnap(IntPtr hWnd, int targetX, int targetY, int targetWidth, int targetHeight)
		{
			// Default start point: top-left inset.
			return ShiftDragSnap(hWnd, targetX, targetY, targetWidth, targetHeight, 0);
		}

		/// <summary>
		/// Shift-drag snap with configurable drag start point on the top toolbar/title bar.
		/// dragStartMode: 0 = left inset, 1 = center, 2 = right-third center (~2/3 width).
		/// </summary>
		public static bool ShiftDragSnap(IntPtr hWnd, int targetX, int targetY, int targetWidth, int targetHeight, int dragStartMode)
		{
			// Get current window position
			RECT rect;
			if (!GetWindowRect(hWnd, out rect)) return false;

			int windowWidth = rect.Right - rect.Left;
			int minX = rect.Left + 8;
			int maxX = Math.Max(minX, rect.Right - 8);

			int titleBarX;
			if (dragStartMode == 1)
			{
				titleBarX = rect.Left + (windowWidth / 2);
			}
			else if (dragStartMode == 2)
			{
				titleBarX = rect.Left + ((windowWidth * 2) / 3);
			}
			else
			{
				// Left inset start remains default to avoid tab-undocking sensitivity.
				titleBarX = minX;
			}

			// Clamp to safe draggable area.
			titleBarX = Math.Max(minX, Math.Min(maxX, titleBarX));
			int titleBarY = rect.Top + 8;

			// Calculate target zone center
			int zoneCenterX = targetX + targetWidth / 2;
			int zoneCenterY = targetY + targetHeight / 2;

			// Focus the window first
			ForceForegroundWindow(hWnd);
			Thread.Sleep(50);

			// Move cursor to title bar
			SetCursorPos(titleBarX, titleBarY);
			Thread.Sleep(30);

			// Press Shift key. No KEYEVENTF_EXTENDEDKEY: Shift is not an extended key,
			// and the release in the finally block must mirror the press exactly - an
			// asymmetric down/up pair risks registering as different key variants and
			// leaving a phantom held Shift for the session.
			keybd_event(VK_SHIFT, 0, 0, UIntPtr.Zero);

			// The held Shift and mouse button are SESSION-GLOBAL state: anything that
			// cuts this sequence short between press and release leaves them logically
			// held until something injects the matching up events (the "terminal input
			// locks up / letters come out as caps" known issue). The finally block
			// guarantees release on every managed exit path; only a hard process kill
			// mid-drag can still strand them, which Reset-KeyboardModifiers heals.
			bool mouseIsDown = false;
			try
			{
				Thread.Sleep(20);

				// Mouse down on title bar
				mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
				mouseIsDown = true;
				Thread.Sleep(30);

				// Move to target zone center (in small steps to ensure FancyZones detects the drag)
				int steps = 10;
				for (int i = 1; i <= steps; i++)
				{
					int currentX = titleBarX + (zoneCenterX - titleBarX) * i / steps;
					int currentY = titleBarY + (zoneCenterY - titleBarY) * i / steps;
					SetCursorPos(currentX, currentY);
					Thread.Sleep(10);
				}

				// Small pause at destination for FancyZones to show zone
				Thread.Sleep(100);
			}
			finally
			{
				// Release mouse
				if (mouseIsDown)
				{
					mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
					Thread.Sleep(30);
				}

				// Release Shift key
				keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
			}
			Thread.Sleep(50);

			return true;
		}

		#endregion
	}

	#endregion
}
