# Compile native Windows API types once at module load
if (-not ([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
	$nativePath = Join-Path -Path $PSScriptRoot -ChildPath "WindowNative.cs"
	if (Test-Path $nativePath) {
		$nativeCode = Get-Content -Path $nativePath -Raw
		Add-Type -TypeDefinition $nativeCode -Language CSharp -ErrorAction Stop
	}
	else {
		Write-Warning "WindowNative.cs not found at $nativePath - native optimizations disabled"
	}
}

# Opt this process into Per-Monitor-V2 DPI awareness BEFORE any window/monitor API is
# used. FancyZones works in physical pixels; a DPI-unaware process sees virtualized
# coordinates on any display scale above 100%, which silently breaks zone math and snap
# verification. At 100% scaling this changes nothing. No-op (returns false) if the
# process awareness was already fixed by a manifest or an earlier call.
if (([System.Management.Automation.PSTypeName]'WindowModule.Native').Type) {
	[void][WindowModule.Native]::EnablePerMonitorDpiAwareness()
}

# Module-scoped timing configuration (in milliseconds)
# These can be adjusted for performance tuning while maintaining reliability
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

# Monitor info cache - avoids repeated [System.Windows.Forms.Screen]::AllScreens calls
$script:MonitorCache = @{
	Monitors  = $null
	Timestamp = [datetime]::MinValue
	MaxAgeSec = 30  # Cache valid for 30 seconds (monitors rarely change)
}

# Applied FancyZones layouts cache - for idempotency checks in Apply-FancyZones
# Reads applied-layouts.json to detect already-applied layouts and skip redundant shortcuts
$script:AppliedLayoutsCache = @{
	Data      = $null
	Timestamp = [datetime]::MinValue
	MaxAgeSec = 10  # Short TTL - file changes when layouts are applied
}

$ModulesPath = Join-Path -Path $PSScriptRoot -ChildPath "\Functions"

$Functions = Get-ChildItem -Path (Join-Path $ModulesPath "*.ps1")

foreach ($Function in $Functions) {
	. $Function.FullName
}

$Functions | ForEach-Object {
	$FunctionName = $_.BaseName
	Export-ModuleMember -Function $FunctionName
}
