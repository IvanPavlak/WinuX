function Update-DirectoryNames {
	<#
	.SYNOPSIS
		Updates dated directory names with the current date.

	.DESCRIPTION
		Scans directories in a given path for names containing a date suffix (YYYY_MM_DD).
		Replaces the date with today's date in the format YYYY_MM_DD.

	.PARAMETER Path
		Root directory to scan. Defaults to the current location.

	.PARAMETER WhatIf
		Shows what changes would be made without actually renaming directories.

	.EXAMPLE
		Update-DirectoryNames
		Updates all dated directories in the current location.

	.EXAMPLE
		Update-DirectoryNames -Path "C:\\My Folders" -WhatIf
		Shows what dated directories would be updated without making changes.
	#>
	param (
		[string]$Path = (Get-Location),
		[switch]$WhatIf
	)

	$currentDate = Get-Date -Format "yyyy_MM_dd"
	$dateChanged = $false

	$directories = Get-ChildItem -Path $Path -Directory

	foreach ($directory in $directories) {
		$parts = $directory.Name -split "_"

		$datePartCount = 3
		$nonDateParts = $parts.Count - $datePartCount

		if ($parts.Count -ge $datePartCount) {
			$year = $parts[$nonDateParts]
			$month = $parts[$nonDateParts + 1]
			$day = $parts[$nonDateParts + 2]

			$isValidDateFormat =
			$year -match '^\d{4}$' -and
			$month -match '^\d{2}$' -and
			$day -match '^\d{2}$' -and
			$day -ne $currentDate

			if ($isValidDateFormat) {
				$nonDateSegments = $parts[0..$([Math]::Max(0, $nonDateParts - 1))]
				$newName = (($nonDateSegments) -join "_") + "_" + $currentDate

				if ($newName -ne $directory.Name) {
					try {
						if ($WhatIf) {
							Write-LogWarning (" Would rename ""{0}"" -> ""{1}""" -f $directory.Name, $newName)
						}
						else {
							Rename-Item -Path $directory.FullName -NewName $newName -ErrorAction Stop
							Write-LogSuccess ("Renaming ""{0}"" -> ""{1}""" -f $directory.Name, $newName)
						}
						$dateChanged = $true
					}
					catch {
						Write-LogError ("Error renaming ""{0}"": {1}" -f $directory.Name, $_.Exception.Message)
					}
				}
				else {
					Write-LogStep ("  ""{0}"" is already up to date!" -f $directory.Name)
				}
			}
		}
	}

	if (-not $dateChanged) {
		Write-LogStep "  All directories are up to date!"
	}
}
