# Protocol probe scripts

Developer-only experiment harnesses, not part of the app or its user
interface. These are the scripts used to reverse-engineer the cooler's
protocol, kept here so the results in
[`docs/FINDINGS.md`](../../docs/FINDINGS.md) are reproducible and so anyone
adding support for a new cooler model (see
[`docs/ADDING_DEVICES.md`](../../docs/ADDING_DEVICES.md)) can re-run the same
experiments against their device.

The scripts communicate with the running app through a narrow developer-only
JSON bridge (`~/.redmagic_probe_command.json` and
`~/.redmagic_probe_status.json`). The bridge carries only the raw values needed
for these experiments and is not present in release builds. Build and launch a
local probe-enabled app, connect the cooler, and then start a probe:

```bash
./build.sh --with-probes --run
```

| Script           | What it maps                                                       |
|------------------|--------------------------------------------------------------------|
| `probe_modes.sh` | The cooling-mode bytes: steps through all 8 values and records the hot-side temperature each one produces, isolating TEC power from fan speed. |
| `probe_fan.sh`   | The fan-speed curve: which 0–100 values produce distinct RPMs (the firmware's response is U-shaped, not linear). |
| `probe_light.sh` | The LED effect bytes: interactive — shows you each effect and asks what you saw, then writes the results to `led_mapping.md` in this folder. |

A word of caution: `probe_modes.sh` deliberately writes mode bytes the vendor
app never uses. They're accepted by the VC Cooler 6 Pro firmware without
complaint, but on an untested model, watch the hot-side temperature while it
runs and unplug if anything looks wrong.
