function Get-InstalledApps {
	<#
	.SYNOPSIS
		Retrievesenumerates all installed Windows applications from the registry.

	.DESCRIPTION
		Scans the Windows registry for all installed applications
		(both 64-bit and 32-bit) and outputs a list with DisplayName, Version, and UninstallString.
		Results are written to `installed_apps.txt` on the user's Desktop.

	.EXAMPLE
		Get-InstalledApps
		Enumerates all installed applications and saves to Desktop/installed_apps.txt.
	#>
	$NameRegex = ""

	$outputPath = "$env:USERPROFILE\Desktop\installed_apps.txt"

	if (Test-Path $outputPath) {
		Clear-Content $outputPath
	}

	foreach ($comp in $Hostname) {
		$keys = "", "\Wow6432Node"
		foreach ($key in $keys) {
			try {
				$reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine", $comp)
				$apps = $reg.OpenSubKey("SOFTWARE$key\Microsoft\Windows\CurrentVersion\Uninstall").GetSubKeyNames()
			}
			catch {
				continue
			}
			foreach ($app in $apps) {
				$program = $reg.OpenSubKey("SOFTWARE$key\Microsoft\Windows\CurrentVersion\Uninstall\$app")
				$name = $program.GetValue("DisplayName")
				if ($name -and $name -match $NameRegex) {
					$appInfo = [pscustomobject]@{
						DisplayName     = $name
						DisplayVersion  = $program.GetValue("DisplayVersion")
						Publisher       = $program.GetValue("Publisher")
						InstallDate     = $program.GetValue("InstallDate")
						UninstallString = $program.GetValue("UninstallString")
						Bits            = $(if ($key -eq "\Wow6432Node") { "64" } else { "32" })
						Path            = $program.name
					}

					$appInfo | Format-List | Out-String | Add-Content -Path $outputPath
				}
			}
		}
	}

	Write-LogSuccess "Installed apps have been exported to $outputPath"
}
