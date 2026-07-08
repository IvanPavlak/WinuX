function Create-CondaEnvironments {
	<#
	.SYNOPSIS
		Creates Conda environments from YAML files in the WinuX Conda/Environments folder.

	.DESCRIPTION
		Idempotently creates Conda environments by checking if each environment already exists
		before attempting to create it. Uses environment YAML files from the configured
		CondaEnvironments folder path.

	.EXAMPLE
		Create-CondaEnvironments
		Creates all missing Conda environments from the YAML files.

	.NOTES
		Requires Miniconda3 to be installed (via Install-WinGetApps.ps1: Anaconda.Miniconda3).
		Environment folder is configured in Configuration.psd1 under BootstrapConfig.DataFiles.CondaEnvironments.
	#>

	Write-LogTitle "Creating Conda Environments"

	$condaPath = $env:Conda
	if (-not $condaPath) {
		Write-LogError " Conda environment variable not set!"
		Write-LogWarning "Ensure the [Conda] environment variable is configured!"
		return
	}

	$condaExe = Join-Path -Path $condaPath -ChildPath "Scripts\conda.exe"

	if (-not (Test-Path $condaExe)) {
		Write-LogError " Conda executable not found => [$condaExe]"
		Write-LogWarning "Ensure Miniconda3 is installed (Anaconda.Miniconda3 via WinGet)!"
		return
	}

	Write-LogTitle "Updating Conda" -BlankLineAfter
	& $condaExe update -n base -c defaults conda -y

	$condaEnvFolder = Join-Path -Path $MachineSpecificPaths.Projects.Self.Root -ChildPath $global:Configuration.BootstrapConfig.DataFiles.CondaEnvironments

	if (-not (Test-Path $condaEnvFolder)) {
		Write-LogError " Conda environments folder not found => [$condaEnvFolder]"
		return
	}

	$envFiles = Get-ChildItem -Path $condaEnvFolder -Filter "*.yml" -File

	if ($envFiles.Count -eq 0) {
		Write-LogWarning "No .yml environment files found in => [$condaEnvFolder]"
		return
	}

	$existingEnvs = @()
	try {
		$condaInfo = & $condaExe env list 2>&1
		$existingEnvs = $condaInfo | ForEach-Object {
			if ($_ -match "^(\S+)\s+") {
				$matches[1]
			}
		} | Where-Object { $_ -and $_ -ne "#" }
	}
 catch {
		Write-LogWarning "Could not retrieve existing Conda environments. Will attempt to create all!"
	}

	foreach ($envFile in $envFiles) {
		$envName = [System.IO.Path]::GetFileNameWithoutExtension($envFile.Name)

		Write-LogTitle "$envName"

		if ($existingEnvs -contains $envName) {
			Write-LogWarning "$envName environment already exists!"
			continue
		}

		Write-LogStep " Creating environment from [$($envFile.Name)]..."

		try {
			& $condaExe env create -f $envFile.FullName

			if ($LASTEXITCODE -eq 0) {
				Write-LogSuccess " Successfully created environment => [$envName]"
			}
			else {
				Write-LogError " Failed to create environment => [$envName]"
			}
		}
		catch {
			Write-LogError " Error creating environment => $_"
		}
	}

	Write-LogSuccess " Conda environments created successfully!"
}
