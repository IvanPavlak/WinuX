function Start-ProcessDetached {
	<#
	.SYNOPSIS
		Starts a process that owns no console, or runs a Start-Process fallback when it cannot.

	.DESCRIPTION
		Creates the process through WMI (Win32_Process.Create). Its parent is the WMI provider
		host, which has no console, so the new process neither inherits this shell's console nor
		can attach to it. That is what lets a workspace close its own terminal tab afterwards:
		Windows Terminal keeps a tab open while any process is still attached to its console
		(see "The Workspace Tab Stays Open After [Closing current terminal tab]" in
		docs/winux/reference/troubleshooting.md).

		When no executable is given, or WMI refuses or throws, Start-Process runs with the
		-Fallback parameters instead and the process it starts shares this shell's console;
		without a fallback the function just returns $null. The reason goes to the debug log
		either way. Start-VSCodeDetached and Start-ObsidianDetached are the callers.

	.PARAMETER FilePath
		The executable to start, quoted into the command line as is. Empty when the caller could
		not resolve it, which goes straight to the fallback.

	.PARAMETER ArgumentList
		Arguments appended to the command line, separated by spaces, exactly as given - quote a
		value that contains spaces yourself ("`"$path`""), as with Start-Process -ArgumentList.

	.PARAMETER Fallback
		Start-Process parameters, splatted when the detached launch is not possible - typically
		the launch the caller used before it went detached. Start-Process errors propagate to
		the caller.

	.OUTPUTS
		[int] The process id of the detached process; $null when the fallback ran or nothing
		could be started.

	.EXAMPLE
		Start-ProcessDetached -FilePath "C:\Apps\Tool\Tool.exe" -ArgumentList "-n", "`"C:\My Project`"" -Fallback @{ FilePath = "tool"; ArgumentList = "-n", "`"C:\My Project`""; NoNewWindow = $true }
		Starts Tool.exe without a console, or through this shell's console when WMI cannot.
	#>
	[CmdletBinding()]
	[OutputType([int])]
	param (
		[Parameter()]
		[string]$FilePath,

		[Parameter()]
		[string[]]$ArgumentList,

		[Parameter()]
		[hashtable]$Fallback
	)

	$failure = $null
	if ([string]::IsNullOrWhiteSpace($FilePath)) {
		$failure = "No executable to launch detached"
	}
	else {
		$commandLine = "`"$FilePath`""
		if ($ArgumentList) {
			$commandLine += " " + ($ArgumentList -join " ")
		}

		try {
			$result = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $commandLine } -ErrorAction Stop
			if ($result.ReturnValue -eq 0) {
				Write-LogDebug " [Start-ProcessDetached] Launched detached => $commandLine (pid $($result.ProcessId))" -Style Success
				return [int]$result.ProcessId
			}
			$failure = "Win32_Process.Create returned $($result.ReturnValue) for [$FilePath]"
		}
		catch {
			$failure = "Win32_Process.Create threw for [$FilePath] => $($_.Exception.Message)"
		}
	}

	if ($Fallback) {
		Write-LogDebug " [Start-ProcessDetached] $failure - falling back to Start-Process (the process will share this shell's console)" -Style Warning
		Start-Process @Fallback
		return $null
	}

	Write-LogDebug " [Start-ProcessDetached] $failure" -Style Warning
	return $null
}
