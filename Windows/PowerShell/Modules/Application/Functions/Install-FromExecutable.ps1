function Install-FromExecutable {
	<#
	.SYNOPSIS
		Unified, reliable, self-cleaning runner for installer-style executables (download or local).

	.DESCRIPTION
		Generalizes the "download an installer, run it, then clean up" pattern that individual
		installer functions used to duplicate. Given either a download -Url or a local -Path, it
		fetches the installer (with retry), runs it, and always removes anything it downloaded.

		Two run modes are selected by whether -Arguments is supplied:
		- Unattended: pass -Arguments (the vendor's own silent switches, e.g. "/S", "/qn"). The
		  installer is run with -Wait and success is gated on its exit code (see -ValidExitCodes),
		  so a non-zero code is reported as a failure instead of a false success. Supplying
		  -Arguments - even empty - selects this mode, so an automated run never blocks on a prompt.
		- Interactive: omit -Arguments. The installer's GUI is launched and the function blocks until
		  you confirm completion.

		Reliability & safety: a -Url download goes to a unique, function-owned folder under the temp
		directory and is wrapped in Invoke-WithOptionalRetry (exponential backoff, -MaxAttempts); any
		partial file is deleted between attempts. Cleanup removes only that temp folder - a
		caller-supplied -Path is run in place and never deleted. Because the download folder is a fresh
		temp directory (never derived from -Name), the run can neither collide with nor destroy
		existing user data.

		Administrator elevation is opt-in via -RequireAdmin (many per-user installers don't need it).

	.PARAMETER Name
		Display name of the software. Drives the log title ("Installing <Name>").

	.PARAMETER Url
		Download URL of the installer. The installer is saved to a temporary folder and removed after
		the run. Mutually exclusive with -Path.

	.PARAMETER InstallerName
		File name to save the downloaded installer as. Defaults to the URL's last path segment when it
		ends in a recognized installer extension (.exe, .msi, .msix, .appx, .bat, .cmd), otherwise
		"installer.exe". Reduced to a bare file name. Ignored when -Path is used.

	.PARAMETER Path
		Path to an existing local installer to run. It is executed in place and never deleted.
		Mutually exclusive with -Url.

	.PARAMETER Arguments
		Silent/unattended switches passed to the installer. Supplying this parameter (even empty)
		selects unattended mode; omit it for an interactive GUI install. Empty/whitespace entries are
		ignored.

	.PARAMETER ValidExitCodes
		Exit codes treated as success in unattended mode. Defaults to 0 and 3010 (reboot required).

	.PARAMETER DetectionPath
		Optional path that, when it already exists, marks the software as installed - the function
		logs a warning and returns without downloading or running anything (idempotency).

	.PARAMETER MaxAttempts
		Number of download attempts (exponential backoff between them). Defaults to 3.

	.PARAMETER RequireAdmin
		Require administrator privileges. When set, Test-AdminPrivileges runs first and elevates or
		aborts if the session is not elevated.

	.EXAMPLE
		Install-FromExecutable -Name "Visual Studio 2026" -Url "https://c2rsetup.example/vs.exe" -RequireAdmin
		Downloads the installer, launches its GUI, waits for you to finish, then cleans up.

	.EXAMPLE
		Install-FromExecutable -Name "7-Zip" -Url "https://www.7-zip.org/a/7z2408-x64.exe" -Arguments "/S"
		Silent install; success is gated on the installer's exit code.

	.EXAMPLE
		Install-FromExecutable -Name "MyApp" -Path "D:\installers\myapp-setup.exe" -Arguments "/quiet" -DetectionPath "C:\Program Files\MyApp\myapp.exe"
		Runs a local installer silently, skipping if MyApp is already present.
	#>
	[CmdletBinding(DefaultParameterSetName = 'Download')]
	param(
		[Parameter(Mandatory = $true, Position = 0)]
		[string]$Name,

		[Parameter(Mandatory = $true, ParameterSetName = 'Download')]
		[string]$Url,

		[Parameter(ParameterSetName = 'Download')]
		[string]$InstallerName,

		[Parameter(Mandatory = $true, ParameterSetName = 'LocalPath')]
		[string]$Path,

		[string[]]$Arguments,

		[int[]]$ValidExitCodes = @(0, 3010),

		[string]$DetectionPath,

		[int]$MaxAttempts = 3,

		[switch]$RequireAdmin
	)

	if ($RequireAdmin) { Test-AdminPrivileges }

	Write-LogTitle "Installing $Name"

	# Idempotency: honor a caller-supplied detection path so re-runs are no-ops. -LiteralPath so paths
	# containing wildcard characters (e.g. "Foo [2026]") are matched literally, not as globs.
	if ($DetectionPath -and (Test-Path -LiteralPath $DetectionPath)) {
		Write-LogWarning "$Name is already installed!"
		return
	}

	# Resolve where the installer lives. For -Url we download into a unique, function-owned temp folder
	# and delete it afterwards; for -Path we run the caller's own file in place and never delete it.
	# The temp folder is never derived from -Name, so cleanup can't collide with or wipe user data.
	$downloaded = $PSCmdlet.ParameterSetName -eq 'Download'
	if ($downloaded) {
		$installerExtensions = @('.exe', '.msi', '.msix', '.appx', '.bat', '.cmd')
		if (-not $InstallerName) {
			# Take the URL's last path segment (after dropping any query/fragment). Split manually
			# rather than via [System.IO.Path] helpers, which THROW on invalid path characters under
			# Windows PowerShell 5.1 - and this runs before the try/catch below.
			$leaf = ((($Url -split '[?#]', 2)[0]).TrimEnd('/', '\') -split '[\\/]')[-1]
			$extension = if ($leaf -match '(\.[A-Za-z0-9]+)$') { $matches[1].ToLowerInvariant() } else { '' }
			$InstallerName = if ($installerExtensions -contains $extension) { $leaf } else { 'installer.exe' }
		}
		# Reduce to a bare, filesystem-safe file name so a crafted URL or name can neither escape the
		# download folder nor carry characters that are invalid in a Windows path.
		$InstallerName = (($InstallerName -split '[\\/]')[-1]) -replace '[<>:"/\\|?*]', ''
		if ([string]::IsNullOrWhiteSpace($InstallerName)) { $InstallerName = 'installer.exe' }

		$downloadDir = Join-Path -Path $env:TEMP -ChildPath ("WinuX-Install_" + [guid]::NewGuid().ToString('N'))
		$installerPath = Join-Path -Path $downloadDir -ChildPath $InstallerName
	}
	else {
		$installerPath = $Path
	}

	try {
		if ($downloaded) {
			New-Item -ItemType Directory -Path $downloadDir -Force -ErrorAction SilentlyContinue | Out-Null

			Write-LogStep "=> Downloading $Name installer..."
			$download = { Invoke-WebRequest -Uri $Url -OutFile $installerPath -UseBasicParsing }
			$onRetry = {
				param($ErrorRecord, $Attempt)
				# Drop any partial download so the next attempt starts from a clean slate.
				Remove-Item -LiteralPath $installerPath -Force -ErrorAction SilentlyContinue
			}
			if (Get-Command Invoke-WithOptionalRetry -ErrorAction SilentlyContinue) {
				Invoke-WithOptionalRetry -ScriptBlock $download -EnableRetry -MaxAttempts $MaxAttempts -OnRetry $onRetry
			}
			else {
				& $download
			}
		}
		elseif (-not (Test-Path -LiteralPath $installerPath)) {
			Write-LogError "Installer not found at '$installerPath'."
			return
		}

		# Supplying -Arguments (even empty) means "run unattended"; omitting it means "interactive GUI".
		if ($PSBoundParameters.ContainsKey('Arguments')) {
			Write-LogStep "=> Running $Name installer silently..."
			$startParams = @{
				FilePath    = $installerPath
				Wait        = $true
				PassThru    = $true
				ErrorAction = 'Stop'
			}
			$silentArgs = @($Arguments | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
			if ($silentArgs.Count -gt 0) { $startParams['ArgumentList'] = $silentArgs }

			$process = Start-Process @startParams
			$exitCode = $process.ExitCode

			if ($ValidExitCodes -contains $exitCode) {
				if ($exitCode -eq 3010) {
					Write-LogWarning "A reboot is required to complete $Name setup."
				}
				Write-LogSuccess "$Name installed successfully!"
			}
			else {
				Write-LogError "$Name installer exited with code $exitCode."
			}
		}
		else {
			# Interactive install: launch the GUI and block until the user confirms completion.
			Write-LogStep "=> Launching $Name installer..." -NoLeadingNewline
			Write-LogWarning "Complete the installation in the GUI!"
			Start-Process -FilePath $installerPath
			$null = Custom-ReadHost -ForegroundColor DarkCyan "`n Press any key after the installation is complete..." -AddNewLine:$false
			Write-LogSuccess "$Name installed successfully!"
		}
	}
	catch {
		Write-LogError "Failed to install $($Name): $($_.Exception.Message)" -Exception $_
	}
	finally {
		# Only clean up the temp folder we created; never touch a caller-supplied -Path.
		if ($downloaded) {
			Write-LogStep "=> Cleaning up installer files..."
			Remove-Item -LiteralPath $downloadDir -Recurse -Force -ErrorAction SilentlyContinue
		}
	}
}
