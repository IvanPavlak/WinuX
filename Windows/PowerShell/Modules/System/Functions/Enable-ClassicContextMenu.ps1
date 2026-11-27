function Enable-ClassicContextMenu {
	<#
	.SYNOPSIS
		Makes right click open the classic context menu on Windows 11.

	.DESCRIPTION
		Windows 11 opens a shortened context menu and keeps the full one behind
		"Show more options". Explorer builds the shortened menu from COM classes; an empty
		per-user `InprocServer32` override of such a class makes it fail to load, and Explorer
		falls back to the classic menu.

		Two classes are overridden under `HKCU:\Software\Classes\CLSID`: the one every
		Windows 11 release has, and the one newer builds draw their redesigned menu with (the
		first override alone does nothing there). A class the machine does not register is left
		alone, so an older build gets one override and Windows 10 gets none.

		Only the current user's hive is written, so no administrator privileges are needed.
		Explorer reads the overrides on startup, so Restart-Explorer runs when at least one was
		written. Safe to re-run: overrides already in place are left as they are.

		To get the Windows 11 menu back, delete the two keys under
		`HKCU:\Software\Classes\CLSID` and restart Explorer.

	.EXAMPLE
		Enable-ClassicContextMenu
		Writes the missing overrides and restarts Explorer.
	#>
	Write-LogTitle "Enabling Classic Context Menu"

	# The shortened menu, then the redesigned one of newer builds.
	$classIds = @(
		'{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}',
		'{51668040-5e31-4023-bbe3-149163bd80f1}'
	)

	$registeredClassIds = @($classIds | Where-Object { Test-Path -LiteralPath "HKLM:\SOFTWARE\Classes\CLSID\$_" })

	if ($registeredClassIds.Count -eq 0) {
		Write-LogWarning "This Windows version has no Windows 11 context menu - nothing to change"
		return
	}

	$overrideWritten = $false

	foreach ($classId in $registeredClassIds) {
		$overridePath = "HKCU:\Software\Classes\CLSID\$classId\InprocServer32"

		# The override is the key's default value set to an empty string; a key without a
		# default value reads as $null and does not count.
		$overrideKey = Get-Item -LiteralPath $overridePath -ErrorAction SilentlyContinue
		if ($overrideKey -and $overrideKey.GetValue('') -eq '') {
			continue
		}

		try {
			New-Item -Path $overridePath -Value '' -Force -ErrorAction Stop | Out-Null
			$overrideWritten = $true
		}
		catch {
			Write-LogError "Failed to override context menu class $classId`: $($_.Exception.Message)"
		}
	}

	if (-not $overrideWritten) {
		Write-LogWarning "Classic context menu already enabled"
		return
	}

	Restart-Explorer

	Write-LogSuccess "Classic context menu enabled"
}
