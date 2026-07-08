function Open-ClaudeDesktop {
	<#
	.SYNOPSIS
		Opens Claude Desktop.

	.DESCRIPTION
		Starts Claude Desktop using Start-Application via its local electron launcher.
		Does nothing if Claude Desktop is already running.

		The running check is scoped to the Claude Desktop install directory so it is not tripped
		by the Claude Code CLI, which also runs as a process named "claude".

	.EXAMPLE
		Open-ClaudeDesktop
		Opens Claude Desktop.
	#>
	Start-Application `
		-AppName "Claude" `
		-ProcessName "claude" `
		-ProcessPathFilter "$env:LOCALAPPDATA\AnthropicClaude\*" `
		-StartMethod DirectPath `
		-ExecutablePath "$env:LOCALAPPDATA\AnthropicClaude\claude.exe" `
		-Arguments "--processStart", "claude.exe"
}
