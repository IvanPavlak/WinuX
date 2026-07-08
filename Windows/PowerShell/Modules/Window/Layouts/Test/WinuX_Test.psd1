<#
LAYOUT VISUALIZATION
================================================================================
This shows how windows are arranged across all virtual desktops and monitors.
Organized by: Virtual Desktop > Monitor (Primary, Secondary, etc.) > Layout Type
================================================================================

VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One
┌─────────────────────────┬──────────────────────────┐
│         Browser         │           Code           │
│         *WinuX*         │                          │
└─────────────────────────┴──────────────────────────┘

#>
@{
	Monitors = @{
		Primary = @{
			VirtualDesktopLayouts = @{
				1 = "One"
			}
		}
	}

	Layout   = @(
		# ==========================================================================
		# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: One
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			WindowTitle   = "*WinuX*"
			DesktopNumber = 1
			Zone          = "Left"
			Monitor       = "Primary"
		}

		@{
			ProcessName   = "Code"
			DesktopNumber = 1
			Zone          = "Right"
			Monitor       = "Primary"
		}
	)
}
