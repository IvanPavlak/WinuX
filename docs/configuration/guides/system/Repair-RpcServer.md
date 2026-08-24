# Repair-RpcServer

Attempts to recover a broken RPC/COM session when `Test-RpcServerHealth -Probe` reports it unhealthy - stale VirtualDesktop proxies after an Explorer restart, or a genuinely hung endpoint (`0x800706BA` / `0x800706BE`).

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Repair-RpcServer
Repair-RpcServer -MaxAttempts 10
```

## Related

- [`Repair-RpcServer` in the System module reference](../../../modules/system.md#repair-rpcserver) - parameters, usage and behaviour
- [System configuration guides](README.md) - every guide for this module
