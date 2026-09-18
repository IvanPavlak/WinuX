# Shared fake for the VirtualDesktop dependency. Dot-source it in a test's BeforeAll after the
# function under test, then call New-FakeVirtualDesktopSession in BeforeEach.
#
# It stands in for the third-party module's cmdlets (Get-DesktopCount, Get-CurrentDesktop,
# Get-DesktopIndex, Get-DesktopFromWindow, Get-Desktop, Get-DesktopList, Switch-Desktop,
# Move-Window, New-Desktop, Remove-Desktop) and for the Window module's session plumbing
# (Import-VirtualDesktopModule, Reset-VirtualDesktopState, Get-RpcRetryPolicy,
# Test-RpcUnavailableError), all driven by one in-memory desktop model in
# $global:FakeVirtualDesktop. Every stub is a plain function, so a test can still Mock any of
# them for a case the model does not express.
#
# Failure injection: Set-FakeVirtualDesktopFailure -Cmdlet Get-DesktopCount -Times 1 makes the
# next call(s) to that cmdlet throw an RPC-classified error (0x800706BA), which is what a stale
# COM session looks like. Reset-VirtualDesktopState clears the injected failure and records that
# it ran, so a test can assert "recovered once" precisely.

function New-FakeVirtualDesktopSession {
	param(
		[int]$DesktopCount = 1,
		[int]$CurrentIndex = 0,
		# handle (int) -> desktop index
		[hashtable]$WindowDesktops = @{},
		[switch]$ModuleUnavailable
	)
	$desktops = [System.Collections.Generic.List[object]]::new()
	for ($i = 0; $i -lt $DesktopCount; $i++) {
		$desktops.Add([pscustomobject]@{ Id = [guid]::NewGuid(); Name = "Desktop $($i + 1)" })
	}
	$windows = @{}
	foreach ($key in $WindowDesktops.Keys) { $windows[[int64]$key] = [int]$WindowDesktops[$key] }
	$global:FakeVirtualDesktop = [pscustomobject]@{
		Desktops          = $desktops
		CurrentIndex      = $CurrentIndex
		WindowDesktops    = $windows
		SwitchLog         = [System.Collections.Generic.List[int]]::new()
		MoveLog           = [System.Collections.Generic.List[object]]::new()
		CreatedCount      = 0
		RemovedLog        = [System.Collections.Generic.List[int]]::new()
		ResetCount        = 0
		Failures          = @{}
		ModuleUnavailable = [bool]$ModuleUnavailable
	}
	return $global:FakeVirtualDesktop
}

function Set-FakeVirtualDesktopFailure {
	param(
		[Parameter(Mandatory)][string]$Cmdlet,
		[int]$Times = 1,
		[string]$Message = 'The RPC server is unavailable. (Exception from HRESULT: 0x800706BA)'
	)
	$global:FakeVirtualDesktop.Failures[$Cmdlet] = @{ Remaining = $Times; Message = $Message }
}

function Invoke-FakeVirtualDesktopFailure {
	param([string]$Cmdlet)
	$failure = $global:FakeVirtualDesktop.Failures[$Cmdlet]
	if ($failure -and $failure.Remaining -gt 0) {
		$failure.Remaining--
		throw [System.Runtime.InteropServices.COMException]::new($failure.Message, -2147023174)
	}
}

function Resolve-FakeDesktopIndex {
	param($Desktop)
	if ($null -eq $Desktop) { return -1 }
	if ($Desktop -is [int] -or $Desktop -is [int64]) { return [int]$Desktop }
	for ($i = 0; $i -lt $global:FakeVirtualDesktop.Desktops.Count; $i++) {
		if ($global:FakeVirtualDesktop.Desktops[$i].Id -eq $Desktop.Id) { return $i }
	}
	return -1
}

# ---- the VirtualDesktop module's cmdlets ------------------------------------------------------

function Get-DesktopCount {
	[CmdletBinding()] param()
	Invoke-FakeVirtualDesktopFailure 'Get-DesktopCount'
	return $global:FakeVirtualDesktop.Desktops.Count
}

function Get-DesktopList {
	[CmdletBinding()] param()
	Invoke-FakeVirtualDesktopFailure 'Get-DesktopList'
	$i = 0
	foreach ($d in $global:FakeVirtualDesktop.Desktops) {
		[pscustomobject]@{ Number = $i; Name = $d.Name; Id = $d.Id }
		$i++
	}
}

function Get-CurrentDesktop {
	[CmdletBinding()] param()
	Invoke-FakeVirtualDesktopFailure 'Get-CurrentDesktop'
	return $global:FakeVirtualDesktop.Desktops[$global:FakeVirtualDesktop.CurrentIndex]
}

function Get-Desktop {
	[CmdletBinding()] param([int]$Index)
	Invoke-FakeVirtualDesktopFailure 'Get-Desktop'
	if ($Index -lt 0 -or $Index -ge $global:FakeVirtualDesktop.Desktops.Count) { return $null }
	return $global:FakeVirtualDesktop.Desktops[$Index]
}

function Get-DesktopIndex {
	[CmdletBinding()] param([Parameter(Position = 0)]$Desktop)
	Invoke-FakeVirtualDesktopFailure 'Get-DesktopIndex'
	return (Resolve-FakeDesktopIndex $Desktop)
}

function Get-DesktopFromWindow {
	[CmdletBinding()] param($Hwnd)
	Invoke-FakeVirtualDesktopFailure 'Get-DesktopFromWindow'
	$key = [int64]$Hwnd
	if (-not $global:FakeVirtualDesktop.WindowDesktops.ContainsKey($key)) { return $null }
	$index = [int]$global:FakeVirtualDesktop.WindowDesktops[$key]
	if ($index -lt 0 -or $index -ge $global:FakeVirtualDesktop.Desktops.Count) { return $null }
	return $global:FakeVirtualDesktop.Desktops[$index]
}

function Switch-Desktop {
	[CmdletBinding()] param($Desktop)
	Invoke-FakeVirtualDesktopFailure 'Switch-Desktop'
	$index = Resolve-FakeDesktopIndex $Desktop
	if ($index -lt 0 -or $index -ge $global:FakeVirtualDesktop.Desktops.Count) { throw "Desktop $Desktop does not exist" }
	$global:FakeVirtualDesktop.SwitchLog.Add($index)
	$global:FakeVirtualDesktop.CurrentIndex = $index
}

function Move-Window {
	[CmdletBinding()] param($Desktop, $Hwnd)
	Invoke-FakeVirtualDesktopFailure 'Move-Window'
	$index = Resolve-FakeDesktopIndex $Desktop
	$global:FakeVirtualDesktop.MoveLog.Add([pscustomobject]@{ Hwnd = [int64]$Hwnd; Index = $index })
	$global:FakeVirtualDesktop.WindowDesktops[[int64]$Hwnd] = $index
	# The real cmdlet returns the Desktop object.
	return $global:FakeVirtualDesktop.Desktops[$index]
}

function New-Desktop {
	[CmdletBinding()] param()
	Invoke-FakeVirtualDesktopFailure 'New-Desktop'
	$n = $global:FakeVirtualDesktop.Desktops.Count + 1
	$desktop = [pscustomobject]@{ Id = [guid]::NewGuid(); Name = "Desktop $n" }
	$global:FakeVirtualDesktop.Desktops.Add($desktop)
	$global:FakeVirtualDesktop.CreatedCount++
	return $desktop
}

function Remove-Desktop {
	[CmdletBinding()] param($Desktop)
	Invoke-FakeVirtualDesktopFailure 'Remove-Desktop'
	$index = Resolve-FakeDesktopIndex $Desktop
	if ($index -lt 0 -or $index -ge $global:FakeVirtualDesktop.Desktops.Count) { throw "Desktop $Desktop does not exist" }
	if ($global:FakeVirtualDesktop.Desktops.Count -le 1) { throw 'The last desktop cannot be removed' }
	$global:FakeVirtualDesktop.Desktops.RemoveAt($index)
	$global:FakeVirtualDesktop.RemovedLog.Add($index)
	# Windows relocates the windows of a removed desktop to its left neighbour (or the first one)
	# and shifts every desktop to the right down by one.
	$relocateTo = [math]::Max(0, $index - 1)
	foreach ($key in @($global:FakeVirtualDesktop.WindowDesktops.Keys)) {
		$where = [int]$global:FakeVirtualDesktop.WindowDesktops[$key]
		if ($where -eq $index) { $global:FakeVirtualDesktop.WindowDesktops[$key] = $relocateTo }
		elseif ($where -gt $index) { $global:FakeVirtualDesktop.WindowDesktops[$key] = $where - 1 }
	}
	if ($global:FakeVirtualDesktop.CurrentIndex -ge $global:FakeVirtualDesktop.Desktops.Count) {
		$global:FakeVirtualDesktop.CurrentIndex = $global:FakeVirtualDesktop.Desktops.Count - 1
	}
}

# ---- the Window module's session plumbing ----------------------------------------------------

function Import-VirtualDesktopModule {
	[CmdletBinding()] param([switch]$Silent)
	return (-not $global:FakeVirtualDesktop.ModuleUnavailable)
}

function Reset-VirtualDesktopState {
	[CmdletBinding()] param()
	$global:FakeVirtualDesktop.ResetCount++
	$global:FakeVirtualDesktop.Failures.Clear()
	return $true
}

function Get-RpcRetryPolicy {
	[CmdletBinding()] param([string]$OperationLabel, [int]$MaxAttempts = 3, [int]$InitialDelayMs = 200, [switch]$Probe)
	return @{ MaxAttempts = $MaxAttempts; InitialDelayMs = 0 }
}

function Test-RpcUnavailableError {
	[CmdletBinding()] param([Parameter(Position = 0)][AllowNull()]$InputObject)
	$pattern = '0x800706BA|0x800706BE|0x80010108|0x800401FD|RPC server is unavailable|remote procedure call failed'
	$exception = if ($InputObject -is [System.Management.Automation.ErrorRecord]) { $InputObject.Exception } elseif ($InputObject -is [Exception]) { $InputObject } else { $null }
	if ($null -eq $exception) { return ([string]$InputObject) -match $pattern }
	while ($null -ne $exception) {
		if ($exception.Message -match $pattern) { return $true }
		if ($exception.HResult -and (('0x{0:X8}' -f $exception.HResult) -match $pattern)) { return $true }
		$exception = $exception.InnerException
	}
	return $false
}
