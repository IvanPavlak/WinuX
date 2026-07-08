<#
LAYOUT VISUALIZATION
================================================================================
This shows how windows are arranged across all virtual desktops and monitors.
Organized by: Virtual Desktop > Monitor (Primary, Secondary, etc.) > Layout Type
================================================================================

VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: Zero
┌────────────────────────────────────────────────────┐
│                  WindowsTerminal                   │
│                                                    │
└────────────────────────────────────────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 2 - Monitor: Primary - Layout: One
┌─────────────────────────┬──────────────────────────┐
│         Browser         │         Browser          │
│                         │                          │
└─────────────────────────┴──────────────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 3 - Monitor: Primary - Layout: Two
┌────────────────┬────────────────┬──────────────────┐
│    Browser     │    Browser     │     Browser      │
│                │                │                  │
└────────────────┴────────────────┴──────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 4 - Monitor: Primary - Layout: Three
┌────────────┬────────────┬────────────┬─────────────┐
│  Browser   │  Browser   │  Browser   │   Browser   │
│            │            │            │             │
└────────────┴────────────┴────────────┴─────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 5 - Monitor: Primary - Layout: Four
┌─────────────────────────┬──────────────────────────┐
│         Browser         │         Browser          │
│                         │                          │
├─────────────────────────┼──────────────────────────┤
│         Browser         │         Browser          │
│                         │                          │
└─────────────────────────┴──────────────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 6 - Monitor: Primary - Layout: Five
┌─────────────────────────────────┬──────────────────┐
│             Browser             │     Browser      │
│                                 │                  │
└─────────────────────────────────┴──────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 7 - Monitor: Primary - Layout: Six
┌─────────────────────────┬──────────────────────────┐
│         Browser         │         Browser          │
│                         │                          │
│                         ├──────────────────────────┤
│                         │         Browser          │
│                         │                          │
└─────────────────────────┴──────────────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 8 - Monitor: Primary - Layout: Seven
┌────────────────┬────────────────┬──────────────────┐
│    Browser     │    Browser     │     Browser      │
│                │                │                  │
│                │                ├──────────────────┤
│                │                │     Browser      │
│                │                │                  │
└────────────────┴────────────────┴──────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 9 - Monitor: Primary - Layout: Eight
┌────────────────┬────────────────┬──────────────────┐
│    Browser     │    Browser     │     Browser      │
│                │                │                  │
│                ├────────────────┼──────────────────┤
│                │    Browser     │     Browser      │
│                │                │                  │
└────────────────┴────────────────┴──────────────────┘
--------------------------------------------------------------------------------

VIRTUAL DESKTOP 10 - Monitor: Primary - Layout: Nine
┌────────────────┬────────────────┬──────────────────┐
│    Browser     │    Browser     │     Browser      │
│                │                │                  │
├────────────────┼────────────────┼──────────────────┤
│    Browser     │    Browser     │     Browser      │
│                │                │                  │
└────────────────┴────────────────┴──────────────────┘

#>
@{
	Monitors = @{
		Primary = @{
			VirtualDesktopLayouts = @{
				1  = "Zero"
				2  = "One"
				3  = "Two"
				4  = "Three"
				5  = "Four"
				6  = "Five"
				7  = "Six"
				8  = "Seven"
				9  = "Eight"
				10 = "Nine"
			}
		}
	}

	Layout   = @(
		# ==========================================================================
		# VIRTUAL DESKTOP 1 - Monitor: Primary - Layout: Zero
		# ==========================================================================
		@{
			ProcessName   = "WindowsTerminal"
			WindowTitle   = ""
			DesktopNumber = 1
			Zone          = "Fullscreen"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 2 - Monitor: Primary - Layout: One
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 2
			Zone          = "Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 2
			Zone          = "Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 3 - Monitor: Primary - Layout: Two
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 3
			Zone          = "Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 3
			Zone          = "Middle"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 3
			Zone          = "Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 4 - Monitor: Primary - Layout: Three
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 4
			Zone          = "Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 4
			Zone          = "Middle-Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 4
			Zone          = "Middle-Right"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 4
			Zone          = "Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 5 - Monitor: Primary - Layout: Four
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 5
			Zone          = "Top-Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 5
			Zone          = "Bottom-Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 5
			Zone          = "Top-Right"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 5
			Zone          = "Bottom-Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 6 - Monitor: Primary - Layout: Five
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 6
			Zone          = "Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 6
			Zone          = "Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 7 - Monitor: Primary - Layout: Six
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 7
			Zone          = "Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 7
			Zone          = "Top-Right"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 7
			Zone          = "Bottom-Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 8 - Monitor: Primary - Layout: Seven
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 8
			Zone          = "Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 8
			Zone          = "Middle"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 8
			Zone          = "Top-Right"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 8
			Zone          = "Bottom-Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 9 - Monitor: Primary - Layout: Eight
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 9
			Zone          = "Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 9
			Zone          = "Top-Middle"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 9
			Zone          = "Bottom-Middle"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 9
			Zone          = "Top-Right"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 9
			Zone          = "Bottom-Right"
			Monitor       = "Primary"
		}

		# ==========================================================================
		# VIRTUAL DESKTOP 10 - Monitor: Primary - Layout: Nine
		# ==========================================================================
		@{
			ProcessName   = "Browser"
			DesktopNumber = 10
			Zone          = "Top-Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 10
			Zone          = "Bottom-Left"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 10
			Zone          = "Top-Middle"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 10
			Zone          = "Bottom-Middle"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 10
			Zone          = "Top-Right"
			Monitor       = "Primary"
		}
		@{
			ProcessName   = "Browser"
			DesktopNumber = 10
			Zone          = "Bottom-Right"
			Monitor       = "Primary"
		}
	)
}
