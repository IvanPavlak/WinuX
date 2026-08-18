function Write-ManualInstructionsToDesktop {
	<#
    .SYNOPSIS
        Write formatted instructions to a file on user's Desktop.

    .DESCRIPTION
        Creates a text file with title, separator, and content for manual setup steps.
        Useful for saving complex instructions when automation isn't feasible.

    .PARAMETER FileName
        Filename for desktop file (e.g., 'setup-instructions.txt').

    .PARAMETER Title
        Document title, displayed at top with separator line.

    .PARAMETER Content
        Main body content with instructions.

    .EXAMPLE
        Write-ManualInstructionsToDesktop -FileName "VPN-Setup.txt" -Title "VPN Configuration" -Content "1. Download VPN client...\n2. Install and configure..."
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $true)]
		[string]$FileName,

		[Parameter(Mandatory = $true)]
		[string]$Title,

		[Parameter(Mandatory = $true)]
		[string]$Content
	)

	# GetFolderPath VERIFIES the folder by default and returns an EMPTY STRING when that
	# check does not succeed (e.g. service/CI profiles without a Desktop), which Join-Path
	# rejects outright. DoNotVerify answers from the known-folder registration without
	# touching the disk; the profile path is the last resort.
	$desktopPath = [Environment]::GetFolderPath("Desktop")
	if ([string]::IsNullOrWhiteSpace($desktopPath)) {
		$desktopPath = [Environment]::GetFolderPath("Desktop", "DoNotVerify")
	}
	if ([string]::IsNullOrWhiteSpace($desktopPath)) {
		$desktopPath = Join-Path $env:USERPROFILE "Desktop"
	}
	$filePath = Join-Path $desktopPath $FileName

	$separator = "=" * $Title.Length

	$document = @"
$Title
$separator

$Content

Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@

	$document | Out-File -FilePath $filePath -Encoding UTF8 -Force
	Write-LogSuccess "Manual instructions written to [$filePath]"
}
