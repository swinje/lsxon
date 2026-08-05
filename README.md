# LSX On

A simple Flutter app to control your KEF LSX speakers over the local network.
Enter the speaker's IP address (default `192.168.0.143`) and you can:

- Turn the speaker **On** (and switch it to the Optical input)
- Turn it **Off** (standby)
- See whether it is currently on/off
- Adjust the **volume** with a slider

The protocol is based on the reverse-engineered KEF network commands.

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
