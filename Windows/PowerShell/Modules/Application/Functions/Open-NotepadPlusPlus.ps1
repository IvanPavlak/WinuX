function Open-NotepadPlusPlus {
	<#
	.SYNOPSIS
		Opens Notepad++, optionally with a specific file.

	.DESCRIPTION
		When called with a file path, resolves it (it must exist) and opens it in Notepad++
		(Universal.NotepadPlusPlusExe). If a Notepad++ window title already contains the file
		name, it warns that the file is already open and does not open a duplicate; the window
		is not brought to the front.

		When called without arguments, launches Notepad++ without a file through
		Start-Application -ConfigKey NotepadPlusPlusExe (a warning if it is already running).

	.PARAMETER File
		Path to the file to open. Omit to open Notepad++ without a file.

	.EXAMPLE
		Open-NotepadPlusPlus
		Opens Notepad++.

	.EXAMPLE
		Open-NotepadPlusPlus -File "C:\config.json"
		Opens config.json in Notepad++, or reports that it is already open.
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
			Start-Process -FilePath (Get-ConfigSetting -Path 'Universal.NotepadPlusPlusExe') -ArgumentList $resolvedPath -ErrorAction Stop
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
