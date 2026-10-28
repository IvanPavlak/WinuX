# Set-GitConsoleColor

Keeps git's colors (the diffstat's green and red `+` and `-`, among others) while its output is shown through `Out-Host`, and turns that off again.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$colored = Set-GitConsoleColor
try { git merge --ff-only origin/master | Out-Host }
finally { if ($colored) { Set-GitConsoleColor -Off } }
```

## Related

- [`Set-GitConsoleColor` in the Git module reference](../../../modules/git.md#set-gitconsolecolor) - parameters, usage and behaviour
- [Git configuration guides](README.md) - every guide for this module
