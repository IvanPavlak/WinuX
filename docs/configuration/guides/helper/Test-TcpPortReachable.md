# Test-TcpPortReachable

Reports whether a TCP port accepts a connection within a timeout.

## Configuration Keys

This function reads no `Configuration.psd1` keys. There is nothing to configure.

## Usage

```powershell
Test-TcpPortReachable -TargetHost "localhost" -Port 5000
Test-TcpPortReachable localhost 44300 -TimeoutMs 250
```

## Related

- [`Test-TcpPortReachable` in the Helper module reference](../../../modules/helper.md#test-tcpportreachable) - parameters, usage and behaviour
- [Helper configuration guides](README.md) - every guide for this module
