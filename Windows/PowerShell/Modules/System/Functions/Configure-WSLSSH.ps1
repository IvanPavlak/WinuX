function Configure-WSLSSH {
	<#
    .SYNOPSIS
        Configure SSH permissions in WSL for proper security.

    .DESCRIPTION
        Copies the Windows .ssh directory into the WSL user's home directory and sets
        appropriate permissions for the .ssh directory, config file, and all key files.
        - Directory: 700 (rwx------)
        - Config file: 600 (rw-------)
        - Private keys: 600 (rw-------)
        - Public keys: 644 (rw-r--r--)

        The WSL username and home directory are derived from inside WSL - they routinely
        differ from the Windows username (Linux is case-sensitive and WSL accounts are
        lowercase by convention, e.g. Windows `Ivan` vs WSL `ivan`).

    .EXAMPLE
        Configure-WSLSSH
    #>

	Write-LogTitle "Configuring WSL SSH"

	if (-not (Confirm-ConfigValue $Configuration.DefaultWSLDistribution "DefaultWSLDistribution not configured - skipping WSL SSH setup!")) {
		return
	}

	# Always target the configured distribution explicitly: Docker Desktop and podman
	# machines routinely steal the WSL *default*, and a bare `wsl` would then run all
	# of this inside the wrong distro (e.g. podman's `user` account).
	$distro = $Configuration.DefaultWSLDistribution

	# Never assume $env:USERNAME maps to the WSL account: `Ivan` on Windows is not
	# `ivan` in Linux, and a wrong name silently builds a root-owned /home/<Wrong>
	# that SSH never reads. Ask WSL itself for the default user and their home.
	$wslUser = "$(wsl -d $distro -e sh -c 'id -un')".Trim()
	$wslHome = "$(wsl -d $distro -e sh -c 'echo $HOME')".Trim()
	if (-not $wslUser -or -not $wslHome) {
		Write-LogError "Could not determine the WSL user - is the distribution initialized? Skipping WSL SSH setup!"
		return
	}

	$sshDir = "$wslHome/.ssh"
	$windowsSshDir = "/mnt/c/Users/$env:USERNAME/.ssh"
	$failed = $false

	Write-LogError "Removing existing .ssh if present!" -BlankLineAfter
	wsl -d $distro -u root bash -c "rm -rf $sshDir"
	wsl -d $distro -u root bash -c "mkdir -p $sshDir"

	Write-LogSuccess "Copying SSH files from Windows to WSL" -NoLeadingNewline
	wsl -d $distro -u root bash -c "cp -rL $windowsSshDir/* $sshDir/ 2>/dev/null || cp -r $windowsSshDir/* $sshDir/"
	if ($LASTEXITCODE) { $failed = $true }

	Write-LogSuccess "Setting ownership => ${wslUser}:${wslUser}" -NoLeadingNewline
	wsl -d $distro -u root chown -R "${wslUser}:${wslUser}" $sshDir
	if ($LASTEXITCODE) { $failed = $true }

	Write-LogSuccess "Setting directory permissions => 700" -NoLeadingNewline
	wsl -d $distro -u root chmod 700 $sshDir
	if ($LASTEXITCODE) { $failed = $true }

	Write-LogSuccess "Setting config file permissions => 600" -NoLeadingNewline
	wsl -d $distro -u root bash -c "[ ! -f $sshDir/config ] || chmod 600 $sshDir/config"
	if ($LASTEXITCODE) { $failed = $true }

	Write-LogSuccess "Setting private key permissions => 600" -NoLeadingNewline
	wsl -d $distro -u root bash -c "find $sshDir -type f ! -name '*.pub' ! -name 'known_hosts*' ! -name 'authorized_keys*' ! -name 'config' -exec chmod 600 {} \;"
	if ($LASTEXITCODE) { $failed = $true }

	Write-LogSuccess "Setting public key permissions => 644" -NoLeadingNewline
	wsl -d $distro -u root bash -c "find $sshDir -type f -name '*.pub' -exec chmod 644 {} \;"
	if ($LASTEXITCODE) { $failed = $true }

	if ($failed) {
		Write-LogError "Some SSH setup commands failed - review the output above!"
	}
	else {
		Write-LogSuccess "SSH configured successfully!"
	}
}
