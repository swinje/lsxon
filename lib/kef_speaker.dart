import 'dart:async';
import 'dart:io';

class KefSpeaker {
  final String host;
  final int port;

  /// When true, raw sent/received bytes and parsed results are printed.
  /// Useful for debugging the on/off status detection.
  final bool debug;

  KefSpeaker({required this.host, this.port = 50001, this.debug = false});

  void _log(String msg) {
    // ignore: avoid_print — debug logging, gated by the `debug` flag.
    if (debug) print('[KefSpeaker $host] $msg');
  }

  /// Turns the speaker on (if off) and switches it to Optical input.
  /// Works whether the speaker is currently on or off/standby.
  Future<bool> turnOnOptical({int retries = 3}) async {
    // Opt = 11, "never standby" offset = 32, L/R (non-inverted) = +0
    const int opticalNeverStandbyCode = 43;
    return _sendSetCommand(
      register: 48,
      value: opticalNeverStandbyCode,
      retries: retries,
    );
  }

  /// Generic "set source" command builder, in case you want other
  /// sources/standby combos later.
  Future<bool> setSource({
    required int sourceCode,
    required StandbyTime standby,
    bool inverted = false,
    bool turnOn = true,
  }) async {
    int code = sourceCode + standby.offset + (inverted ? 64 : 0);
    if (!turnOn) code += 128; // mirrors Python lib's "state=off" branch
    return _sendSetCommand(register: 48, value: code, retries: 3);
  }

  /// Turns the speaker off (standby) while keeping the current source.
  /// Mirrors the Python lib's `turn_off` (adds 128 to the source code).
  Future<bool> turnOff({int retries = 3}) async {
    // Optical "never standby" code is 43; +128 puts the speaker in standby.
    const int offCode = 43 + 128;
    return _sendSetCommand(register: 48, value: offCode, retries: retries);
  }

  /// Returns whether the speaker is currently powered on.
  /// Returns `null` if the query could not be completed (speaker booting or
  /// unreachable), so callers can avoid overwriting a known state with a
  /// false "off".
  Future<bool?> isOn() async {
    final value = await _sendGetCommand(register: 48);
    _log(
      'isOn: raw value=$value -> ${value == null ? 'null' : (value <= 128 ? 'ON' : 'OFF')}',
    );
    if (value == null) return null;
    // The 128 bit is the power bit. When it is SET (value >= 128) the speaker
    // is in standby/off; when it is UNSET (value < 128) the speaker is on.
    // This matches the reference library (aiokef, for the LS50), which uses
    // `value <= 128` for "on". The source code (e.g. 43 = Optical) occupies
    // the lower 7 bits, so an on speaker reports 43 and a standby speaker
    // reports 43 + 128 = 171.
    return value <= 128;
  }

  /// Returns the current volume as a 0.0–1.0 value, or `null` if the speaker
  /// is muted or off/unreachable.
  Future<double?> getVolume() async {
    final value = await _sendGetCommand(register: 37); // '%'
    _log('getVolume: raw value=$value');
    if (value == null) return null;
    if (value >= 128) return null; // muted
    return (value % 128) / 100.0;
  }

  /// Sets the volume. [volume] is clamped to the 0.0–1.0 range.
  Future<bool> setVolume(double volume) async {
    final v = (volume.clamp(0.0, 1.0) * 100).round();
    _log('setVolume: requested=$volume -> value=$v');
    return _sendSetCommand(register: 37, value: v, retries: 3);
  }

  Future<bool> _sendSetCommand({
    required int register,
    required int value,
    required int retries,
  }) async {
    final message = [0x53, register, 0x81, value]; // 'S', register, 129, value
    for (int attempt = 0; attempt < retries; attempt++) {
      _log('SET send: $message (attempt ${attempt + 1})');
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        final completer = Completer<List<int>>();
        final received = <int>[];
        socket.listen(
          (data) => received.addAll(data),
          onDone: () => completer.complete(received),
          onError: (e) => completer.completeError(e),
          cancelOnError: true,
        );
        socket.add(message);
        await socket.flush();
        final reply = await completer.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => received,
        );
        await socket.close();

        _log('SET recv: $reply');
        // Success reply is [82, 17, 255] somewhere in the response
        if (_containsSuccess(reply)) {
          _log('SET success');
          return true;
        }
      } catch (e) {
        _log('SET error: $e');
        // swallow and retry — speaker can be slow waking from standby
      }
      await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    return false;
  }

  bool _containsSuccess(List<int> reply) {
    for (int i = 0; i + 2 < reply.length + 1 && i + 2 <= reply.length; i++) {
      if (i + 2 <= reply.length &&
          reply.length >= i + 3 &&
          reply[i] == 82 &&
          reply[i + 1] == 17 &&
          reply[i + 2] == 255) {
        return true;
      }
    }
    return reply.length >= 3 &&
        reply[reply.length - 3] == 82 &&
        reply[reply.length - 2] == 17 &&
        reply[reply.length - 1] == 255;
  }

  /// Sends a "get" command (`'G'`, register, 128) and returns the value byte
  /// from the reply segment `R(82), register, value`. Returns `null` on
  /// failure or if no matching reply was received.
  ///
  /// Retries a few times because the speaker only accepts a single TCP
  /// connection at a time — a quick follow-up query (e.g. volume right after
  /// isOn) is often refused while the previous socket is still closing.
  Future<int?> _sendGetCommand({required int register}) async {
    final message = [0x47, register, 0x80]; // 'G', register, 128
    for (int attempt = 0; attempt < 3; attempt++) {
      _log('GET send: $message (attempt ${attempt + 1})');
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        final completer = Completer<List<int>>();
        final received = <int>[];
        socket.listen(
          (data) => received.addAll(data),
          onDone: () => completer.complete(received),
          onError: (e) => completer.completeError(e),
          cancelOnError: true,
        );
        socket.add(message);
        await socket.flush();
        final reply = await completer.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () => received,
        );
        await socket.close();

        _log('GET recv (register $register): $reply');

        // Split reply into segments starting with 'R' (82) and find the one
        // whose second byte matches our register. The segment layout is
        // R(82), register, <status>, value, <checksum>, so the value is the
        // 4th byte (index i+3).
        for (int i = 0; i + 3 < reply.length; i++) {
          if (reply[i] == 82 && reply[i + 1] == register) {
            return reply[i + 3];
          }
        }
        _log('GET: no segment matched register $register');
      } catch (e) {
        _log('GET error: $e');
        // swallow and retry — speaker may be off/standby or unreachable
      }
      await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
    }
    return null;
  }
}

enum StandbyTime {
  twentyMin(0),
  sixtyMin(16),
  never(32);

  final int offset;
  const StandbyTime(this.offset);
}
