function Get-WindowTitleCandidates {
	<#
	.SYNOPSIS
		Generate window title matching candidates from file paths.

	.DESCRIPTION
		Creates multiple title variations from file names/paths for robust window matching.
		Generates full path, filename, and filename-without-extension candidates.

	.PARAMETER Names
		Array of file paths or names to generate candidates from.

	.EXAMPLE
		$candidates = Get-WindowTitleCandidates -Names "C:\path\to\file.txt", "other.ps1"
		# Returns: ["C:\path\to\file.txt", "file.txt", "file", "other.ps1", "other"]
	#>
	[CmdletBinding()]
	param(
		[Parameter()]
		[string[]]$Names
	)

	$candidates = [System.Collections.Generic.List[string]]::new()

	foreach ($name in $Names) {
		if ([string]::IsNullOrWhiteSpace($name)) {
			continue
		}

		$trimmedName = $name.Trim()
		if (-not $candidates.Contains($trimmedName)) {
			$candidates.Add($trimmedName)
		}

		$fileName = [System.IO.Path]::GetFileName($trimmedName)
		if (-not [string]::IsNullOrWhiteSpace($fileName) -and -not $candidates.Contains($fileName)) {
			$candidates.Add($fileName)
		}

		$fileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($trimmedName)
		if (-not [string]::IsNullOrWhiteSpace($fileNameWithoutExtension) -and -not $candidates.Contains($fileNameWithoutExtension)) {
			$candidates.Add($fileNameWithoutExtension)
		}
	}

	return @($candidates)
}
