function Configure-PostgreSqlPasswords {
	<#
    .SYNOPSIS
        Changes the PostgreSQL default database user password.

    .DESCRIPTION
        Prompts for the current (default) PostgreSQL password and the new password,
        then updates the `postgres` user password in the PostgreSQL server.

        With `-Auto`, reads the current and new passwords from `PostgreSqlPasswords` in
        Configuration.psd1 and applies them without prompting.

    .PARAMETER DefaultOrCurrentPassword
        The current PostgreSQL password (for authentication).

    .PARAMETER NewPassword
        The new PostgreSQL password to set.

    .PARAMETER Auto
        Reads passwords from Configuration.psd1 instead of prompting.

    .EXAMPLE
        Configure-PostgreSqlPasswords -Auto
        Changes the PostgreSQL password using configuration settings.
    #>
	param(
		[Parameter(Mandatory = $false)]
		[string]$DefaultOrCurrentPassword,

		[Parameter(Mandatory = $false)]
		[string]$NewPassword,

		[Parameter(Mandatory = $false)]
		[switch]$Auto
	)

	Write-LogTitle "Configuring PostgreSQL password"

	if ($Auto -or (-not $DefaultOrCurrentPassword -and -not $NewPassword)) {
		if (-not $Configuration.PostgreSqlPasswords) {
			Write-LogError "PostgreSQL password configuration not found!"
			return
		}

		$DefaultOrCurrentPassword = $Configuration.PostgreSqlPasswords.DefaultOrCurrent
		$NewPassword = $Configuration.PostgreSqlPasswords.New

		Write-LogStep "=> Using configuration!"
	}

	if (-not $DefaultOrCurrentPassword -or -not $NewPassword) {
		Write-LogError "Both current and new passwords are required!"
		return
	}

	try {
		$env:PGPASSWORD = $DefaultOrCurrentPassword

		$foundPaths = @()
		$searchPaths = @(
			"C:\Program Files\PostgreSQL",
			"C:\Program Files (x86)\PostgreSQL"
		)

		foreach ($searchPath in $searchPaths) {
			if (Test-Path $searchPath) {
				$versionDirs = Get-ChildItem -Path $searchPath -Directory -ErrorAction SilentlyContinue
				foreach ($versionDir in $versionDirs) {
					$psqlPath = Join-Path $versionDir.FullName "bin\psql.exe"
					if (Test-Path $psqlPath) {
						$foundPaths += $psqlPath
					}
				}
			}
		}

		if ($foundPaths.Count -eq 0) {
			Write-LogError "PostgreSQL psql.exe not found in common installation paths!"
			return
		}

		Write-LogStep "=> Found [$($foundPaths.Count)] PostgreSQL installation(s)!"

		$sqlFile = "$env:TEMP\update_postgres_password.sql"
		"ALTER USER postgres WITH PASSWORD '$NewPassword';" | Out-File -FilePath $sqlFile -Encoding ASCII

		$successCount = 0
		$failureCount = 0
		$alreadyConfiguredCount = 0
		$failedVersions = @()

		$portsToTry = @(5432, 5433, 5434, 5435)

		foreach ($psqlPath in $foundPaths) {
			$version = ($psqlPath -replace '.*PostgreSQL\\(\d+)\\.*', '$1')
			Write-LogStep " Configuring PostgreSQL [$version]..."

			$versionSuccess = $false
			$alreadyConfigured = $false
			$lastError = ""

			foreach ($port in $portsToTry) {
				try {
					$env:PGPASSWORD = $NewPassword
					$testResult = & $psqlPath -U postgres -d postgres -p $port -c "SELECT 1;" 2>&1

					if ($LASTEXITCODE -eq 0) {
						Write-LogWarning "PostgreSQL [$version] password already configured on port [$port]!"
						$alreadyConfiguredCount++
						$alreadyConfigured = $true
						$versionSuccess = $true
						break
					}
				}
				catch {

				}
				finally {
					$env:PGPASSWORD = $DefaultOrCurrentPassword
				}

				if (-not $alreadyConfigured) {
					try {
						$result = & $psqlPath -U postgres -d postgres -p $port -f $sqlFile 2>&1

						if ($LASTEXITCODE -eq 0) {
							Write-LogSuccess "PostgreSQL [$version] password updated successfully on port [$port]!"
							$successCount++
							$versionSuccess = $true
							break
						}
						else {
							$lastError = $result
						}
					}
					catch {
						$lastError = $_.Exception.Message
						continue
					}
				}
			}

			if (-not $versionSuccess) {
				Write-LogError "PostgreSQL [$version] failed on all attempted ports => [$($portsToTry -join ', ')]" -NoLeadingNewline
				if ($lastError) {
					Write-LogError "Last error: [$lastError]" -NoLeadingNewline
				}
				$failureCount++
				$failedVersions += $version
			}
		}

		Remove-Item $sqlFile -Force -ErrorAction SilentlyContinue

		if ($alreadyConfiguredCount -gt 0) {
			Write-LogWarning "[$alreadyConfiguredCount] PostgreSQL password(s) already configured!"
		}

		if ($successCount -gt 0) {
			Write-LogSuccess "[$successCount] PostgreSQL password(s) configured successfully!"
		}

		if ($failureCount -gt 0) {
			Write-LogError "Failed => [$failureCount]" -NoLeadingNewline

			$failedVersionsList = $failedVersions -join ", "

			$content = @"
Some PostgreSQL installations failed to configure automatically.
Failed versions: $failedVersionsList

Common Issue: The script tried ports 5432, 5433, 5434, and 5435.
If your PostgreSQL instance runs on a different port, follow the manual steps below.

Manual Steps:
1. Open SQL Shell (psql) for the failed version from Start Menu
2. Use default settings (press Enter 4 times for Server, Database, Port, Username)
   - If connection fails, try specifying the port manually (check your PostgreSQL service port)
3. Enter the current password when prompted: $DefaultOrCurrentPassword
4. Run the following command:
   ALTER USER postgres WITH PASSWORD '$NewPassword';
5. Type \q to exit

Alternative: Check PostgreSQL service port in Services (services.msc)
- Look for "postgresql-x64-XX" service (where XX is the version number)
- The port is typically configured in postgresql.conf in the data directory

Note: Repeat these steps for each failed PostgreSQL installation.
"@

			Write-ManualInstructionsToDesktop -FileName "PostgreSQL_Password_Manual_Instructions.txt" `
				-Title "PostgreSQL Password Configuration - Manual Instructions" `
				-Content $content
		}
	}
	catch {
		Write-LogError "Failed to update PostgreSQL password: $($_.Exception.Message)"

		$content = @"
The automatic configuration failed with an unexpected error.

Manual Steps:
1. Open SQL Shell (psql) from Start Menu for your PostgreSQL version
2. Use default settings (press Enter 4 times for Server, Database, Port, Username)
   - Common ports: 5432 (default), 5433, 5434, 5435
   - If connection fails, check your PostgreSQL service port in Services (services.msc)
3. Enter the current password when prompted: $DefaultOrCurrentPassword
4. Run the following command:
   ALTER USER postgres WITH PASSWORD '$NewPassword';
5. Type \q to exit

Troubleshooting:
- Verify PostgreSQL service is running in Services (services.msc)
- Check which port your PostgreSQL instance is using
- Ensure the current password is correct
- Try connecting manually first to verify credentials

Error Details:
$($_.Exception.Message)
"@

		Write-ManualInstructionsToDesktop -FileName "PostgreSQL_Password_Manual_Instructions.txt" `
			-Title "PostgreSQL Password Configuration - Manual Instructions" `
			-Content $content
	}
	finally {
		Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue
	}
}
