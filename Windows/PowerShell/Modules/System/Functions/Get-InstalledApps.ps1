function Get-InstalledApps {
	<#
	.SYNOPSIS
		Enumerates all installed Windows applications from the registry.

	.DESCRIPTION
		Scans the Windows registry's Uninstall keys for all installed applications
		(both 64-bit and 32-bit) and outputs DisplayName, DisplayVersion, Publisher, InstallDate,
		UninstallString, Bits and the registry Path of each. Results are written to
		`installed_apps.txt` on the user's Desktop; an existing file there is cleared first.
		The local machine's registry is opened in its 64-bit view, so the plain Uninstall key holds
		the 64-bit applications and the Wow6432Node key the 32-bit ones. When nothing is found, a
		warning replaces the success message.

	.EXAMPLE
		Get-InstalledApps
		Enumerates all installed applications and saves to Desktop/installed_apps.txt.
	#>
	$NameRegex = ""

	$outputPath = "$env:USERPROFILE\Desktop\installed_apps.txt"

	if (Test-Path $outputPath) {
		Clear-Content $outputPath
	}

	# The 64-bit view, whatever the bitness of this shell: Wow6432Node is then the 32-bit hive.
	# OpenRemoteBaseKey against this machine's own name needed the Remote Registry service.
	$reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey("LocalMachine", "Registry64")
	$exportedCount = 0

	$keys = "", "\Wow6432Node"
	foreach ($key in $keys) {
		try {
			$apps = $reg.OpenSubKey("SOFTWARE$key\Microsoft\Windows\CurrentVersion\Uninstall").GetSubKeyNames()
		}
		catch {
			continue
		}
		foreach ($app in $apps) {
			$program = $reg.OpenSubKey("SOFTWARE$key\Microsoft\Windows\CurrentVersion\Uninstall\$app")
			if (-not $program) { continue }
			$name = $program.GetValue("DisplayName")
			if ($name -and $name -match $NameRegex) {
				$appInfo = [pscustomobject]@{
					DisplayName     = $name
					DisplayVersion  = $program.GetValue("DisplayVersion")
					Publisher       = $program.GetValue("Publisher")
					InstallDate     = $program.GetValue("InstallDate")
					UninstallString = $program.GetValue("UninstallString")
					Bits            = $(if ($key -eq "\Wow6432Node") { "32" } else { "64" })
					Path            = $program.name
				}

				$appInfo | Format-List | Out-String | Add-Content -Path $outputPath
				$exportedCount++
			}
		}
	}

	if ($exportedCount -eq 0) {
		Write-LogWarning "No installed apps were found in the registry - nothing exported to $outputPath"
		return
	}

	Write-LogSuccess "$exportedCount installed apps have been exported to $outputPath"
}
