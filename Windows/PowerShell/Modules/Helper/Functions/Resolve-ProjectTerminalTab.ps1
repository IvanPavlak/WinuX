function Resolve-ProjectTerminalTab {
	<#
	.SYNOPSIS
		Reads one ProjectTerminals path entry into the tab it describes.

	.DESCRIPTION
		A `ProjectTerminals` entry writes its tabs in `Paths`, and a tab there can take any of six
		shapes - a path key, the DEFAULT and WSL keywords, and three hashtable forms. Every consumer
		of that list has to read all six the same way, and until this function existed each consumer
		read them on its own: Open-ProjectTerminals knew all six, Run-Project knew two. That is the
		whole of the `rp` bug where a WSL tab's `/mnt/c/...` path reached `Set-Location`, which
		resolves a rooted path against the CURRENT DRIVE and sent the tab to `C:\mnt\c\...`.

		The shapes, and what each resolves to:

		  "PathKey"                            Kind "Path",    Path from Resolve-ProjectPath
		  "DEFAULT"                            Kind "Default", no path - the shell's own directory
		  "WSL"                                Kind "WSL",     no path - the distribution's home
		  @{ Key = "WSL"; Path = "/mnt/c/x" }  Kind "WSL",     that path, as WSL sees it
		  @{ Key = "Name"; Path = "C:\path" }  Kind "Path",    that path, verbatim
		  @{ Key = "Name" }                    Kind "Default", no path, custom title

		Kind is what a caller switches on, and it is deliberately not "does it have a path": a WSL
		path and a Windows path are both paths but reach a tab through entirely different machinery
		(`wsl.exe --cd` against the tab's commandline versus `Set-Location` inside pwsh), so the two
		must never fall into the same branch again.

		A WSL tab carries the configured DefaultWSLDistribution, and $null when it is unset - which
		callers read as "skip this tab", the same no-op every other WSL feature performs without it.
		Distribution is $null for every other kind.

		Title is always "<ProjectName>.<Key>", the tab title Open-Terminal pins with
		--suppressApplicationTitle and Close-ProjectTerminals matches on.

	.PARAMETER ProjectName
		The project the entry belongs to. Only used to build the tab title and to resolve a path key
		through Resolve-ProjectPath.

	.PARAMETER PathEntry
		One element of a ProjectTerminals mapping's `Paths` - a string key or a hashtable.

	.OUTPUTS
		[pscustomobject] with Key, Title, Kind ("Path", "Default" or "WSL"), Path and Distribution.

	.EXAMPLE
		Resolve-ProjectTerminalTab -ProjectName "MyProject" -PathEntry "Api"
		Returns Kind "Path" with the Api directory resolved out of PathTemplates.

	.EXAMPLE
		Resolve-ProjectTerminalTab -ProjectName "MyProject" -PathEntry @{ Key = "WSL"; Path = "/mnt/c/Dev/MyProject" }
		Returns Kind "WSL" with the path untranslated and the configured distribution.

	.EXAMPLE
		$tab = Resolve-ProjectTerminalTab -ProjectName $name -PathEntry $entry
		switch ($tab.Kind) {
			"WSL"     { Open-WSLTab -Distribution $tab.Distribution -Path $tab.Path -TabTitle $tab.Title }
			"Default" { Open-Terminal -Command "" -TabTitles $tab.Title }
			default   { Open-Terminal -Command "Set-Location -Path '$($tab.Path)'" -TabTitles $tab.Title }
		}
	#>
	[CmdletBinding()]
	[OutputType([pscustomobject])]
	param (
		[Parameter(Mandatory)]
		[string]$ProjectName,

		[Parameter(Mandatory)]
		$PathEntry
	)

	if ($PathEntry -is [System.Collections.IDictionary]) {
		$pathKey = [string]$PathEntry.Key
		$explicitPath = $PathEntry.Path
	}
	else {
		$pathKey = [string]$PathEntry
		$explicitPath = $null
	}

	$tab = [pscustomobject]@{
		Key          = $pathKey
		Title        = "$ProjectName.$pathKey"
		Kind         = "Path"
		Path         = $null
		Distribution = $null
	}

	if ($pathKey -eq "WSL") {
		# The path stays exactly as configured. It is a path in the distribution's own file system,
		# handed to `wsl --cd`, and translating it to a Windows path would break the one case it
		# exists for - a repository mounted at /mnt/c that WSL must enter as WSL, not as Windows.
		$distribution = Get-ConfigSetting -Path 'DefaultWSLDistribution'

		$tab.Kind = "WSL"
		$tab.Path = if (Test-ConfigValue $explicitPath) { [string]$explicitPath } else { $null }
		$tab.Distribution = if (Test-ConfigValue $distribution) { [string]$distribution } else { $null }

		return $tab
	}

	# DEFAULT, and a hashtable entry that names a tab without giving it a path, both mean the same
	# tab: the shell where Windows Terminal starts it, with no Set-Location in front.
	if ($pathKey -eq "DEFAULT" -or ($PathEntry -is [System.Collections.IDictionary] -and -not (Test-ConfigValue $explicitPath))) {
		$tab.Kind = "Default"
		return $tab
	}

	$tab.Path = if (Test-ConfigValue $explicitPath) {
		[string]$explicitPath
	}
	else {
		Resolve-ProjectPath -ProjectName $ProjectName -PathKey $pathKey
	}

	return $tab
}
