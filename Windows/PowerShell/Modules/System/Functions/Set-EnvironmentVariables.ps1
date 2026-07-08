function Set-EnvironmentVariables {
	<#
    .SYNOPSIS
        Sets system environment variables from the configuration or manually.

    .DESCRIPTION
        With `-Auto`, reads all variables from `AutoEnvironmentVariables` in Configuration.psd1,
        expands placeholder paths, and sets them as system environment variables.
        Manual mode accepts `-Name` and `-Value` to set an individual variable.
        Requires administrator privileges.

    .PARAMETER Name
        Variable name for manual mode (e.g. "MY_VAR").

    .PARAMETER Value
        Variable value for manual mode (e.g. "C:\\Tools").

    .PARAMETER Auto
        Reads all variables from configuration and sets them automatically.

    .EXAMPLE
        Set-EnvironmentVariables -Auto
        Sets all configured environment variables.

    .EXAMPLE
        Set-EnvironmentVariables -Name "MY_VAR" -Value "C:\\Tools"
        Sets a single environment variable.
    #>
	param(
		[Parameter(Mandatory = $false)]
		[string]$Name,

		[Parameter(Mandatory = $false)]
		[string]$Value,

		[Parameter(Mandatory = $false)]
		[switch]$Auto
	)

	Test-AdminPrivileges

	Write-LogTitle "Setting System Environment Variables"

	if ($Auto) {
		$autoVariables = $Configuration.AutoEnvironmentVariables

		if (-not $autoVariables -or $autoVariables.Count -eq 0) {
			Write-LogWarning "No automatic environment variables are defined in the configuration!"
			return
		}

		$basePath = $global:Configuration.BasePaths[$global:MachineType].Dev
		$userPath = $global:Configuration.BasePaths[$global:MachineType].User

		$updated = $false
		foreach ($variable in $autoVariables.GetEnumerator()) {
			$varName = $variable.Key
			$varValue = $variable.Value

			$varValue = Expand-Hashtable -Source $varValue -DevPath $basePath -UserPath $userPath -MachineTypeName $global:MachineType

			$currentValue = [Environment]::GetEnvironmentVariable($varName, "User")

			if ($currentValue) {
				if ($currentValue -eq $varValue) {
					Write-LogWarning "Environment variable [$varName] already exists with correct value: [$currentValue]"
				}
				else {
					Write-LogWarning "Environment variable [$varName] exists with different value: [$currentValue]"
					Write-LogSuccess "Updating to new value: [$varValue]"
					[Environment]::SetEnvironmentVariable($varName, $varValue, "User")
					Set-Item -Path "env:$varName" -Value $varValue
					$updated = $true
				}
			}
			else {
				[Environment]::SetEnvironmentVariable($varName, $varValue, "User")
				Set-Item -Path "env:$varName" -Value $varValue
				Write-LogSuccess "Environment variable [$varName] set to [$varValue]"
				$updated = $true
			}
		}
		if ($updated) {
			Write-LogSuccess "Environment variables setup completed"
		}

		# Process AutoPathAdditions
		$autoPathAdditions = $Configuration.AutoPathAdditions
		if ($autoPathAdditions -and $autoPathAdditions.Count -gt 0) {
			$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
			$pathEntries = $currentPath -split ";" | Where-Object { $_ -ne "" }
			$pathUpdated = $false

			foreach ($entry in $autoPathAdditions) {
				$expandedEntry = Expand-Hashtable -Source $entry -DevPath $basePath -UserPath $userPath -MachineTypeName $global:MachineType

				if ($pathEntries -contains $expandedEntry) {
					Write-LogWarning "PATH entry already present: [$expandedEntry]"
				}
				else {
					$pathEntries += $expandedEntry
					Write-LogSuccess "Added to User PATH: [$expandedEntry]"
					$pathUpdated = $true
				}
			}

			if ($pathUpdated) {
				$newPath = $pathEntries -join ";"
				[Environment]::SetEnvironmentVariable("Path", $newPath, "User")
				$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + $newPath
				Write-LogSuccess "PATH updated"
			}
		}
	}
	else {
		if (-not $Name -or -not $Value) {
			Write-LogWarning "Provide both [-Name] and [-Value] parameters or use the [-Auto] flag!" -BlankLineAfter
			return
		}

		$basePath = $global:Configuration.BasePaths[$global:MachineType].Dev
		$userPath = $global:Configuration.BasePaths[$global:MachineType].User

		$Value = Expand-Hashtable -Source $Value -DevPath $basePath -UserPath $userPath -MachineTypeName $global:MachineType

		$currentValue = [Environment]::GetEnvironmentVariable($Name, "User")

		if ($currentValue) {
			if ($currentValue -eq $Value) {
				Write-LogWarning "Environment variable [$Name] already exists with correct value: [$currentValue]" -BlankLineAfter
			}
			else {
				Write-LogWarning "Environment variable [$Name] exists with different value: [$currentValue]"
				Write-LogSuccess "Updating to new value: [$Value]"
				[Environment]::SetEnvironmentVariable($Name, $Value, "User")
				Set-Item -Path "env:$Name" -Value $Value
				Write-LogSuccess "Environment variables setup completed"
			}
		}
		else {
			[Environment]::SetEnvironmentVariable($Name, $Value, "User")
			Set-Item -Path "env:$Name" -Value $Value
			Write-LogSuccess "Environment variable [$Name] set to [$Value]" -BlankLineAfter
			Write-LogSuccess "Environment variables setup completed"
		}
	}

	[System.Environment]::GetEnvironmentVariables("User").GetEnumerator() | ForEach-Object {
		Set-Item -Path "env:$($_.Key)" -Value $_.Value
	}
}
