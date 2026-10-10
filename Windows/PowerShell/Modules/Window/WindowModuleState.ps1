# Module-scoped state, initialized once at import.
#
# Kept in its own file, dot-sourced by Window.psm1, so that the test suite can put the module back
# to exactly its freshly imported state (Tests/Modules/Support/Reset-WindowModuleState.ps1) by
# running this same code, instead of paying for a full `Import-Module -Force` - re-dot-sourcing
# every function file - in every test file that needs clean caches. Everything assigned here must
# use the $script: scope.

# Module-scoped timing configuration (in milliseconds)
# These can be adjusted for performance tuning while maintaining reliability
# From personal experience, on stronger machines 10ms is a bit too fast - 25 seems to be the sweet spot for 100% reliability
$script:WindowModuleDelays = @{
	# Delay after cursor movement before sending keys (monitor activation)
	CursorSettleMs     = 25
	# Delay after SetForegroundWindow before sending keys
	FocusSettleMs      = 25
	# Delay after keyboard shortcut is sent (for FancyZones to process)
	KeyboardShortcutMs = 25
	# Delay allowing FancyZones to asynchronously commit a layout switch to disk before
	# a virtual-desktop switch fires. Too short a delay lets the last desktop's layout
	# "bleed" onto the desktop we switch back to (see Apply-FancyZones return-desktop reapply).
	LayoutCommitMs     = 25
	# Delay after ShowWindow restore operations
	WindowRestoreMs    = 25
	# Delay after SetWindowPos for window to settle
	WindowPositionMs   = 25
	# Delay after Move-Window for virtual desktop operations
	VirtualDesktopMs   = 25
	# Delay after writing applied-layouts.json before the probe shortcut that confirms FancyZones
	# reloaded it. FancyZones' file watcher posts the reload to its main thread; its own log shows
	# the reload landing 40-60 ms after a write, so this leaves headroom without adding real time.
	AppliedLayoutsReloadMs = 150
}

# Module-scoped position tolerances (in pixels)
# PositionVerificationPx is the shared tolerance for post-move, post-snap,
# and final layout verification. PreSnapValidationPx stays looser because
# some applications drift slightly before FancyZones snapping runs.
$script:WindowModuleTolerances = @{
	PositionVerificationPx = 20
	PreSnapValidationPx    = 75
}

# Window enumeration cache for reducing repeated EnumWindows syscalls
$script:WindowCache = @{
	Windows   = $null
	Timestamp = [datetime]::MinValue
	MaxAgeMs  = 50  # Cache valid for 50ms (adjustable)
}

# Windows Forms loaded state - avoids repeated Add-Type calls
$script:WindowsFormsLoaded = $false

# FancyZones JSON cache - avoids repeated file reads and JSON parsing
$script:FancyZonesCache = @{
	Path      = $null
	Data      = $null
	Timestamp = [datetime]::MinValue
	MaxAgeSec = 60  # Cache valid for 60 seconds (file rarely changes)
}

# VirtualDesktop module lazy loading - avoids Get-Module calls on every function invocation
$script:VirtualDesktopState = @{
	Checked   = $false
	Available = $false
	Loaded    = $false
}

# Monitor info cache - avoids repeated [System.Windows.Forms.Screen]::AllScreens calls.
# Fingerprint holds a cheap display-topology signature (see Get-CachedMonitors) so an attach,
# detach or resolution change invalidates the cache immediately instead of waiting out the TTL.
# The TTL is deliberately short: monitor LABELS are derived from physical position
# (Get-MonitorSpecs), so a stale entry hands out labels for an arrangement that no longer
# exists, and a workspace open reads the monitors once and reuses them throughout.
$script:MonitorCache = @{
	Monitors    = $null
	Timestamp   = [datetime]::MinValue
	Fingerprint = $null
	MaxAgeSec   = 5  # Backstop for topology changes the fingerprint cannot see
}

# Applied FancyZones layouts cache - for idempotency checks in Apply-FancyZones
# Reads applied-layouts.json to detect already-applied layouts and skip redundant shortcuts
$script:AppliedLayoutsCache = @{
	Data      = $null
	Timestamp = [datetime]::MinValue
	MaxAgeSec = 10  # Short TTL - file changes when layouts are applied
}

# The exact Open-Workspace invocation of the open in progress, for the failure-path respawn
# (Set-WorkspaceWindowLayout -> ReRun-LastCommand -Command). Module state on purpose: an
# environment variable is inherited by every terminal tab the open spawns, and a standalone
# layout escalation typed into such a tab would then respawn the whole inherited open.
$script:WorkspaceRerunCommand = $null
