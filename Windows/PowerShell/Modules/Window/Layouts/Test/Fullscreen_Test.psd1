<#
LAYOUT VISUALIZATION
================================================================================
This shows how windows are arranged across all virtual desktops and monitors.
Organized by: Virtual Desktop > Monitor (Primary, Secondary, etc.) > Layout Type
================================================================================

VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: Zero
┌────────────────────────────────────────────────────┐
│                     Fullscreen                     │
│                                                    │
└────────────────────────────────────────────────────┘

#>
@{
	Monitors = @{
		Primary = @{
			VirtualDesktopLayouts = @{
				1 = "Zero"
			}
		}
	}

	Layout   = @(
		# ==========================================================================
		# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: Zero
		# ==========================================================================
		@{
			ProcessName   = $null
			WindowTitle   = $null
			DesktopNumber = 1
			Zone          = "Fullscreen"
			Monitor       = "Primary"
		}
	)
}
