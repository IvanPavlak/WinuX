function Configure-WSLSSH {
	<#
    .SYNOPSIS
        Configure SSH permissions in WSL for proper security.

    .DESCRIPTION
        Symlinks the .ssh directory and sets appropriate permissions for the .ssh directory, config file, and all private key files.
        - Directory: 700 (rwx------)
        - Config file: 600 (rw-------)
        - Private keys: 600 (rw-------)

    .EXAMPLE
        Configure-WSLSSH
    #>

	Write-LogTitle "Configuring WSL SSH"

	$user = $env:USERNAME
	$sshDir = "/home/$user/.ssh"
	$windowsSshDir = "/mnt/c/Users/$user/.ssh"

	Write-LogError "Removing existing .ssh if present!" -BlankLineAfter
	wsl -u root bash -c "rm -rf $sshDir"
	wsl -u root bash -c "mkdir -p $sshDir"

	Write-LogSuccess "Copying SSH files from Windows to WSL" -NoLeadingNewline
	wsl -u root bash -c "cp -rL $windowsSshDir/* $sshDir/ 2>/dev/null || cp -r $windowsSshDir/* $sshDir/"

	Write-LogSuccess "Setting ownership => ${user}:${user}" -NoLeadingNewline
	wsl -u root chown -R "${user}:${user}" $sshDir

	Write-LogSuccess "Setting directory permissions => 700" -NoLeadingNewline
	wsl chmod 700 $sshDir

	Write-LogSuccess "Setting config file permissions => 600" -NoLeadingNewline
	wsl bash -c "[ -f $sshDir/config ] && chmod 600 $sshDir/config"

	Write-LogSuccess "Setting private key permissions => 600" -NoLeadingNewline
	wsl bash -c "find $sshDir -type f ! -name '*.pub' ! -name 'known_hosts*' ! -name 'authorized_keys*' ! -name 'config' -exec chmod 600 {} \;"

	Write-LogSuccess "Setting public key permissions => 644" -NoLeadingNewline
	wsl bash -c "find $sshDir -type f -name '*.pub' -exec chmod 644 {} \;"

	Write-LogSuccess "SSH configured successfully!"
}
