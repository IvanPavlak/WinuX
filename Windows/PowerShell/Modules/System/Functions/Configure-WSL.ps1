function Configure-WSL {
	<#
	.SYNOPSIS
		Enables WSL and installs the default WSL distribution.

	.DESCRIPTION
		Enables the WSL Windows optional feature if not already enabled.
		Installs the default WSL distribution (read from `DefaultWSLDistribution` in Configuration.psd1)
		if not already installed.

		When `DefaultWSLUsername` is configured, the WSL user account is created
		non-interactively on first installation: the username comes from configuration,
		the password is prompted in the terminal (used for sudo - passwords never live
		in configuration), and the account is made the distribution's default user via
		/etc/wsl.conf. Without it, the interactive first-launch setup runs instead:
		- Username: your choice (lowercase)
		- Password: [prompted, used for sudo]

		Requires administrator privileges.

	.PARAMETER Force
		Redoes the whole WSL setup even when the distribution is already installed:
		unregisters the existing distribution (DELETING everything inside it), reinstalls
		it, recreates the user, and re-runs Initialize-WSLEnvironment, SymbolicLinkMaker
		-Scope WSL (restoring only the WSL symlinks the reinstall wiped), and Configure-WSLSSH.

	.EXAMPLE
		Configure-WSL
		Enables WSL and installs the default distribution if needed.

	.EXAMPLE
		Configure-WSL -Force
		Wipes the installed distribution and redoes the whole WSL setup from scratch.
	#>
	param(
		[Alias("Override")]
		[switch]$Force
	)
	try {
		Write-LogTitle "Configuring WSL"

		Test-AdminPrivileges

		# Guard before enabling the WSL Windows feature: an unconfigured distribution
		# means the user never opted into WSL, so nothing gets installed or enabled.
		if (-not (Confirm-ConfigValue $Configuration.DefaultWSLDistribution "DefaultWSLDistribution not configured - skipping WSL setup!")) {
			return
		}

		if (-not (Test-WSLEnabled)) {
			Write-LogTitle "Enabling WSL"
			Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
			Write-LogSuccess "WSL enabled!"
		}
		else {
			Write-LogWarning "WSL is already enabled"
		}

		$distro = $Configuration.DefaultWSLDistribution

		if ($Force -and (Test-WSLDistributionInstalled)) {
			Write-LogWarning "-Force: unregistering $distro - ALL data inside the distribution is deleted!" -BlankLineAfter
			wsl --unregister $distro
		}

		if (-not (Test-WSLDistributionInstalled)) {
			Write-LogTitle "Installing $distro" -BlankLineAfter
			wsl --install -d $distro --no-launch
			Write-LogSuccess "$distro installed"

			# A freshly installed distro is not registered until the machine reboots. Only run the
			# first-launch user setup if the distro is actually available now; otherwise defer
			# with a clear message instead of dumping wsl.exe's help text and silently no-opping.
			if (Test-WSLDistributionInstalled) {
				$wslUser = $Configuration.DefaultWSLUsername
				if (Test-ConfigValue $wslUser) {
					# Linux usernames are lowercase by convention (Ubuntu's default useradd
					# NAME_REGEX rejects uppercase) - normalize instead of failing.
					if ($wslUser -cne $wslUser.ToLower()) {
						$wslUser = $wslUser.ToLower()
						Write-LogWarning "DefaultWSLUsername lowercased to [$wslUser]"
					}

					Write-LogTitle "Creating WSL user [$wslUser]"
					# A fresh --no-launch install runs as root, so the account can be created
					# without the interactive first-launch wizard.
					wsl -d $distro -u root useradd --create-home --shell /bin/bash --groups "adm,sudo" $wslUser
					Write-LogWarning "Set the password for [$wslUser] (used for sudo):" -BlankLineAfter
					wsl -d $distro -u root passwd $wslUser

					# Make it the default user via /etc/wsl.conf (distro-agnostic, unlike the
					# per-distro launcher exe). Update an existing [user] section in place
					# instead of appending a duplicate.
					wsl -d $distro -u root sh -c "grep -q '^\[user\]' /etc/wsl.conf 2>/dev/null && sed -i 's/^default=.*/default=$wslUser/' /etc/wsl.conf || printf '\n[user]\ndefault=%s\n' '$wslUser' >> /etc/wsl.conf"

					# wsl.conf is only read at distro start - restart so the default user applies.
					wsl --terminate $distro
					Write-LogSuccess "WSL user [$wslUser] created and set as default!"
				}
				else {
					Write-LogTitle "Set up WSL user on first launch"
					Write-LogSuccess "   Username => [your choice, lowercase]"
					Write-LogSuccess "   Password => [sudo password]" -NoLeadingNewline
					Write-LogTitle "Launching WSL for initial setup"
					Write-LogWarning "Use [exit] to let the WSL setup continue!" -BlankLineAfter
					wsl
				}

				# -Force promises the WHOLE setup, so redo the pieces Bootstrap normally runs
				# as separate steps (all idempotent): the in-distro environment, the WSL
				# symlinks a reinstall wiped (WSL scope only - Windows links are untouched
				# by a distro reinstall), and the SSH keys.
				if ($Force) {
					Initialize-WSLEnvironment
					SymbolicLinkMaker -Scope WSL
					Configure-WSLSSH
				}
			}
			else {
				Write-LogWarning "$distro needs a reboot before first launch - WSL user setup is deferred. Re-run Bootstrap after rebooting to finish it." -BlankLineAfter
			}
		}
		else {
			Write-LogWarning "$distro is already installed"
		}

		# Docker Desktop and podman machines routinely steal the WSL *default* distribution,
		# which silently redirects every bare `wsl` invocation (and the Windows Terminal
		# default WSL profile) into the wrong distro. Pin the configured one every run.
		if (Test-WSLDistributionInstalled) {
			wsl --set-default $distro
			Write-LogSuccess "$distro pinned as the default WSL distribution"
		}
	}
	catch {
		Write-LogError "An error occurred during installation: $_"
		Write-LogError "Stack Trace => [$($_.ScriptStackTrace)]"
	}
}
