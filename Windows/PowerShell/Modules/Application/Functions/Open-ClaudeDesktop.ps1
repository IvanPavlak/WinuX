function Open-ClaudeDesktop {
	<#
	.SYNOPSIS
		Opens Claude Desktop.

	.DESCRIPTION
		Starts Claude Desktop using Start-Application via its local electron launcher.
		Does nothing if Claude Desktop is already running.

		The running check is scoped to the Claude Desktop install directory so it is not tripped
		by the Claude Code CLI, which also runs as a process named "claude".

		The launcher is invoked without arguments on purpose. It is a Squirrel stub executable that
		resolves the newest "app-*" install directory on its own, and it forwards any arguments it
		receives straight through to the Electron binary. Passing "--processStart claude.exe" made
		Claude Desktop treat the trailing "claude.exe" as a file to open, prompting on every launch
		to attach the executable to the session.

	.EXAMPLE
		Open-ClaudeDesktop
		Opens Claude Desktop.
	#>
	Start-Application `
		-AppName "Claude" `
		-ProcessName "claude" `
		-ProcessPathFilter "$env:LOCALAPPDATA\AnthropicClaude\*" `
		-StartMethod DirectPath `
		-ExecutablePath "$env:LOCALAPPDATA\AnthropicClaude\claude.exe"
}
