function Save-CurrentLayout {
	<#
	.SYNOPSIS
		Writes the current workspace layout to Window\Layouts\CurrentLayout.txt.

	.DESCRIPTION
		Called by Set-WorkspaceWindowLayout after a workspace has been fully applied and
		verified. Produces a single PowerShell data file (read back by Get-CurrentLayout via
		Import-PowerShellDataFile) that records, per open workspace:

		  - DesktopCount   : number of virtual desktops the workspace uses
		  - DesktopOffset  : the offset this run used (0 in normal mode, +N in -Alongside)
		  - Alongside      : whether this snapshot was produced by an -Alongside open
		  - Desktops       : the FancyZones layout applied to each monitor on each desktop
		  - Windows        : one record per window that was positioned and snapped, with its
		                     handle, process fingerprint, title, layout-relative desktop,
		                     monitor and zone - i.e. exactly where each window belongs

		The window records are supplied by the caller via -WindowStates - Set-WorkspaceWindowLayout
		builds them from the Set-WindowLayouts results so every configured window is captured,
		including ones already correctly placed and skipped this run (the snap-tracking set only
		holds windows that were actually repositioned, which would shrink the snapshot on an
		idempotent re-run and break pinning the next time). It falls back to the module-scoped
		$script:PositionedWindowHandles only when -WindowStates is not provided.

		"Reflect all open workspaces": a normal (non-alongside) open replaces the whole file
		because normal mode resets the virtual desktops, so only this workspace is on screen.
		An -Alongside open instead loads the existing snapshot and updates (or adds) only this
		workspace's section, preserving the records of the workspaces already running.

		Desktop numbers in window records are stored layout-relative (pre-offset, 1-based, the
		raw layout DesktopNumber) so the snapshot is offset-independent and re-usable whether
		the workspace is later reopened normally or alongside. The actual on-screen desktop is
		(record Desktop + section DesktopOffset).

		Writing is best-effort: any I/O failure is logged as a warning and swallowed so it can
		never fail an already-successful layout.

	.PARAMETER Workspace
		The workspace/layout name this snapshot belongs to (e.g. "Example_PC").

	.PARAMETER LayoutsDir
		The Layouts directory that holds CurrentLayout.txt (the value of
		$MachineSpecificPaths.Projects.Self.Layouts).

	.PARAMETER MachineType
		The machine type the layout was applied for (PC / Laptop / Work). Recorded for context.

	.PARAMETER DesktopOffset
		The desktop offset applied this run (0 normally, +N for alongside).

	.PARAMETER Alongside
		Present when the workspace was opened alongside existing desktops. Controls whether the
		file is merged (preserve other workspaces) or replaced.

	.PARAMETER DesktopCount
		Number of virtual desktops the workspace uses.

	.PARAMETER LayoutConfig
		The workspace layout array ($config.Layout). Reserved for future cross-referencing.

	.PARAMETER MonitorConfig
		The Monitors hashtable from the workspace .psd1 ($config.Monitors), used to record which
		FancyZones layout was applied to each monitor on each desktop.

	.PARAMETER WindowStates
		Optional. The positioned-window records to serialize. Defaults to the module-scoped
		$script:PositionedWindowHandles populated by Set-WindowLayouts. Pass @() for layouts
		that have no per-zone window placement (e.g. simple Fullscreen/Empty layouts).

	.EXAMPLE
		Save-CurrentLayout -Workspace 'Example_PC' -LayoutsDir $layoutsDir -MachineType 'PC' `
			-DesktopCount $requiredVirtualDesktops -MonitorConfig $config.Monitors -LayoutConfig $config.Layout
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$Workspace,

		[Parameter(Mandatory = $true)]
		[string]$LayoutsDir,

		[Parameter()]
		[string]$MachineType,

		[Parameter()]
		[int]$DesktopOffset = 0,

		[Parameter()]
		[switch]$Alongside,

		[Parameter()]
		[int]$DesktopCount = 1,

		[Parameter()]
		[array]$LayoutConfig,

		[Parameter()]
		[hashtable]$MonitorConfig,

		[Parameter()]
		[object]$WindowStates
	)

	if ([string]::IsNullOrWhiteSpace($LayoutsDir) -or [string]::IsNullOrWhiteSpace($Workspace)) {
		return
	}

	# Default to the live tracking set, but honour an explicit (possibly empty) override so
	# simple layouts can record desktops/zones with no window rows.
	if (-not $PSBoundParameters.ContainsKey('WindowStates')) {
		$WindowStates = $script:PositionedWindowHandles
	}

	# Recursive PSD1 literal serializer. Emits only data (strings, numbers, booleans,
	# hashtables, arrays) so the result round-trips through Import-PowerShellDataFile.
	$serialize = {
		param($Value, [int]$Indent)

		$pad = '    ' * $Indent
		$childPad = '    ' * ($Indent + 1)

		if ($null -eq $Value) { return '$null' }
		if ($Value -is [string]) { return "'" + ($Value -replace "'", "''") + "'" }
		if ($Value -is [bool]) { return $(if ($Value) { '$true' } else { '$false' }) }
		if ($Value -is [int] -or $Value -is [long] -or $Value -is [int64] -or $Value -is [uint32] -or $Value -is [uint64] -or $Value -is [double] -or $Value -is [single]) {
			return [string]$Value
		}

		if ($Value -is [System.Collections.IDictionary]) {
			if ($Value.Count -eq 0) { return '@{}' }
			$sb = [System.Text.StringBuilder]::new()
			[void]$sb.Append("@{`n")
			foreach ($key in $Value.Keys) {
				$keyText = if ("$key" -match '^[A-Za-z_][A-Za-z0-9_]*$') { "$key" } else { "'" + ("$key" -replace "'", "''") + "'" }
				$valText = & $serialize $Value[$key] ($Indent + 1)
				[void]$sb.Append("$childPad$keyText = $valText`n")
			}
			[void]$sb.Append("$pad}")
			return $sb.ToString()
		}

		if ($Value -is [System.Collections.IEnumerable]) {
			$items = @($Value)
			if ($items.Count -eq 0) { return '@()' }
			$sb = [System.Text.StringBuilder]::new()
			[void]$sb.Append("@(`n")
			foreach ($item in $items) {
				$itemText = & $serialize $item ($Indent + 1)
				[void]$sb.Append("$childPad$itemText`n")
			}
			[void]$sb.Append("$pad)")
			return $sb.ToString()
		}

		# Fallback: store the string form so the file stays valid data.
		return "'" + ("$Value" -replace "'", "''") + "'"
	}

	try {
		# --- Build the per-desktop FancyZones map (which layout per monitor per desktop) ---
		$desktops = [System.Collections.Generic.List[object]]::new()
		for ($d = 1; $d -le $DesktopCount; $d++) {
			$monitors = [ordered]@{}
			if ($MonitorConfig) {
				foreach ($monitorLabel in $MonitorConfig.Keys) {
					$monitorEntry = $MonitorConfig[$monitorLabel]
					if ($monitorEntry.VirtualDesktopLayouts -and $monitorEntry.VirtualDesktopLayouts.ContainsKey($d)) {
						$monitors[[string]$monitorLabel] = [string]$monitorEntry.VirtualDesktopLayouts[$d]
					}
				}
			}
			$desktops.Add([ordered]@{
					DesktopNumber = $d
					Monitors      = $monitors
				})
		}

		# --- Build one window record per tracked, positioned window ---
		$windows = [System.Collections.Generic.List[object]]::new()
		if ($WindowStates) {
			foreach ($state in $WindowStates) {
				if (-not $state) { continue }

				$handleValue = 0
				try { $handleValue = ([IntPtr]$state.Handle).ToInt64() } catch { $handleValue = 0 }

				# Store desktop layout-relative (strip the run's offset) so the snapshot is
				# reusable regardless of where the workspace currently lives.
				$relativeDesktop = if ($null -ne $state.DesktopNumber) { [int]$state.DesktopNumber - $DesktopOffset } else { 1 }
				if ($relativeDesktop -lt 1) { $relativeDesktop = 1 }

				$windows.Add([ordered]@{
						Handle         = $handleValue
						ProcessName    = [string]$state.ProcessName
						ProcessId      = [uint32]($state.ProcessId)
						WindowTitle    = [string]$state.WindowTitle
						Desktop        = $relativeDesktop
						Monitor        = [string]$state.Monitor
						Layout         = [string]$state.Layout
						Zone           = [string]$state.Zone
						ExpectedX      = [int]$state.ExpectedX
						ExpectedY      = [int]$state.ExpectedY
						ExpectedWidth  = [int]$state.ExpectedWidth
						ExpectedHeight = [int]$state.ExpectedHeight
					})
			}
		}

		$section = [ordered]@{
			Workspace     = $Workspace
			Alongside     = [bool]$Alongside
			DesktopOffset = $DesktopOffset
			DesktopCount  = $DesktopCount
			Desktops      = $desktops.ToArray()
			Windows       = $windows.ToArray()
		}

		# --- Merge with existing sections so alongside preserves other open workspaces ---
		$workspaces = [ordered]@{}
		if ($Alongside) {
			$existing = Get-CurrentLayout -LayoutsDir $LayoutsDir
			if ($existing -and $existing.Workspaces) {
				foreach ($key in $existing.Workspaces.Keys) {
					$workspaces[[string]$key] = $existing.Workspaces[$key]
				}
			}
		}
		$workspaces[$Workspace] = $section

		$root = [ordered]@{
			MachineType = if ($MachineType) { $MachineType } else { '' }
			Workspaces  = $workspaces
		}

		$header = @(
			'# CurrentLayout.txt - auto-generated snapshot of the most recently applied workspace(s).'
			'# Written by Save-CurrentLayout after a successful Set-WorkspaceWindowLayout; read by'
			'# Get-CurrentLayout. Do not edit by hand - it is overwritten on every workspace open.'
			'# Desktop numbers in window records are layout-relative (actual = Desktop + DesktopOffset).'
		) -join "`n"

		$body = & $serialize $root 0
		$content = "$header`n$body`n"

		if (-not (Test-Path -Path $LayoutsDir)) {
			New-Item -ItemType Directory -Path $LayoutsDir -Force -ErrorAction Stop | Out-Null
		}

		$path = Join-Path $LayoutsDir 'CurrentLayout.txt'
		Set-Content -Path $path -Value $content -NoNewline -Encoding UTF8 -ErrorAction Stop

		Write-LogDebug " Current layout recorded => [$path] ($($windows.Count) window(s), $DesktopCount desktop(s))" -Style Success
	}
	catch {
		# Never fail an already-successful layout because of a snapshot write error.
		Write-LogWarning "Could not write CurrentLayout.txt: $($_.Exception.Message)" -NoLeadingNewline
	}
}
