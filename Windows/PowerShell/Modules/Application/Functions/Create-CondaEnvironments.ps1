function Create-CondaEnvironments {
	<#
	.SYNOPSIS
		Creates Conda environments from YAML files in the WinuX Conda/Environments folder.

	.DESCRIPTION
		Creates the Conda environments of the configured CondaEnvironments folder, one per *.yml
		file, named after the file (conda env create -n <Name> -f <file>). An environment that
		already exists is left alone unless -Recreate is given, which removes it first
		(conda env remove -n <Name> -y) and creates it again from its file.

		Without -Name every file in the folder is processed; with -Name only the named ones are.
		A name without a file is reported as an error and the other names still run.

		With CondaUpdateBase on (off in the base configuration) a run without -Name first updates
		conda in the base environment (conda update -n base -c defaults conda -y). A run with
		-Name never does, so creating one environment stays quick.

		-List shows each environment and whether it exists, -DryRun prints the conda commands;
		neither changes anything. The Foundation twin is Install-CondaEnvironments.

	.PARAMETER Name
		The environments to process, by file name without .yml (a trailing .yml is accepted).
		Several names may be given, separated by spaces or commas. Omitted: every file in the folder.

	.PARAMETER Recreate
		Removes an environment that already exists and creates it again from its file.

	.PARAMETER List
		Lists each environment as exists or missing and changes nothing.

	.PARAMETER DryRun
		Prints the conda commands a run would make and changes nothing.

	.EXAMPLE
		Create-CondaEnvironments
		Creates every missing Conda environment from the YAML files.

	.EXAMPLE
		Create-CondaEnvironments MyEnvironment
		Creates only the MyEnvironment environment, when it is missing.

	.EXAMPLE
		Create-CondaEnvironments MyEnvironment -Recreate
		Removes the MyEnvironment environment and creates it again from MyEnvironment.yml.

	.EXAMPLE
		Create-CondaEnvironments -List
		Shows which environments exist and which are missing.

	.NOTES
		Requires Miniconda3 to be installed and the Conda user environment variable to point at it
		(AutoEnvironmentVariables.Conda, written by Set-EnvironmentVariables -Auto); without the
		variable the function warns and returns. conda.exe is expected at <Conda>\Scripts\conda.exe.
		Environment folder is configured in Configuration.psd1 under BootstrapConfig.DataFiles.CondaEnvironments,
		relative to the repository root (Projects.Self.Root). CondaUpdateBase turns the base update on.
	#>
	[CmdletBinding()]
	param(
		[Parameter(Position = 0, ValueFromRemainingArguments = $true)]
		[string[]]$Name,

		[Parameter()]
		[switch]$Recreate,

		[Parameter()]
		[switch]$List,

		[Parameter()]
		[switch]$DryRun
	)

	Write-LogTitle "Creating Conda Environments"

	$condaPath = $env:Conda
	if (-not (Confirm-ConfigValue $condaPath "Conda environment variable not set (opt in via AutoEnvironmentVariables.Conda) - skipping Conda environments!")) {
		return
	}

	$condaExe = Join-Path -Path $condaPath -ChildPath "Scripts\conda.exe"

	if (-not (Test-Path $condaExe)) {
		Write-LogError " Conda executable not found => [$condaExe]"
		Write-LogWarning "Ensure Miniconda3 is installed (Anaconda.Miniconda3 via WinGet)!"
		return
	}

	$condaEnvFolder = Join-Path -Path $MachineSpecificPaths.Projects.Self.Root -ChildPath (Get-ConfigSetting -Path 'BootstrapConfig.DataFiles.CondaEnvironments')

	if (-not (Test-Path $condaEnvFolder)) {
		Write-LogError " Conda environments folder not found => [$condaEnvFolder]"
		return
	}

	$envFiles = @(Get-ChildItem -Path $condaEnvFolder -Filter "*.yml" -File)

	if ($envFiles.Count -eq 0) {
		Write-LogWarning "No .yml environment files found in => [$condaEnvFolder]"
		return
	}

	# Which files to process: every one, or the -Name ones (any case, a trailing .yml dropped).
	$failures = 0
	$selectedFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
	$requestedNames = @($Name | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() -replace '\.yml$', '' } | Where-Object { $_ })

	if ($requestedNames.Count -eq 0) {
		$envFiles | ForEach-Object { $selectedFiles.Add($_) }
	}
	else {
		foreach ($requestedName in $requestedNames) {
			$match = $envFiles | Where-Object { $_.BaseName -eq $requestedName } | Select-Object -First 1
			if (-not $match) {
				Write-LogError " No environment file for [$requestedName] in => [$condaEnvFolder]"
				$failures++
				continue
			}
			if (-not ($selectedFiles | Where-Object { $_.FullName -eq $match.FullName })) {
				$selectedFiles.Add($match)
			}
		}
		if ($selectedFiles.Count -eq 0) {
			return
		}
	}

	$existingEnvs = @()
	try {
		$condaInfo = & $condaExe env list 2>&1
		$existingEnvs = @($condaInfo | ForEach-Object {
				if ("$_" -match "^(\S+)\s+") {
					$matches[1]
				}
			} | Where-Object { $_ -and $_ -ne "#" })
	}
	catch {
		Write-LogWarning "Could not retrieve existing Conda environments. Will attempt to create all!"
	}

	if ($List) {
		Write-LogStep " Environment files in [$condaEnvFolder]"
		foreach ($envFile in $selectedFiles) {
			$state = if ($existingEnvs -contains $envFile.BaseName) { "exists" } else { "missing" }
			Write-Host ("  {0,-24} {1}" -f $envFile.BaseName, $state)
		}
		return
	}

	# The base update runs only on a run over every environment, and only when configured.
	if ($requestedNames.Count -eq 0 -and (Get-ConfigSetting -Path 'CondaUpdateBase' -Default $false) -eq $true) {
		if ($DryRun) {
			Write-Host "  conda update -n base -c defaults conda -y"
		}
		else {
			Write-LogTitle "Updating Conda" -BlankLineAfter
			& $condaExe update -n base -c defaults conda -y
			if ($LASTEXITCODE -ne 0) {
				Write-LogWarning "conda update of the base environment failed!"
				$failures++
			}
		}
	}

	$changed = 0
	foreach ($envFile in $selectedFiles) {
		$envName = $envFile.BaseName

		if (-not $DryRun) {
			Write-LogTitle "$envName"
		}

		$exists = $existingEnvs -contains $envName
		if ($exists -and -not $Recreate) {
			if (-not $DryRun) {
				Write-LogWarning "$envName environment already exists (-Recreate rebuilds it)!"
			}
			continue
		}

		$changed++

		if ($DryRun) {
			if ($exists) {
				Write-Host "  conda env remove -n $envName -y"
			}
			Write-Host "  conda env create -n $envName -f $($envFile.FullName)"
			continue
		}

		if ($exists) {
			Write-LogStep " Removing environment [$envName]..."
			& $condaExe env remove -n $envName -y
			if ($LASTEXITCODE -ne 0) {
				Write-LogError " Failed to remove environment => [$envName]"
				$failures++
				continue
			}
		}

		Write-LogStep " Creating environment from [$($envFile.Name)]..."
		& $condaExe env create -n $envName -f $envFile.FullName

		if ($LASTEXITCODE -eq 0) {
			Write-LogSuccess " Successfully created environment => [$envName]"
		}
		else {
			Write-LogError " Failed to create environment => [$envName]"
			$failures++
		}
	}

	if ($failures -gt 0) {
		Write-LogError " Conda environments done with $failures failure(s)!"
	}
	elseif ($changed -eq 0) {
		Write-LogSuccess " Every Conda environment already exists!"
	}
	elseif (-not $DryRun) {
		Write-LogSuccess " Conda environments created successfully!"
	}
}
