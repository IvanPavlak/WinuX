# Tests Module Configuration Guides

One configuration guide per exported function of the `Tests` module, which covers the Pester test runner. 1 function in total: 0 read configuration and 1 do not.

The [Tests module reference](../../../modules/tests.md) is the authority on what each function *does*. These guides cover what to *configure* for it.

> [!TIP]
> Working through a whole module is what [WinuXConfigurator](../../winux-configurator.md) is for - point an AI assistant at it and it walks the table below with you, one decision at a time.

## Configurable Functions

No function in the `Tests` module reads `Configuration.psd1`.

## Functions With No Configuration

These read no `Configuration.psd1` keys. Their guides record that fact and show how to call them.

[Run-Tests](Run-Tests.md)

## Related

- [Tests module reference](../../../modules/tests.md) - what each function does
- [Configuration reference](../../configuration-reference.md) - every key, section by section
- [Configuration overview](../../overview.md) - how the configuration system fits together
- [Fork Model](../../../contributing/fork-model.md) - why your values go in `Configuration.local.psd1`
- [WinuXConfigurator](../../winux-configurator.md) - AI-assisted walkthrough of every module
