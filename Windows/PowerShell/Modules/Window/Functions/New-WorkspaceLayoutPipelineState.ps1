function New-WorkspaceLayoutPipelineState {
	<#
	.SYNOPSIS
		Creates the shared state of one workspace layout pass: what it lays out, with what, and what it has placed so far.

	.DESCRIPTION
		Set-WorkspaceWindowLayout used to hold this state in a dozen locals and reach them from
		two inline scriptblocks it handed to Wait-ForWorkspaceWindows as callbacks. Those callbacks
		are named functions now (Move-StableWindowEarly, Invoke-ReadyDesktopPass) and this object is
		the one argument they take: the immutable inputs of the pass and the live tallies the
		per-desktop passes fill in while the wait is still running, which the tail after the wait
		then finishes.

		Inputs (set once):
		  LayoutConfig, MonitorInfo, MonitorConfig, DesktopOffset, DesktopCount, Alongside,
		  Claims (New-WindowClaimSet), ZoneReset (scriptblock run when a snap exhausts its attempts),
		  RecordPhase (scriptblock booking elapsed time to a named phase), SpinnerActive.

		Live tallies (filled by the per-desktop passes):
		  PipelinedDesktops (desktop number -> $true), PipelinedEntryKeys, PipelinedResults,
		  PipelinedSnapFailures, and Claims.Excluded, which receives every handle a pass placed so
		  no later entry can carry it off.

	.PARAMETER LayoutConfig
		The layout entries to apply, tokens already resolved.

	.PARAMETER Claims
		The window claim set for this open (New-WindowClaimSet).

	.PARAMETER MonitorInfo
		The monitor list the layout resolves against.

	.PARAMETER MonitorConfig
		The layout's monitor section (zone grids per monitor).

	.PARAMETER DesktopOffset
		Virtual desktop offset for an alongside open.

	.PARAMETER DesktopCount
		How many virtual desktops the layout needs.

	.PARAMETER Alongside
		Whether this is an alongside open.

	.PARAMETER ZoneReset
		Scriptblock (one string argument, the reason) that resets FancyZones and re-applies the zone grids.

	.PARAMETER RecordPhase
		Scriptblock (one string argument, the phase name) that books elapsed time to that phase.

	.PARAMETER SpinnerActive
		Whether a Loading-Spinner is running and must be paused around a per-desktop pass.

	.OUTPUTS
		[pscustomobject] with the inputs above and the live tallies.

	.EXAMPLE
		$pipeline = New-WorkspaceLayoutPipelineState -LayoutConfig $layout -Claims $claims -MonitorInfo $monitors -MonitorConfig $config.Monitors -DesktopOffset 0 -DesktopCount 3 -ZoneReset $reset -RecordPhase $record
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param(
		[Parameter(Mandatory = $true)]
		[AllowEmptyCollection()]
		[array]$LayoutConfig,

		[Parameter(Mandatory = $true)]
		[pscustomobject]$Claims,

		[Parameter()]
		[AllowNull()]
		[array]$MonitorInfo,

		[Parameter()]
		[AllowNull()]
		[hashtable]$MonitorConfig,

		[Parameter()]
		[int]$DesktopOffset = 0,

		[Parameter()]
		[int]$DesktopCount = 0,

		[Parameter()]
		[switch]$Alongside,

		[Parameter()]
		[AllowNull()]
		[scriptblock]$ZoneReset,

		[Parameter()]
		[AllowNull()]
		[scriptblock]$RecordPhase,

		[Parameter()]
		[switch]$SpinnerActive
	)

	return [pscustomobject]@{
		LayoutConfig          = $LayoutConfig
		Claims                = $Claims
		MonitorInfo           = $MonitorInfo
		MonitorConfig         = $MonitorConfig
		DesktopOffset         = $DesktopOffset
		DesktopCount          = $DesktopCount
		Alongside             = [bool]$Alongside
		ZoneReset             = $ZoneReset
		RecordPhase           = if ($RecordPhase) { $RecordPhase } else { { param([string]$Phase) } }
		SpinnerActive         = [bool]$SpinnerActive
		PipelinedDesktops     = @{}
		PipelinedEntryKeys    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
		PipelinedResults      = [System.Collections.Generic.List[PSObject]]::new()
		PipelinedSnapFailures = [System.Collections.Generic.List[object]]::new()
	}
}
