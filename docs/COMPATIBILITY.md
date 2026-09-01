# Device compatibility

The app supports coolers through explicit device profiles. A model is marked
supported only after its advertised name, GATT characteristics, commands, and
telemetry have been verified on physical hardware.

This list focuses on REDMAGIC coolers with official evidence of Bluetooth or
vendor-app control. Button-only models are intentionally omitted because there
is no remote connection for the macOS app to use.

## Status

| Model | Introduced | Official control evidence | Project status |
|-------|------------|---------------------------|----------------|
| [REDMAGIC Cryo Cooler 8 Pro](https://redmagic.tech/products/redmagic-cryo-cooler-8-pro) | 2026 | REDMAGIC app connectivity | **Unsupported — unverified and untested** |
| [REDMAGIC VC Cooler 6 Pro](https://redmagic.tech/products/redmagic-vc-cooler-6-pro) | 2025 | Goper app | **Supported — hardware verified** |
| [REDMAGIC VC Cooler 5 Pro](https://redmagic.tech/blogs/product-information/learn-more-about-the-technology-that-brings-you-the-redmagic-vc-cooler-5-pro) | 2024 | Goper app | **Unsupported — unverified and untested** |
| [REDMAGIC Dual-Core Ice Dock](https://redmagic.tech/blogs/product-information/the-battle-of-redmagic-external-cooling-solutions) | 2022 | Bluetooth and REDMAGIC Equipment app | **Unsupported — unverified and untested** |

The Cryo Cooler 8 series launched on March 10, 2026. REDMAGIC describes the
Cryo Cooler 8 Pro as its latest generation of external active cooling and
documents app control; this project has not yet inspected that model's radio,
GATT table, or protocol. The companion Cryo Cooler 8 Air uses button adjustment
according to its official product page, so it is not included in the table.

The same rule excludes older coolers whose official controls are mechanical or
which have no radio. Absence from this list does not prove that a model lacks
Bluetooth; it means there is not enough authoritative evidence yet to present
it as a candidate.

## Add or verify a model

If you have one of the untested coolers, start with
[`ADDING_DEVICES.md`](ADDING_DEVICES.md). The guide covers finding its BLE name,
mapping GATT services, capturing vendor-app writes, implementing a profile, and
verifying it with the probe scripts.

Partial findings are useful. Open an issue with the advertised name, a GATT
dump, or packet capture even if you cannot complete the profile yourself.

## Research sources

Compatibility research was checked on **September 1, 2026** against REDMAGIC's
official pages:

- [REDMAGIC's 2026 milestones](https://redmagic.tech/blogs/product-information/redmagic-2026-gaming-milestones)
  identifies the Cryo Cooler 8 series as the current 2026 generation.
- [Cryo Cooler 8 Pro](https://redmagic.tech/products/redmagic-cryo-cooler-8-pro)
  documents REDMAGIC app connectivity.
- [Cryo Cooler 8 Air](https://redmagic.tech/products/redmagic-cryo-cooler-8-air)
  documents button adjustment.
- [VC Cooler 6 Pro](https://redmagic.tech/products/redmagic-vc-cooler-6-pro)
  documents Goper app integration.
- [VC Cooler 5 Pro](https://redmagic.tech/blogs/product-information/learn-more-about-the-technology-that-brings-you-the-redmagic-vc-cooler-5-pro)
  documents Goper app control.
- [REDMAGIC external cooling solutions](https://redmagic.tech/blogs/product-information/the-battle-of-redmagic-external-cooling-solutions)
  documents the Dual-Core Ice Dock's Bluetooth and Equipment app control.
