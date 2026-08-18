import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'kef_speaker.dart';

const String _kIpKey = 'speaker_ip';
const String _kDefaultIp = '192.168.0.143';
const String _kDefaultVolumeKey = 'default_volume'; // 0..100
const int _kDefaultVolume = 50;
const String _kDefaultSourceKey =
    'default_source'; // 'optical'|'aux'|'bluetooth'
const Source _kDefaultSource = Source.optical;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LSX On',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'LSX On'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _defaultVolumeController =
      TextEditingController();
  bool _busy = false;
  bool _ready = false; // becomes true once the startup state query finishes
  String? _status;
  bool? _isOn;
  double? _volume;
  int _defaultVolume = _kDefaultVolume;
  Source _defaultSource = _kDefaultSource;
  bool _scanning = false;

  KefSpeaker _speaker() =>
      KefSpeaker(host: _ipController.text.trim(), debug: false);

  /// Toggles the speaker. When the state is known it turns the speaker off
  /// if on (or on if off). When the state is unknown (e.g. right after the
  /// IP was changed) it just turns the speaker ON — querying is unreliable
  /// on the LSX (a clean GET reports the true state, which would make us
  /// turn an already-on speaker OFF), and turning on is harmless if it's
  /// already on.
  Future<void> _toggle() async {
    if (_busy) return;
    if (_isOn == true) {
      await _turnOff();
    } else {
      await _turnOn();
    }
  }

  @override
  void initState() {
    super.initState();
    _ipController.addListener(_saveIp);
    _init();
  }

  Future<void> _init() async {
    await _loadIp();
    await _loadDefaultVolume();
    await _loadDefaultSource();
    // If no IP has ever been saved, suggest scanning on startup. We only
    // prompt when the stored value is still the built-in default, which
    // means the user hasn't configured anything yet.
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kIpKey);
    final bool neverConfigured =
        saved == null || saved.trim().isEmpty || saved.trim() == _kDefaultIp;
    if (neverConfigured && mounted) {
      await _suggestScanOnStartup();
    }
    await _refreshState(); // query the real state instead of starting as Unknown
    setState(() => _ready = true); // reveal the toggle only after startup
  }

  /// On first launch (no saved IP), offer to scan for the speaker. The user
  /// can scan or just dismiss and enter the IP manually in Advanced settings.
  Future<void> _suggestScanOnStartup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Find your speaker?'),
        content: const Text(
          'No speaker IP is configured yet. You can scan your local network '
          'to find it automatically, or set the IP manually later in '
          'Advanced settings.\n\n'
          'Scanning checks every device on your network. Only do this on a '
          'network you own or control — not on corporate, public, or shared '
          'networks, where port scanning may trigger security systems.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Enter manually'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _scanForSpeaker();
    }
  }

  Future<void> _loadIp() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kIpKey);
    // Default to 192.168.0.143 when nothing (or only whitespace) was stored.
    _ipController.text = (saved == null || saved.trim().isEmpty)
        ? _kDefaultIp
        : saved;
  }

  Future<void> _loadDefaultVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getInt(_kDefaultVolumeKey);
    _defaultVolume = saved ?? _kDefaultVolume;
    _defaultVolumeController.text = _defaultVolume.toString();
  }

  Future<void> _saveDefaultVolume() async {
    final parsed = int.tryParse(_defaultVolumeController.text.trim());
    final clamped = (parsed ?? _kDefaultVolume).clamp(0, 100);
    setState(() => _defaultVolume = clamped);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kDefaultVolumeKey, clamped);
  }

  Future<void> _loadDefaultSource() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kDefaultSourceKey);
    Source source = _kDefaultSource;
    if (saved != null) {
      source = Source.values.firstWhere(
        (s) => s.name == saved,
        orElse: () => _kDefaultSource,
      );
    }
    setState(() => _defaultSource = source);
  }

  Future<void> _saveDefaultSource(Source source) async {
    setState(() => _defaultSource = source);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDefaultSourceKey, source.name);
  }

  /// Scans the local subnet for a KEF speaker and, if found, saves its IP.
  /// Shows a warning first because port scanning can trip security systems
  /// on networks you don't own. Returns the discovered IP, or `null`.
  Future<String?> _scanForSpeaker() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan for speaker?'),
        content: const Text(
          'This will check every device on your local network (subnet scan) '
          'to find the speaker. Only use this on a network you own or control.\n\n'
          'Do NOT run it on corporate, public, or shared networks — port '
          'scanning can trigger intrusion-detection systems or other security '
          'devices that may react to the scan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Scan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;

    setState(() => _scanning = true);
    try {
      final ip = await KefSpeaker.discover();
      if (ip != null) {
        _ipController.text = ip;
        await _saveIp();
        setState(() => _status = 'Found speaker at $ip.');
      } else {
        setState(() => _status = 'No speaker found on this network.');
      }
      return ip;
    } finally {
      setState(() => _scanning = false);
    }
  }

  Future<void> _saveIp() async {
    // Clear stale status when the IP is edited.
    if (_isOn != null || _volume != null) {
      setState(() {
        _isOn = null;
        _volume = null;
      });
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kIpKey, _ipController.text.trim());
  }

  Future<void> _turnOn() async {
    final host = _ipController.text.trim();
    if (host.isEmpty) {
      setState(() => _status = 'Please enter an IP address.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Connecting to $host…';
    });
    final ok = await _speaker().turnOn(_defaultSource);
    if (ok) {
      // Apply the user's default volume once the speaker is on.
      await _speaker().setVolume(_defaultVolume / 100.0);
    }
    // NOTE: on the LSX, reading register 48 right after a SET echoes the
    // inverse of the value we sent (send 43 -> read 171, send 171 -> read 43),
    // so probing it here would wrongly report the opposite state. Trust the
    // command result instead, as we do for turn-off.
    setState(() {
      _busy = false;
      _isOn = ok ? true : _isOn;
      _volume = ok ? _defaultVolume / 100.0 : _volume;
      _status = ok
          ? 'Speaker is on, ${_defaultSource.label} selected.'
          : 'Failed — check IP/network.';
    });
  }

  Future<void> _turnOff() async {
    setState(() {
      _busy = true;
      _status = 'Turning off…';
    });
    final ok = await _speaker().turnOff(_defaultSource);
    // NOTE: on the LSX, register 48 keeps reporting the same value (43) even
    // after the speaker enters standby, so `isOn()` cannot detect "off".
    // Trust the command result instead of re-querying, otherwise the UI
    // would immediately flip back to "On".
    setState(() {
      _busy = false;
      _isOn = ok ? false : _isOn;
      _volume = ok ? null : _volume;
      _status = ok ? 'Speaker is off.' : 'Failed to turn off.';
    });
  }

  /// Polls the speaker's on/off state, retrying for a few seconds to allow it
  /// to finish booting after power-on. A failed query (`null`) does NOT
  /// overwrite a previously known state, so the status can't get stuck on
  /// "Off" just because the speaker was slow to answer.
  Future<void> _refreshState() async {
    final speaker = _speaker();
    bool? on;
    for (int i = 0; i < 10 && on == null; i++) {
      on = await speaker.isOn();
      if (on == null) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    if (on == null) {
      setState(() {
        _isOn = null;
        _volume = null;
        _status = 'Could not reach speaker.';
      });
      return;
    }
    final bool isOn = on;
    final vol = isOn ? await speaker.getVolume() : null;
    setState(() {
      _isOn = on;
      _volume = vol;
      _status = isOn ? 'Speaker is on.' : 'Speaker is off.';
    });
  }

  /// The latest slider value the user has dragged to.
  double? _pendingVolume;

  /// Serializes volume SETs so we never open two sockets at once (the
  /// speaker only accepts one connection at a time). A short debounce means
  /// we send at most one command per pause in dragging instead of one per
  /// pixel — otherwise the speaker refuses almost all of them.
  Timer? _volumeTimer;
  Future<void>? _volumeInFlight;

  Future<void> _setVolume(double value) async {
    setState(() => _volume = value); // reflect immediately in the UI
    _pendingVolume = value;
    _volumeTimer?.cancel();
    _volumeTimer = Timer(const Duration(milliseconds: 250), _flushVolume);
  }

  /// Opens the Advanced settings in a dialog (IP + default volume). Save
  /// persists both values and immediately applies the default volume to the
  /// speaker, then refreshes the shown state.
  Future<void> _openAdvanced() async {
    final ctx = context; // capture before any async gap
    var saving = false; // dialog-local loading state
    await showDialog<void>(
      context: ctx,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Advanced settings'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _ipController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Speaker IP address',
                      border: OutlineInputBorder(),
                      hintText: '192.168.0.143',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _defaultVolumeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Default volume (0–100)',
                      border: OutlineInputBorder(),
                      hintText: '50',
                    ),
                    onChanged: (_) => _saveDefaultVolume(),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Source>(
                    initialValue: _defaultSource,
                    decoration: const InputDecoration(
                      labelText: 'Default source when turned on',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final source in Source.values)
                        DropdownMenuItem<Source>(
                          value: source,
                          child: Text(source.label),
                        ),
                    ],
                    onChanged: (source) {
                      if (source != null) {
                        _saveDefaultSource(source);
                        setDialogState(() {});
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _scanning
                        ? null
                        : () async {
                            setDialogState(() => saving = true);
                            await _scanForSpeaker();
                            if (!mounted) return;
                            setDialogState(() => saving = false);
                          },
                    icon: _scanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(_scanning ? 'Scanning…' : 'Scan for speaker'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton.icon(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        await _saveIp();
                        await _saveDefaultVolume();
                        if (!mounted) return;
                        // Apply the default volume to the speaker. A successful
                        // SET proves the speaker is reachable and powered on,
                        // so reflect that in the UI. We deliberately do NOT
                        // call isOn()/refreshState() here: on the LSX a GET
                        // issued right after a SET echoes the inverse value
                        // (send 43 -> read 171), which would wrongly report
                        // the speaker as off, and a separate query on an
                        // unreachable IP would block for tens of seconds.
                        final ok = await _speaker().setVolume(
                          _defaultVolume / 100.0,
                        );
                        if (!mounted) return;
                        setState(() {
                          _isOn = ok ? true : _isOn;
                          _volume = ok ? _defaultVolume / 100.0 : _volume;
                          _status = ok
                              ? 'Speaker is on, volume set to $_defaultVolume%.'
                              : 'Saved. Could not reach speaker at '
                                    '${_ipController.text.trim()}.';
                        });
                        // ignore: use_build_context_synchronously
                        Navigator.of(dialogContext).pop();
                      },
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('Save & apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Switches to the Spotify app (or the App Store if it isn't installed).
  Future<void> _openSpotify() async {
    final uri = Uri.parse('spotify:');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fall back to the App Store if Spotify isn't installed.
      await launchUrl(
        Uri.parse('https://apps.apple.com/app/spotify/id324684580'),
        mode: LaunchMode.externalApplication,
      );
    }
  }

  Future<void> _flushVolume() async {
    final value = _pendingVolume;
    if (value == null) return;
    // Wait for any in-flight SET to finish before starting another.
    while (_volumeInFlight != null) {
      await _volumeInFlight;
    }
    _volumeInFlight = _speaker().setVolume(value).whenComplete(() {
      _volumeInFlight = null;
    });
    await _volumeInFlight;
  }

  @override
  void dispose() {
    _ipController.removeListener(_saveIp);
    _ipController.dispose();
    _defaultVolumeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool on = _isOn == true;
    final Color accent = on ? Colors.green : Colors.red;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu), // hamburger menu, top-right
            onSelected: (value) {
              if (value == 'advanced') _openAdvanced();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'advanced',
                child: Row(
                  children: [
                    Icon(Icons.settings),
                    SizedBox(width: 12),
                    Text('Advanced settings'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          // NOTE: must be `start`, not `center`. With `center` in a scroll
          // view, when the keyboard shrinks the viewport the column gets
          // clipped at the top and unreachable, causing a RenderFlex
          // overflow error. `start` keeps it scrollable in every case.
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.speaker, size: 200, color: Colors.teal),
            const SizedBox(height: 24),
            // Status text
            Text(
              !_ready
                  ? 'Connecting…'
                  : _isOn == null
                  ? 'Unknown'
                  : (on ? 'On' : 'Off'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: _isOn == null ? Colors.grey : accent,
              ),
            ),
            const SizedBox(height: 32),
            // Big on/off toggle. Hidden (spinner) until startup query finishes.
            Center(
              child: !_ready
                  ? const SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : _busy
                  ? const SizedBox(
                      width: 72,
                      height: 72,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  : GestureDetector(
                      onTap: _toggle,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.withValues(alpha: 0.15),
                          border: Border.all(color: accent, width: 4),
                        ),
                        child: Icon(
                          on ? Icons.power_settings_new : Icons.power_off,
                          size: 72,
                          color: accent,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 32),
            // Volume control (disabled when speaker is off/unknown)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.volume_up,
                      color: on ? Colors.teal : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !on
                            ? 'Volume: —'
                            : _volume == null
                            ? 'Volume: unknown'
                            : 'Volume: ${(_volume! * 100).round()}%',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: _volume ?? 0.0,
                  onChanged: (on && !_busy) ? _setVolume : null,
                  activeColor: Colors.teal,
                  label: _volume == null
                      ? null
                      : '${(_volume! * 100).round()}%',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Switch to the Spotify app
            OutlinedButton.icon(
              onPressed: _openSpotify,
              icon: const Icon(Icons.music_note),
              label: const Text('Open Spotify'),
            ),
            const SizedBox(height: 16),
            if (_status != null)
              Text(
                _status!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
