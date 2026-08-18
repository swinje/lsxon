# LSX On

A simple Flutter app to control your **KEF LSX (1st generation)** speakers over
the local network. Enter the speaker's IP address (default `192.168.0.143`) and
you can:

- Turn the speaker **On** (and switch it to your chosen input)
- Turn it **Off** (standby)
- **Choose the input source** — Optical, Aux, or Bluetooth — applied each time
  the speaker is turned on
- See whether it is currently on/off
- Adjust the **volume** with a slider

The protocol is based on the reverse-engineered KEF network commands.

## Why this app exists

This app is a **workaround**. The built-in Wi-Fi in the LSX Gen 1 speakers
gave me constant connectivity problems, so I switched to using an external
streamer instead. The catch is that the speakers still need to be *woken up*
over the network before they'll play — which is exactly what this app does:
tap once to power the speaker on and select the input, then your streamer
takes over.

Because Wi-Fi has to stay enabled for the wake-up command to reach the
speakers, the KEF still shows up as a castable device in music apps and
confuses the source picker. To keep it out of the way I renamed the speaker to
**"do not use"** in the KEF app — a small trick so it doesn't clutter the list
of real playback targets.

In my own setup I pair the LSX with a **WiiM mini** streamer connected over
**Optical**. I set the default source to Optical and the default volume to
**75**, which has turned out to be a good starting level for that combination —
the WiiM then handles the actual playback and volume.

> **Disclaimer:** This project is not affiliated with, endorsed by, or
> sponsored by KEF. "KEF" and "LSX" are trademarks of their respective owner.
> All product names are used descriptively to indicate device compatibility.

## Acknowledgements

This project would not be possible without the work of
[Bas Nijholt](https://github.com/basnijholt), who reverse-engineered the KEF
LSX network protocol in his
[`media_player.kef`](https://github.com/basnijholt/media_player.kef) Home
Assistant integration. The on/optical command sequence used here is based on
that discovery. Thank you for figuring out how to wake these speakers up!

## How it works

The app talks to the speaker over TCP port `50001` using the reverse-engineered
KEF network protocol:

- **SET** command: `[0x53 ('S'), register, 0x81 (129), value]`
- **GET** command: `[0x47 ('G'), register, 0x80 (128)]`
- Success reply: `[82, 17, 255]` (`R`, `17`, `255`)

Source is controlled via register `48` and volume via register `37`. On the
LSX, the `128` bit of the source register is the standby bit: `value <= 128`
means the speaker is on, `value >= 128` means it is in standby.

The input source is selected by the lower 7 bits of register `48`. The codes
match [aiokef](https://github.com/basnijholt/aiokef)'s
`INPUT_SOURCES_20_MINUTES_LR` mapping:

| Input     | Code |
|-----------|------|
| Optical   | 11   |
| Aux       | 10   |
| Bluetooth | 9    |

The app adds the "never standby" offset (`32`) when turning on and the power
bit (`128`) when turning off, preserving the selected source.

## Settings

Open **Advanced settings** from the top-right menu (⋮) to configure:

- **Speaker IP address** — the address used to reach the speaker (default
  `192.168.0.143`). Saved as you type.
- **Default volume (0–100)** — applied automatically whenever the speaker is
  turned on. Saved as you type.
- **Default source when turned on** — choose **Optical**, **Aux**, or
  **Bluetooth**. This input is selected each time the speaker is switched on.
  Defaults to **Optical** if not set, and is saved immediately when you pick it.

All settings are persisted on the device via `shared_preferences` and restored
on the next launch.

## Finding your speaker's IP

The app needs the speaker's IP address on your local network. A few ways to
find it:

- **Router admin page / app** — look in the DHCP client list for a device
  named "KEF LSX" or a MAC vendor of "KEF".
- **KEF Connect app** — its settings/about screen usually shows the assigned
  IP.
- **`arp -a`** on a computer after the speaker has been awake — the IP appears
  next to the KEF MAC address.
- **Static DHCP reservation** — pin the speaker to a fixed IP in your router so
  it never changes; then you set it once in the app. (The `192.168.0.143`
  default assumes your router already hands that out consistently.)

### Automatic scan

The app can also find the speaker for you:

- **On first launch** (no IP configured yet) it offers to scan the network.
- **In Advanced settings** there is a **Scan for speaker** button.

Scanning works by probing every device on your local subnet (a /24) on port
`50001` and keeping the first one that answers like a KEF speaker. Because this
is a port scan, **only run it on a network you own or control**. Do **not** use
it on corporate, public, or shared networks — port scanning can trigger
intrusion-detection / intrusion-prevention systems or other security devices
that may react to the scan. The app shows this warning before scanning.

## Requirements

- An iOS device on the same local network as the KEF LSX speakers.
- Local Network permission is requested on first launch (required to reach the
  speaker).
- Flutter 3.x and a macOS machine with Xcode to build.

## Building

```sh
flutter pub get
flutter run
```

## License

Released under the MIT License — see the [LICENSE](LICENSE) file.
