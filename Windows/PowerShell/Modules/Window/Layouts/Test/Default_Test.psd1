<#
LAYOUT VISUALIZATION
================================================================================
This shows how windows are arranged across all virtual desktops and monitors.
Organized by: Virtual Desktop > Monitor (Primary, Secondary, etc.) > Layout Type
================================================================================

VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: Zero
┌────────────────────────────────────────────────────┐
│                      Browser                       │
│                  Google\s*[-—].*                   │
└────────────────────────────────────────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 2 - Monitor: Primary - Layout: Zero
┌────────────────────────────────────────────────────┐
│                      Browser                       │
│                     *YouTube*                      │
└────────────────────────────────────────────────────┘

#>
@{
	Monitors = @{
		Primary = @{
			VirtualDesktopLayouts = @{
				1 = "Zero"
				2 = "Zero"
			}
		}
	}

	Layout   = @(
		# ==========================================================================
		# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: Zero
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			WindowTitle   = "Google\s*[-—].*"
			DesktopNumber = 1
			Zone          = "Fullscreen"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 2 - Monitor: Primary - Layout: Zero
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			WindowTitle   = "*YouTube*"
			DesktopNumber = 2
			Zone          = "Fullscreen"
			Monitor       = "Primary"
		}
	)
}
