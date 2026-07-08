function Initialize-WSLEnvironment {
	<#
	.SYNOPSIS
		Installs and configures fastfetch inside the WSL environment.

	.DESCRIPTION
		Installs the fastfetch system info tool inside the active WSL distribution via apt,
		then adds `fastfetch` to `.bashrc` so it runs automatically on shell startup.

	.EXAMPLE
		Initialize-WSLEnvironment
		Installs fastfetch and adds it to WSL shell initialization.
	#>
	Write-LogTitle "Configuring WSL Environment"

	# Check if fastfetch is installed
	$fastfetchInstalled = wsl bash -c "command -v fastfetch &> /dev/null && echo 'true' || echo 'false'"
	if ($fastfetchInstalled -ne 'true') {
		Write-LogTitle "Installing fastfetch" -BlankLineAfter
		wsl -u root add-apt-repository ppa:zhangsongcui3371/fastfetch -y
		wsl -u root apt update
		wsl -u root apt install fastfetch -y
		Write-LogSuccess "fastfetch installed!"
	}
	else {
		Write-LogWarning "fastfetch is already installed!"
	}

	# Check if fastfetch is in .bashrc
	$bashrcCheck = wsl bash -c "grep -q 'fastfetch' ~/.bashrc && echo 'exists' || echo 'missing'"
	if ($bashrcCheck -eq 'missing') {
		Write-LogTitle "Adding fastfetch to .bashrc"
		wsl bash -c "echo '' >> ~/.bashrc && echo 'fastfetch' >> ~/.bashrc"
		Write-LogSuccess "fastfetch added to .bashrc!"
	}
	else {
		Write-LogWarning "fastfetch is already configured in .bashrc!"
	}

	Write-LogTitle "Configuring oh-my-posh"
	$tempScript = "/tmp/setup-ohmyposh.sh"
	$ohmyposhScript = @'
#!/bin/bash

# Check and install unzip if needed
printf "\n[Installing unzip]\n"
if ! dpkg -l | grep -q "^ii  unzip"; then
    sudo apt install unzip -y
    printf "\n=> unzip installed!"
else
    printf "\n unzip is already installed!\n"
fi

# Check and install oh-my-posh if needed
printf "\n[Installing oh-my-posh]\n\n"
if ! command -v oh-my-posh &> /dev/null; then
    curl -s https://ohmyposh.dev/install.sh | bash -s
    printf "\n=> oh-my-posh installed!\n"
else
    printf "\n oh-my-posh is already installed!"
fi

# Add oh-my-posh to .profile if not already present
printf "\n[Adding oh-my-posh to .profile]\n\n"
OHMYPOSH_LINE='eval "$(oh-my-posh init bash --config /mnt/c/Users/__WINUSER__/AppData/Local/Programs/oh-my-posh/themes/__OMPTHEME__)"'
if ! grep -q "oh-my-posh init bash" ~/.profile 2>/dev/null; then
    echo -e "\n$OHMYPOSH_LINE" >> ~/.profile
    printf "\n=> oh-my-posh added to .profile!"
else
    printf "\n oh-my-posh is already configured in .profile"
fi

# Reload profile
source ~/.profile 2>/dev/null || true
'@

	# Inject the current Windows username and the configured oh-my-posh theme filename into the
	# mounted-drive (/mnt/c/Users/...) path. Theme is config-driven (Universal.OhMyPoshThemeFile).
	$ompTheme = if ($Configuration.Universal.OhMyPoshThemeFile) { Split-Path -Leaf $Configuration.Universal.OhMyPoshThemeFile } else { "WinuX.omp.json" }
	$ohmyposhScript = $ohmyposhScript.Replace('__WINUSER__', $env:USERNAME).Replace('__OMPTHEME__', $ompTheme)

	$ohmyposhScript | wsl bash -c "tr -d '\r' | tee $tempScript > /dev/null"
	wsl chmod +x $tempScript
	wsl bash $tempScript
	wsl rm -f $tempScript

	Write-LogSuccess "WSL environment initialization complete!"
}
