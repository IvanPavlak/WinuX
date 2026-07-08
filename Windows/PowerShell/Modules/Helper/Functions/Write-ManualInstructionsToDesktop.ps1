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

	$desktopPath = [Environment]::GetFolderPath("Desktop")
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
