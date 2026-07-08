function Create-Executable {
	<#
    .SYNOPSIS
    Creates a standalone executable from a PowerShell function and its dependencies.

    .DESCRIPTION
    This function analyzes a PowerShell function, discovers all its custom dependencies,
    bundles them together, converts global variables to parameters, and creates a
    standalone .exe file using ps2exe.

    The resulting executable is completely self-contained and includes all custom
    function dependencies. The user only needs to run the .exe file.

    .PARAMETER FunctionName
    The name of the PowerShell function to convert to an executable.

    .PARAMETER OutputPath
    Optional path for the output executable. If not specified, creates the .exe
    in the current directory with the name FunctionName.exe.

    .PARAMETER NoConsole
    Creates a Windows Forms application without a console window.

    .PARAMETER RequireAdmin
    Requires the executable to run with administrator privileges.

    .PARAMETER IconFile
    Path to a custom icon file (.ico) for the executable.

    .PARAMETER Title
    Title for the executable (visible in file properties).

    .PARAMETER Description
    Description for the executable (visible in file properties).

    .PARAMETER Company
    Company name for the executable metadata.

    .PARAMETER Version
    Version number for the executable (e.g., "1.0.0.0").

    .EXAMPLE
    Create-Executable -FunctionName "Determine-DotnetDependencies"

    Creates DotnetDependencies.exe in the current directory with all dependencies bundled.

    .EXAMPLE
    Create-Executable -FunctionName "List-Functions" -OutputPath "C:\Tools\ListFunctions.exe" -Title "Function Lister"

    Creates a custom executable with metadata.

    .EXAMPLE
    Create-Executable -FunctionName "Configure-System" -RequireAdmin -NoConsole

    Creates a GUI executable that requires administrator privileges.
    #>

	[CmdletBinding()]
	param(
		[Parameter(Mandatory)]
		[string]$FunctionName,

		[Parameter()]
		[string]$OutputPath,

		[Parameter()]
		[switch]$NoConsole,

		[Parameter()]
		[switch]$RequireAdmin,

		[Parameter()]
		[string]$IconFile,

		[Parameter()]
		[string]$Title,

		[Parameter()]
		[string]$Description,

		[Parameter()]
		[string]$Company = "WinuX",

		[Parameter()]
		[string]$Version = "1.0.0.0"
	)

	Write-LogTitle "PowerShell Executable Creator"

	# Step 1: Verify ps2exe is installed
	Write-LogStep " Checking for ps2exe module..."
	if (-not (Get-Module -ListAvailable -Name ps2exe)) {
		Write-LogError "ps2exe module not found!"
		Write-Host -ForegroundColor Yellow "   Run: Install-PowerShellModules"
		Write-Host -ForegroundColor Yellow "   Or: Install-Module -Name ps2exe -Scope CurrentUser"
		return
	}

	# Import ps2exe if not already loaded
	if (-not (Get-Module -Name ps2exe)) {
		Import-Module ps2exe -ErrorAction SilentlyContinue
	}

	Write-Host -ForegroundColor Green "   ps2exe module found!"

	# Step 2: Verify function exists
	Write-LogStep " Verifying function exists..."
	try {
		$command = Get-Command $FunctionName -ErrorAction Stop
	}
	catch {
		Write-LogError "Function [$FunctionName] not found!"
		Write-Host -ForegroundColor Yellow "   Make sure the function is loaded in your current session."
		return
	}

	Write-Host -ForegroundColor Green "   Function [$FunctionName] found!"

	# Step 3: Analyze dependencies
	Write-LogStep " Analyzing dependencies..."

	# Reset processed functions tracker
	$script:ProcessedFunctions = @()

	$deps = Get-PowerShellFunctionDependencies -FunctionName $FunctionName -Recursive

	if (-not $deps) {
		Write-LogError "Failed to analyze dependencies!"
		return
	}

	# Display dependency report
	Write-LogTitle "Dependency Analysis Report"

	if ($deps.Custom.Count -gt 0) {
		Write-Host -ForegroundColor Yellow "`n Custom Functions (will be bundled):"
		$deps.Custom | ForEach-Object {
			Write-LogStep "   - $($_.Command) (from $($_.Module) module)" -NoLeadingNewline
		}
	}
	else {
		Write-Host -ForegroundColor Green "`n No custom function dependencies found."
	}

	if ($deps.Module.Count -gt 0) {
		Write-Host -ForegroundColor Yellow "`n External Module Dependencies (must be installed separately):"
		$deps.Module | Group-Object Module | ForEach-Object {
			Write-LogStep "   - $($_.Name): $($_.Group.Command -join ', ')" -NoLeadingNewline
		}
		Write-Host -ForegroundColor DarkYellow "`n   Note: The target machine must have these modules installed!"
	}

	if ($deps.GlobalVariables.Count -gt 0) {
		Write-Host -ForegroundColor Yellow "`n Global Variables (will be converted to parameters):"
		$deps.GlobalVariables | ForEach-Object {
			Write-LogStep "   - `$global:$_" -NoLeadingNewline
		}
	}

	# Step 4: Build the bundled script
	Write-LogStep " Building bundled script..."

	$scriptContent = @"
# ============================================================================
# Auto-generated executable for: $FunctionName
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# Created by: Create-Executable function
# ============================================================================

"@

	# Add custom function dependencies first (in order)
	if ($deps.Custom.Count -gt 0) {
		$scriptContent += "`n# === Dependency Functions ===`n`n"

		foreach ($dep in $deps.Custom) {
			$scriptContent += "# Function: $($dep.Command) (from $($dep.Module) module)`n"
			$scriptContent += "# " + ("-" * 76) + "`n"

			# Convert global variables to parameters in dependencies too
			$depDefinition = Convert-GlobalVariablesToParameters -FunctionDefinition $dep.Definition

			# Wrap in function declaration
			$scriptContent += "function $($dep.Command) {`n"
			$scriptContent += $depDefinition
			$scriptContent += "`n}`n`n"
		}
	}

	# Add the main function
	$scriptContent += "# === Main Function ===`n`n"
	$scriptContent += "# Function: $FunctionName`n"
	$scriptContent += "# " + ("-" * 76) + "`n"

	# Convert global variables to parameters in main function
	$mainDefinition = Convert-GlobalVariablesToParameters -FunctionDefinition $command.Definition

	# Wrap in function declaration
	$scriptContent += "function $FunctionName {`n"
	$scriptContent += $mainDefinition
	$scriptContent += "`n}`n`n"

	# Add invocation code
	$scriptContent += @"
# === Execution ===
# Invoke the main function with all command-line arguments
try {
    $FunctionName @args
}
catch {
    Write-Host -ForegroundColor Red "`nError: `$(`$_.Exception.Message)"
    exit 1
}
finally {
    Write-Host -ForegroundColor DarkCyan "`nConsole will close in 60 seconds..."
    Start-Sleep -Seconds 60
}
"@

	# Step 5: Write to temporary file
	$tempScript = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "$FunctionName-$(Get-Date -Format 'yyyyMMddHHmmss').ps1")

	try {
		$scriptContent | Out-File -FilePath $tempScript -Encoding UTF8 -Force
		Write-Host -ForegroundColor Green "   Temporary script created: $tempScript"
	}
	catch {
		Write-LogError "Failed to create temporary script: $($_.Exception.Message)"
		return
	}

	# Step 6: Determine output path
	if ([string]::IsNullOrWhiteSpace($OutputPath)) {
		$OutputPath = Join-Path $PWD "$FunctionName.exe"
	}

	# Ensure output path has .exe extension
	if (-not $OutputPath.EndsWith('.exe')) {
		$OutputPath += '.exe'
	}

	# Step 7: Build ps2exe parameters
	Write-LogStep " Creating executable..."
	Write-LogStep "   Output: $OutputPath" -NoLeadingNewline

	$ps2exeParams = @{
		inputFile  = $tempScript
		outputFile = $OutputPath
		noError    = $false
		noOutput   = $false
	}

	if ($NoConsole) {
		$ps2exeParams.noConsole = $true
		Write-LogStep "   Mode: GUI (no console)" -NoLeadingNewline
	}
	else {
		Write-LogStep "   Mode: Console application" -NoLeadingNewline
	}

	if ($RequireAdmin) {
		$ps2exeParams.requireAdmin = $true
		Write-LogStep "   Privileges: Requires Administrator" -NoLeadingNewline
	}

	if ($IconFile -and (Test-Path $IconFile)) {
		$ps2exeParams.iconFile = $IconFile
		Write-LogStep "   Icon: $IconFile" -NoLeadingNewline
	}

	if ($Title) {
		$ps2exeParams.title = $Title
	}
	else {
		$ps2exeParams.title = $FunctionName
	}

	if ($Description) {
		$ps2exeParams.description = $Description
	}
	else {
		$ps2exeParams.description = "PowerShell executable for $FunctionName"
	}

	if ($Company) {
		$ps2exeParams.company = $Company
	}

	if ($Version) {
		$ps2exeParams.version = $Version
	}

	# Step 8: Execute ps2exe
	try {
		Write-Host ""
		Invoke-ps2exe @ps2exeParams

		if (Test-Path $OutputPath) {
			$fileInfo = Get-Item $OutputPath
			Write-LogSuccess "Executable created successfully!"
			Write-LogStep "   Location: $OutputPath" -NoLeadingNewline
			Write-LogStep "   Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -NoLeadingNewline
			Write-LogTitle "Usage"
			Write-LogStep "   Run: $OutputPath" -NoLeadingNewline

			# Show parameter usage if function has parameters
			if ($command.Parameters.Count -gt 0) {
				Write-LogStep "   Available parameters:"
				$command.Parameters.Keys | ForEach-Object {
					if ($_ -notin @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable')) {
						Write-LogStep "      -$_" -NoLeadingNewline
					}
				}
			}
		}
		else {
			Write-LogError "Failed to create executable!"
			Write-Host -ForegroundColor Yellow "   Check the ps2exe output above for errors."
		}
	}
	catch {
		Write-LogError "Error creating executable: $($_.Exception.Message)"
	}
	finally {
		# Step 9: Cleanup temporary file
		if (Test-Path $tempScript) {
			Remove-Item $tempScript -Force -ErrorAction SilentlyContinue
		}
	}
}
