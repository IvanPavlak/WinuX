function Write-WindowInfoBlock {
	<#
	.SYNOPSIS
		Writes a formatted terminal block for a window info object.

	.DESCRIPTION
		Prints a window's process name, title, handle, process ID, position, size,
		and a ready-to-copy configuration template. Used by
		`Get-ActiveWindowInfo -Continuous` when focus changes.

	.PARAMETER Info
		Window information object containing `ProcessName`, `Title`, `Handle`,
		`ProcessId`, `X`, `Y`, `Width`, and `Height`.

	.EXAMPLE
		Write-WindowInfoBlock -Info $windowInfo
		Writes a formatted info block for the supplied window object.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[PSCustomObject]$Info
	)

	Write-Host -ForegroundColor DarkCyan (Create-CenteredBorder -Title $Info.ProcessName -BorderChar '-')
	Write-Host -ForegroundColor DarkCyan "Process Name  : " -NoNewline
	Write-Host -ForegroundColor White $Info.ProcessName
	Write-Host -ForegroundColor DarkCyan "Window Title  : " -NoNewline
	Write-Host -ForegroundColor White $Info.Title
	Write-Host -ForegroundColor DarkCyan "Window Handle : " -NoNewline
	Write-Host -ForegroundColor White "0x$($Info.Handle.ToString('X'))"
	Write-Host -ForegroundColor DarkCyan "Process ID    : " -NoNewline
	Write-Host -ForegroundColor White $Info.ProcessId
	Write-Host -ForegroundColor DarkCyan "Position      : " -NoNewline
	Write-Host -ForegroundColor White "($($Info.X), $($Info.Y))"
	Write-Host -ForegroundColor DarkCyan "Size          : " -NoNewline
	Write-Host -ForegroundColor White "$($Info.Width)x$($Info.Height)"
	Write-Host ""
	Write-LogStep "Config template:" -NoLeadingNewline
	Write-LogStep "@{
    ProcessName   = `"$($Info.ProcessName)`"
    WindowTitle   = `"$($Info.Title)`"
    DesktopNumber = 1
    Zone          = `"Zone`"
    Monitor       = `"Monitor`"
}" -NoLeadingNewline
}
