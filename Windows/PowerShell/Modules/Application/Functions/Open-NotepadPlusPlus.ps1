function Open-NotepadPlusPlus {
	<#
	.SYNOPSIS
		Opens Notepad++, optionally with a specific file.

	.DESCRIPTION
		When called with a file path, opens that file in Notepad++. If the file is already
		open in an existing Notepad++ window, focuses that window instead of opening a duplicate.

		When called without arguments, opens Notepad++ without any file.

	.PARAMETER File
		Path to the file to open. Omit to open Notepad++ without a file.

	.EXAMPLE
		Open-NotepadPlusPlus
		Opens Notepad++.

	.EXAMPLE
		Open-NotepadPlusPlus -File "C:\config.json"
		Opens config.json in Notepad++, or focuses the existing window if already open.
	#>
	param(
		[Parameter(Position = 0)]
		[string]$File
	)

	if ($File) {
		try {
			$resolvedPath = Resolve-Path -Path $File -ErrorAction Stop
			$fileName = Split-Path -Leaf $resolvedPath

			$nppWindows = Get-WindowHandle -ProcessName "notepad++" -ErrorAction SilentlyContinue

			foreach ($window in $nppWindows) {
				if ($window.Title -match "(?i)$([regex]::Escape($fileName))") {
					Write-LogWarning "File [$fileName] is already open in Notepad++!"
					return
				}
			}

			Write-LogStep "Opening [$File] in Notepad++..."
			Start-Process -FilePath $Configuration.Universal.NotepadPlusPlusExe -ArgumentList $resolvedPath -ErrorAction Stop
			Write-LogSuccess "File opened in Notepad++!"
		}
		catch {
			Write-LogError "Error: $($_.Exception.Message)" -BlankLineAfter
		}
	}
	else {
		Start-Application `
			-AppName "Notepad++" `
			-ProcessName "notepad++" `
			-StartMethod ConfigPath `
			-ConfigKey "NotepadPlusPlusExe" `
			-NoNewWindow
	}
}
