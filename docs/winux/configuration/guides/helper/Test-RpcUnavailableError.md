# Test-RpcUnavailableError

Classifies an ErrorRecord, exception, or message string as an RPC availability failure - the error family VirtualDesktop COM calls surface when the shell endpoint is gone or the session's cached COM proxies have disconnected from a restarted `explorer.exe`: `0x800706BA` "The RPC server is unavailable", `0x800706BE` "The remote procedure call failed", `0x80010108` "The object invoked has disconn...

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-RpcUnavailableError $_
if (Test-RpcUnavailableError $errorRecord) { [void](Reset-VirtualDesktopState) }
```

## Related

- [`Test-RpcUnavailableError` in the Helper module reference](../../../modules/helper.md#test-rpcunavailableerror) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
