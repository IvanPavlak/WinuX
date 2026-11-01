function Open-T3Code {
	<#
    .SYNOPSIS
        Opens T3 Code.

    .DESCRIPTION
        Starts T3 Code using Start-Application from its per-user install directory.
        Does nothing if T3 Code is already running.

        T3 Code is an Electron application, which attaches to the console of the process that
        launched it: it would log into this terminal and die with it, hence -Detached.

        The process name carries the release channel ("T3 Code (Beta)"), as does the
        executable, so a channel change means updating both here and in the layout files.

    .EXAMPLE
        Open-T3Code
        Opens T3 Code.
    #>
	Start-Application `
		-AppName "T3 Code" `
		-ProcessName "T3 Code (Beta)" `
		-StartMethod DirectPath `
		-ExecutablePath "$env:LOCALAPPDATA\Programs\t3code\T3 Code (Beta).exe" `
		-Detached
}
