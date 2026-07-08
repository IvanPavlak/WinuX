function Configure-NerdFont {
	<#
    .SYNOPSIS
        Installs and configures a Nerd Font.

    .DESCRIPTION
        Reads available Nerd Fonts from `NerdFonts` in Configuration.psd1. When called with
        a font name, installs that Nerd Font. When called without arguments, shows an
        interactive menu of available fonts.
        The default font is read from `DefaultNerdFont` in Configuration.psd1.
        Requires administrator privileges.

    .PARAMETER FontName
        Nerd Font name as defined in Configuration.psd1 (e.g. "JetBrainsMono").
        Omit to show the interactive menu.

    .EXAMPLE
        Configure-NerdFont
        Shows the Nerd Font selection menu.

    .EXAMPLE
        Configure-NerdFont -FontName "JetBrainsMono"
        Installs the JetBrainsMono Nerd Font.
    #>
	[CmdletBinding()]
	param(
		[Parameter(Mandatory = $false)]
		[string]$FontName
	)

	Test-AdminPrivileges

	$nerdFonts = $Configuration.NerdFonts
	$defaultFontName = $Configuration.DefaultNerdFont
	$targetFontName = ""

	if (-not [string]::IsNullOrWhiteSpace($FontName)) {
		if ($nerdFonts.ContainsKey($FontName)) {
			$targetFontName = $FontName
		}
		else {
			Write-LogError "Error: Nerd Font [$FontName] not found in configuration!"
			return
		}
	}
 else {
		$fontOptions = $nerdFonts.Keys
		$resolveParams = @{
			OptionList               = $fontOptions
			MenuTitle                = "[Available Nerd Fonts]"
			PromptMessage            = "Select a Nerd Font to configure (or press Enter for default [$defaultFontName])"
			AllowEmptyPromptResponse = $true
		}

		$selectedFontName = Resolve-Selection @resolveParams

		if ([string]::IsNullOrWhiteSpace($selectedFontName)) {
			$targetFontName = $defaultFontName
		}
		else {
			$targetFontName = $selectedFontName
		}
	}

	$fontConfig = $nerdFonts[$targetFontName]
	$fontSearchPattern = $fontConfig.SearchPattern
	$fontFolderName = $fontConfig.FolderName

	Write-LogTitle "Configuring $($targetFontName) Nerd Font"

	$existingFonts = Get-ChildItem -Path $Configuration.Universal.Fonts -ErrorAction SilentlyContinue |
		Where-Object { $_.Name -like "$($fontSearchPattern).ttf" -or $_.Name -like "$($fontSearchPattern).otf" }

	$registryFonts = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -ErrorAction SilentlyContinue |
		Get-Member -MemberType NoteProperty |
		Where-Object { $_.Name -like $fontSearchPattern }

	if ($existingFonts -and $registryFonts) {
		Write-LogWarning "$targetFontName Nerd Font is already configured in both filesystem and registry"
		return
	}

	$fontSourceFolder = Join-Path -Path $MachineSpecificPaths.Projects.Self.Root -ChildPath $fontFolderName
	if (-not (Test-Path $fontSourceFolder -PathType Container)) {
		Write-LogError "Font folder not found at $($fontSourceFolder)"
		return
	}

	try {
		$fontFiles = Get-ChildItem -Path $fontSourceFolder | Where-Object { $_.Extension -in ".ttf", ".otf" }
		if (-not $fontFiles) {
			Write-LogError "No font files found in the folder '$($fontFolderName)'"
			return
		}

		$Shell = New-Object -ComObject Shell.Application
		$FontsFolder = 0x14
		$Destination = $Shell.Namespace($FontsFolder)
		foreach ($fontFile in $fontFiles) {
			$destinationPath = Join-Path -Path $Configuration.Universal.Fonts -ChildPath $fontFile.Name

			if (Test-Path $destinationPath) {
				Write-LogWarning "Skipping existing font file: $($fontFile.Name)"
				continue
			}

			Copy-Item -Path $fontFile.FullName -Destination $destinationPath -Force

			$Destination.CopyHere($fontFile.FullName, 0x10)
			$fontType = if ($fontFile.Extension -eq ".ttf") { "(TrueType)" } else { "(OpenType)" }
			$fontRegistryName = "$($fontFile.BaseName) $fontType"

			$existingRegistryEntry = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name $fontRegistryName -ErrorAction SilentlyContinue
			if (-not $existingRegistryEntry) {
				Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" -Name $fontRegistryName -Value $fontFile.Name -Force
			}
		}

		Write-LogSuccess "$($targetFontName) Nerd Font installation completed"
	}
	catch {
		Write-LogError "Error: $($_.Exception.Message)"
		Write-LogError "Stack trace: $($_.ScriptStackTrace)"
	}
}
