function Configure-WSL {
	<#
	.SYNOPSIS
		Enables WSL and installs the default WSL distribution.

	.DESCRIPTION
		Enables the WSL Windows optional feature if not already enabled.
		Installs the default WSL distribution (read from `DefaultWSLDistribution` in Configuration.psd1)
		if not already installed.

		On first installation, prompts the user to set up the WSL user account:
		- Username: your choice (lowercase)
		- Password: [prompted, used for sudo]

		Requires administrator privileges.

	.EXAMPLE
		Configure-WSL
		Enables WSL and installs the default distribution if needed.
	#>
	try {
		Write-LogTitle "Configuring WSL"

		if (-not (Test-WSLEnabled)) {
			Write-LogTitle "Enabling WSL"
			Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
			Write-LogSuccess "WSL enabled!"
		}
		else {
			Write-LogWarning "WSL is already enabled"
		}

		$distro = $Configuration.DefaultWSLDistribution

		if (-not (Test-WSLDistributionInstalled)) {
			Write-LogTitle "Installing $distro" -BlankLineAfter
			wsl --install -d $distro --no-launch
			Write-LogSuccess "$distro installed"

			# A freshly installed distro is not registered until the machine reboots. Only run the
			# interactive first-launch setup if the distro is actually available now; otherwise defer
			# with a clear message instead of dumping wsl.exe's help text and silently no-opping.
			if (Test-WSLDistributionInstalled) {
				Write-LogTitle "Set up WSL user on first launch"
				Write-LogSuccess "   Username => [your choice, lowercase]"
				Write-LogSuccess "   Password => [sudo password]" -NoLeadingNewline
				Write-LogTitle "Launching WSL for initial setup"
				Write-LogWarning "Use [exit] to let the WSL setup continue!" -BlankLineAfter
				wsl
			}
			else {
				Write-LogWarning "$distro needs a reboot before first launch - WSL user setup is deferred. Re-run Bootstrap after rebooting to finish it." -BlankLineAfter
			}
		}
		else {
			Write-LogWarning "$distro is already installed"
		}
	}
	catch {
		Write-LogError "An error occurred during installation: $_"
		Write-LogError "Stack Trace => [$($_.ScriptStackTrace)]"
	}
}
