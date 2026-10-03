# Test-AiModsCli

Checks that the Claude Code CLI is on PATH and that `claude plugin validate` accepts each given mod, returning `Installed` and the `Invalid` mod paths.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-AiModsCli -ModPath "$env:USERPROFILE\.claude\mods\my-mod"
(Test-AiModsCli -ModPath (Get-ChildItem "$env:USERPROFILE\.claude\mods").FullName).Invalid
```

## Related

- [`Test-AiModsCli` in the AI module reference](../../../modules/ai.md#test-aimodscli)
- [AI configuration guides](README.md)
