function Clear-WhatsAppLocalStorage {
	<#
	.SYNOPSIS
		Clears WhatsApp local storage to resolve startup issues.

	.DESCRIPTION
		Stops WhatsApp if running, then deletes the local storage directory at the path
		configured in `Configuration.Universal.WhatsAppLocalStoragePath`.
		Requires administrator privileges.

	.EXAMPLE
		Clear-WhatsAppLocalStorage
		Stops WhatsApp and clears its local storage directory.
	#>
	Test-AdminPrivileges

	Write-LogTitle "Clearing Local WhatsApp Storage"

	Write-LogStep "Checking if WhatsApp is closed!"
	if (Get-Process -Name "WhatsApp.Root" -ErrorAction SilentlyContinue) {
		try {
			Stop-Process -Name "WhatsApp.Root" -Force -ErrorAction Stop
			Write-LogSuccess "WhatsApp closed!"
		}
		catch {
			Write-LogError "Error: $($_.Exception.Message)"
		}
	}
	else {
		Write-LogWarning "WhatsApp is already closed!"
	}

	$whatsAppLocalStoragePath = $Configuration.Universal.WhatsAppLocalStoragePath

	if (-not (Test-Path -Path $whatsAppLocalStoragePath)) {
		Write-LogWarning "WhatsApp Storage is already cleared!"
		return
	}

	Write-LogStep " Listing contents of WhatsApp local storage directory:"
	Get-ChildItem $whatsAppLocalStoragePath -Directory | ForEach-Object {
		$size = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
		[PSCustomObject]@{
			Directory = $_.Name
			MB        = [math]::Round($size / 1MB, 2)
			GB        = [math]::Round($size / 1GB, 2)
		}
	} | Format-Table -AutoSize

	$totalSize = (Get-ChildItem -Recurse $whatsAppLocalStoragePath -File | Measure-Object -Property Length -Sum).Sum
	Write-LogStep "Total => $([math]::Round($totalSize / 1MB, 2)) MB ($([math]::Round($totalSize / 1GB, 2)) GB)" -NoLeadingNewline

	$clearStorageConfirmation = Resolve-Selection `
		-MenuTitle "[Clear Local WhatsApp Storage]" `
		-PromptMessage "Do you want to clear the local WhatsApp storage? (Enter for default => Yes)" `
		-AllowEmptyPromptResponse:$true

	if ($clearStorageConfirmation -eq "Yes" -or $null -eq $clearStorageConfirmation) {
		Write-LogStep " Removing everything from => [$whatsAppLocalStoragePath]"
		try {
			Remove-Item $whatsAppLocalStoragePath -Recurse -Force
			Write-LogSuccess "Local WhatsApp Storage cleared successfully!"
		}
		catch {
			Write-LogError "Error: $_"
		}
	}
	else {
		Write-LogError "Local WhatsApp Storage cleaning cancelled!"
	}
}
