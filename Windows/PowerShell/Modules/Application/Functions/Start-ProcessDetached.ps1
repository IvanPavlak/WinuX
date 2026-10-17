function Start-ProcessDetached {
	<#
	.SYNOPSIS
		Starts a process that owns no console and is not tied to the current shell.

	.DESCRIPTION
		Creates the process through WMI (Win32_Process.Create). Its parent is the WMI provider
		host, which has no console, so the new process neither inherits this shell's console nor
		can attach to it (Electron applications attach to the console of the process that
		launched them). Windows Terminal closes a tab only when every process attached to the
		tab's console has disconnected, so an application launched with a plain
		Start-Process -NoNewWindow from a shell that then exits keeps that tab open, with no
		"[process exited with code ...]" line to show why. Start-VSCodeDetached and
		Start-ObsidianDetached launch through this function for that reason.

		Returns the new process id, or $null when WMI refuses or throws; the caller decides on a
		fallback. Nothing is written to the console on failure - the reason goes to the debug log.

	.PARAMETER FilePath
		The executable to start. Quoted into the command line as is.

	.PARAMETER ArgumentList
		Arguments appended to the command line, separated by spaces, exactly as given - quote a
		value that contains spaces yourself ("`"$path`""), as with Start-Process -ArgumentList.

	.PARAMETER WorkingDirectory
		The new process's current directory. Omit to let WMI choose (the user's profile folder).

	.OUTPUTS
		[int] The process id, or $null when the process could not be created.

	.EXAMPLE
		$processId = Start-ProcessDetached -FilePath "C:\Apps\Tool\Tool.exe" -ArgumentList "-n", "`"C:\My Project`""
		if (-not $processId) { Start-Process -FilePath "C:\Apps\Tool\Tool.exe" -ArgumentList "-n", "`"C:\My Project`"" }
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param (
		[Parameter(Mandatory = $true)]
		[string]$FilePath,

		[Parameter()]
		[string[]]$ArgumentList,

		[Parameter()]
		[string]$WorkingDirectory
	)

	$commandLine = "`"$FilePath`""
	if ($ArgumentList) {
		$commandLine += " " + ($ArgumentList -join " ")
	}

	$arguments = @{ CommandLine = $commandLine }
	if ($WorkingDirectory) {
		$arguments['CurrentDirectory'] = $WorkingDirectory
	}

	try {
		$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments $arguments -ErrorAction Stop
	}
	catch {
		Write-LogDebug " [Start-ProcessDetached] Win32_Process.Create threw for [$FilePath] => $($_.Exception.Message)" -Style Warning
		return $null
	}

	if ($result.ReturnValue -ne 0) {
		Write-LogDebug " [Start-ProcessDetached] Win32_Process.Create returned $($result.ReturnValue) for [$FilePath]" -Style Warning
		return $null
	}

	Write-LogDebug " [Start-ProcessDetached] Launched detached => $commandLine (pid $($result.ProcessId))" -Style Success
	return [int]$result.ProcessId
}
