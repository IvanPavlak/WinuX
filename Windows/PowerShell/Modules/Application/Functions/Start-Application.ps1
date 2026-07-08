function Start-Application {
	<#
    .SYNOPSIS
        Common function to start applications with standardized error handling and process checking.

    .DESCRIPTION
        Provides a DRY (Don't Repeat Yourself) implementation for starting applications with
        common patterns: process checking, error handling, and user feedback.

        Applications start non-blocking by default since Start-Process is inherently async.
        Use -Sync with -Wait behavior when you need to wait for an application to exit.

    .PARAMETER AppName
        Display name of the application (used in messages).

    .PARAMETER ProcessName
        Process name to check if the application is already running.

    .PARAMETER StartMethod
        Method to start the application:
        - ConfigPath: Uses $Configuration.Universal.[ConfigKey]
        - AppxPackage: Uses Get-AppxPackage to find and start UWP apps
        - DirectPath: Uses a direct file path
        - Custom: Uses a custom scriptblock for complex scenarios

    .PARAMETER ConfigKey
        Configuration key for ConfigPath method (e.g., 'VirtualBoxExe').

    .PARAMETER PackageName
        Package name pattern for AppxPackage method (e.g., 'Microsoft.Outlook').

    .PARAMETER ExecutableName
        Executable name within package for AppxPackage method (e.g., 'olk.exe').

    .PARAMETER ExecutablePath
        Direct path to executable for DirectPath method.

    .PARAMETER Arguments
        Optional arguments to pass to Start-Process.

    .PARAMETER NoNewWindow
        Pass -NoNewWindow to Start-Process.

    .PARAMETER SkipProcessCheck
        Skip checking if the process is already running.

    .PARAMETER ProcessPathFilter
        Wildcard pattern that scopes the "already running" check to processes launched from a
        specific location. When set, only processes whose executable path matches this pattern
        count as running. Useful when several apps share a process name (e.g. Claude Desktop and
        the Claude Code CLI both run as "claude"), so launching one is not blocked by the other.

    .PARAMETER Sync
        Wait for the process to exit before returning (uses -Wait on Start-Process).

    .PARAMETER SuppressOutput
        Redirect stdout and stderr to NUL, suppressing all console output from the launched process.
        Useful for applications like Docker Desktop (Electron) that dump verbose output to the parent console.

    .PARAMETER CustomStartLogic
        Scriptblock for Custom start method.

    .EXAMPLE
        Start-Application -AppName "VirtualBox" -ProcessName "VirtualBox" -StartMethod ConfigPath -ConfigKey "VirtualBoxExe" -NoNewWindow
        # Starts VirtualBox (non-blocking by default)

    .EXAMPLE
        Start-Application -AppName "Outlook" -ProcessName "Outlook" -StartMethod AppxPackage -PackageName "Microsoft.Outlook" -ExecutableName "olk.exe"
        # Starts Outlook UWP app (non-blocking by default)

    .EXAMPLE
        Start-Application -AppName "Docker" -ProcessName "Docker Desktop" -StartMethod DirectPath -ExecutablePath $dockerExe -Sync
        # Starts Docker and waits for the process to exit
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$AppName,

		[Parameter(Mandatory)]
		[string]$ProcessName,

		[Parameter(Mandatory)]
		[ValidateSet('ConfigPath', 'AppxPackage', 'DirectPath', 'Custom')]
		[string]$StartMethod,

		[Parameter()]
		[string]$ConfigKey,

		[Parameter()]
		[string]$PackageName,

		[Parameter()]
		[string]$ExecutableName,

		[Parameter()]
		[string]$ExecutablePath,

		[Parameter()]
		[string[]]$Arguments,

		[Parameter()]
		[switch]$NoNewWindow,

		[Parameter()]
		[switch]$SkipProcessCheck,

		[Parameter()]
		[string]$ProcessPathFilter,

		[Parameter()]
		[switch]$SkipPathValidation,

		[Parameter()]
		[switch]$Sync,

		[Parameter()]
		[switch]$SuppressOutput,

		[Parameter()]
		[scriptblock]$CustomStartLogic
	)

	Write-LogStep "Opening $AppName..."

	if (-not $SkipProcessCheck) {
		$runningProcesses = [System.Diagnostics.Process]::GetProcessesByName($ProcessName)

		if ($ProcessPathFilter) {
			$runningProcesses = $runningProcesses | Where-Object {
				try { $_.Path -like $ProcessPathFilter } catch { $false }
			}
		}

		if (@($runningProcesses).Count -gt 0) {
			Write-LogWarning "$AppName is already running!"
			return
		}
	}

	try {
		switch ($StartMethod) {
			'ConfigPath' {
				if ([string]::IsNullOrWhiteSpace($ConfigKey)) {
					throw "ConfigKey parameter is required for ConfigPath method"
				}

				$exePath = $Configuration.Universal.$ConfigKey
				if ([string]::IsNullOrWhiteSpace($exePath)) {
					throw "$ConfigKey not found in configuration!"
				}

				$startParams = @{
					FilePath    = $exePath
					ErrorAction = 'Stop'
				}
				if ($NoNewWindow) { $startParams['NoNewWindow'] = $true }
				if ($Arguments) { $startParams['ArgumentList'] = $Arguments }
				if ($Sync) { $startParams['Wait'] = $true }
				if ($SuppressOutput) {
					$startParams['RedirectStandardOutput'] = [System.IO.Path]::GetTempFileName()
					$startParams['RedirectStandardError'] = [System.IO.Path]::GetTempFileName()
					if (-not $startParams.ContainsKey('NoNewWindow')) {
						$startParams['NoNewWindow'] = $true
					}
				}

				Start-Process @startParams
			}

			'AppxPackage' {
				if ([string]::IsNullOrWhiteSpace($PackageName)) {
					throw "PackageName parameter is required for AppxPackage method"
				}
				if ([string]::IsNullOrWhiteSpace($ExecutableName)) {
					throw "ExecutableName parameter is required for AppxPackage method"
				}

				$package = Get-AppxPackage "*$PackageName*" -ErrorAction Stop | Select-Object -First 1

				if (-not $package) {
					throw "$AppName is not installed!"
				}

				$appPath = Join-Path $package.InstallLocation $ExecutableName

				if (-not (Test-Path $appPath)) {
					throw "$ExecutableName not found at expected location"
				}

				$startParams = @{
					FilePath    = $appPath
					ErrorAction = 'Stop'
				}
				if ($Arguments) { $startParams['ArgumentList'] = $Arguments }
				if ($Sync) { $startParams['Wait'] = $true }
				if ($SuppressOutput) {
					$startParams['RedirectStandardOutput'] = [System.IO.Path]::GetTempFileName()
					$startParams['RedirectStandardError'] = [System.IO.Path]::GetTempFileName()
					if (-not $startParams.ContainsKey('NoNewWindow')) {
						$startParams['NoNewWindow'] = $true
					}
				}

				Start-Process @startParams
			}

			'DirectPath' {
				if ([string]::IsNullOrWhiteSpace($ExecutablePath)) {
					throw "ExecutablePath parameter is required for DirectPath method"
				}

				if (-not $SkipPathValidation -and -not (Test-Path $ExecutablePath)) {
					throw "$AppName not found at expected location: $ExecutablePath"
				}

				$startParams = @{
					FilePath    = $ExecutablePath
					ErrorAction = 'Stop'
				}
				if ($NoNewWindow) { $startParams['NoNewWindow'] = $true }
				if ($Arguments) { $startParams['ArgumentList'] = $Arguments }
				if ($Sync) { $startParams['Wait'] = $true }
				if ($SuppressOutput) {
					$startParams['RedirectStandardOutput'] = [System.IO.Path]::GetTempFileName()
					$startParams['RedirectStandardError'] = [System.IO.Path]::GetTempFileName()
					if (-not $startParams.ContainsKey('NoNewWindow')) {
						$startParams['NoNewWindow'] = $true
					}
				}

				Start-Process @startParams
			}

			'Custom' {
				if (-not $CustomStartLogic) {
					throw "CustomStartLogic scriptblock is required when using Custom start method"
				}
				& $CustomStartLogic
			}
		}

		Write-LogSuccess "$AppName opened!"
	}
	catch {
		Write-LogError "Failed to open $AppName => $_"
	}
}
