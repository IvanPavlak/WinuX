# Test-RpcServerHealth

Verifies that required Remote Procedure Call (RPC) infrastructure services are running and, optionally, that this session's live RPC/COM state actually responds.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-RpcServerHealth
Test-RpcServerHealth -Probe
Test-RpcServerHealth -ServiceNames @("RpcSs", "DcomLaunch")
```

## Related

- [`Test-RpcServerHealth` in the System module reference](../../../modules/system.md#test-rpcserverhealth) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
