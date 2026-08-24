# Get-RpcRetryPolicy

Centralizes the RPC safety pattern used by VirtualDesktop-heavy workflows.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
$rpcPolicy = Get-RpcRetryPolicy -OperationLabel "desktop cleanup"
Get-RpcRetryPolicy -Probe
```

## Related

- [`Get-RpcRetryPolicy` in the Helper module reference](../../../modules/helper.md#get-rpcretrypolicy) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
