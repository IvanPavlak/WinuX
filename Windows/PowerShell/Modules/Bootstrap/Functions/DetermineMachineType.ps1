function DetermineMachineType {
	<#
	.SYNOPSIS
		Resolves the current machine type from hostname or interactively if the hostname is not mapped.

	.DESCRIPTION
		Looks up `$env:COMPUTERNAME` in the `HostnameToMachineType` table in Configuration.psd1.
		If the hostname is not found, prompts the user to select from the valid machine types
		(PC, Laptop, Work, Test) defined in `ValidMachineTypes`.

		Sets `$global:MachineType` and returns the resolved value.
		If `$global:MachineType` is already set and valid, returns it immediately without prompting.

	.EXAMPLE
		DetermineMachineType
		Returns the machine type string, e.g. "PC" or "Laptop".
	#>
	$Hostname = $env:COMPUTERNAME
	$ValidTypes = $global:Configuration.ValidMachineTypes

	if (Get-Variable -Name "MachineType" -Scope Global -ErrorAction SilentlyContinue) {
		if ($ValidTypes.Contains($global:MachineType)) {
			#Write-Host -ForegroundColor Green "`n=> Using pre-defined Machine Type: $($global:MachineType)"
			return $global:MachineType
		}
		else {
			Write-LogError "Pre-defined Machine Type '$($global:MachineType)' is invalid"
			Remove-Variable -Name "MachineType" -Scope Global
		}
	}

	# Try to get machine type from hostname mapping
	if ($global:Configuration.HostnameToMachineType.ContainsKey($Hostname)) {
		$MachineType = $global:Configuration.HostnameToMachineType[$Hostname]
	}
	else {
		$MachineType = $null
	}

	if ($null -eq $MachineType) {
		Write-LogTitle "Determining Machine Type"
		do {
			Write-LogError "Machine type could not be inferred from hostname => [$Hostname]"

			# Menu-style list feeding Custom-ReadHost - left raw (composite render).
			$AvailableTypesString = ($ValidTypes | ForEach-Object { "`n $_" }) -join ""
			Write-Host -ForegroundColor DarkCyan "`n[Available Machine Types]`n$AvailableTypesString`n"
			$global:MachineType = Custom-ReadHost "Specify the Machine Type: " -AddNewLine:$false

			if (-not $ValidTypes.Contains($global:MachineType)) {
				Write-LogError "Invalid Machine Type. Choose from: $($ValidTypes -join "`n ")"
			}

		} until ($ValidTypes.Contains($global:MachineType))

		Write-LogSuccess "Machine Type set to: $($global:MachineType)"
	}
	else {
		$global:MachineType = $MachineType
	}

	return $global:MachineType
}
