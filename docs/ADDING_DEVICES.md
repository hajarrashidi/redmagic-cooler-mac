# Adding support for another cooler

The app only *knows* one device today — the REDMAGIC VC Cooler 6 Pro — but all
of that knowledge lives in a single place:
[`src-swift/BLE/DeviceProfile.swift`](../src-swift/BLE/DeviceProfile.swift).
A profile bundles everything model-specific: the name to match in a Bluetooth
scan, the GATT service and characteristic UUIDs, and how to decode the
telemetry frames. The rest of the app — connection handling, autopilot, UI,
CLI — is model-agnostic and just follows whichever profile matched.

So supporting a new cooler is a reverse-engineering exercise that ends in one
new `DeviceProfile`. This guide walks the whole path. Read
[`FINDINGS.md`](FINDINGS.md) alongside it — that's the finished worked example
for the 6 Pro, and other REDMAGIC coolers will likely look very similar.

## What you need

- The cooler, and a Mac.
- A BLE explorer to poke at the device by hand. On the Mac,
  [LightBlue](https://apps.apple.com/app/lightblue/id557428110) or
  [Bluetility](https://github.com/jnross/Bluetility); on a phone,
  [nRF Connect](https://www.nordicsemi.com/Products/Development-tools/nRF-Connect-for-mobile).
- Optionally: an Android phone with the vendor app (REDMAGIC coolers use
  *Goper*, older ones the *REDMAGIC Equipment* app) so you can capture what the
  official app sends.

## Step 1 — Find the device's advertised name

REDMAGIC coolers don't advertise their service UUID, so this app discovers
them by **name substring**. Scan with your BLE explorer while the cooler is
powered and note the exact advertised name (the 6 Pro shows up as
`RM Magcooler 6pro`).

Pick a lowercase substring of it that's unlikely to match anything else —
that'll be the profile's `nameHints` entry.

## Step 2 — Map the GATT table

Connect to the cooler with the BLE explorer and list its services and
characteristics. You're looking for a vendor service (a random-looking 128-bit
UUID, not one of the Bluetooth-SIG `0000xxxx-0000-1000-8000-00805f9b34fb`
assigned ones) containing a handful of short read/write/notify
characteristics.

For the 6 Pro that's service `d52082ad-…` with characteristics `0x1011`
through `0x1019` — the full map is in [`FINDINGS.md`](FINDINGS.md). If your
cooler's table looks the same, you may be nearly done: try writing the known
bytes (e.g. `0x01` to the cooling-mode characteristic) and see if the device
responds.

## Step 3 — Work out what the bytes mean

If the table doesn't match, capture what the vendor app sends:

- **Android HCI snoop log** — enable *Bluetooth HCI snoop log* in the phone's
  developer options, drive the cooler from the vendor app while changing one
  thing at a time, then pull the log and open it in Wireshark. Every ATT write
  is right there with its handle and payload.
- **Decompile the APK** — [jadx](https://github.com/skylot/jadx) on the vendor
  APK turns up the UUID constants and the code that assembles each payload.
  This is how the 6 Pro's LED payload format (`[effect, R, G, B]`) was
  confirmed.

Change one control in the app per capture. A slider that goes 0–100 and
produces single-byte writes 0x00–0x64 identifies itself immediately.

For notify characteristics (telemetry), subscribe and watch frames while you
change the physical situation: warm the plate with your hand and see which
byte moves — that's a temperature. Frame markers (the 6 Pro uses `0xAA` in
byte 0) and multi-byte fields like fan RPM stand out once a few frames are
side by side.

## Step 4 — Write the profile

Add a `static let` to the extension at the bottom of `DeviceProfile.swift`,
mirroring `vcCooler6Pro`, and register it:

```swift
static let all: [DeviceProfile] = [.vcCooler6Pro, .yourNewModel]
```

That's the only registration step. Discovery, the device picker, connection
and reconnection, writes, and telemetry decoding all pick it up from there.

If the new device genuinely lacks one of the profile's characteristics (say,
no hall sensor), give it a placeholder UUID that won't be found — discovery
skips characteristics the device doesn't expose — and the related feature
simply stays inert. If it needs *more* than the profile can express (a
different write payload shape, extra controls), extend `DeviceProfile` with a
new closure the way `decodeTelemetry` works, and keep the model-specific bytes
out of `CoolerBLEManager`.

## Step 5 — Verify with the probe scripts

The scripts in [`tools/probe/`](../tools/probe/) automate the tedious part of
confirming a mapping: `probe_modes.sh` sweeps the cooling-mode bytes and logs
the hot-side temperature each produces, `probe_fan.sh` maps fan values to
RPM, and `probe_light.sh` walks the LED effect bytes interactively. They talk
to the running app over its IPC files, so build and launch the app with your
new profile first.

Be gentle with unknown mode bytes on a new device: the 6 Pro accepts
undocumented values harmlessly, but keep an eye on the hot-side temperature
the first time through.

## Step 6 — Document what you found

Add your GATT map and byte tables to a findings doc (mirror
[`FINDINGS.md`](FINDINGS.md)), note the advertised name, and mention the model
in the README's supported-devices table. The next person with that cooler will
thank you.
