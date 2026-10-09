import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opendeck/features/device/providers/device_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A deck on the Wi-Fi port. The first connection drops in the middle of an
/// upload; later ones work.
class _FakeDeck {
  late final ServerSocket server;
  int connections = 0;
  int commits = 0;

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 7777);
    server.listen((s) {
      final n = ++connections;
      var dataLines = 0;
      s.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final m = jsonDecode(line) as Map<String, dynamic>;
        void send(Map<String, dynamic> r) => s.write('${jsonEncode(r)}\n');
        switch (m['t']) {
          case 'hello':
            send({'t': 'hello', 'fw': 'test', 'w': 320, 'h': 480, 'fs_total': 8 << 20, 'fs_used': 0, 'pages': 1});
          case 'data':
            if (n == 1 && ++dataLines == 2) {
              s.destroy();
              return;
            }
            send({'t': 'ok'});
          case 'commit':
            commits++;
            send({'t': 'ok'});
          case 'ping':
            send({'t': 'pong'});
          default:
            send({'t': 'ok'});
        }
      }, onError: (_) {});
    });
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a sync whose link drops reconnects and finishes', () async {
    SharedPreferences.setMockInitialValues({});
    final deck = _FakeDeck();
    await deck.start();
    final container = ProviderContainer();
    addTearDown(() async {
      container.dispose();
      await deck.server.close();
    });
    final device = container.read(deviceProvider.notifier);
    await device.connectTcp('127.0.0.1');
    expect(container.read(deviceProvider).connected, isTrue);

    final compiled = await device.sync().timeout(const Duration(seconds: 60));
    expect(compiled, isNotNull);
    expect(deck.connections, 2);
    expect(deck.commits, 1);
    final st = container.read(deviceProvider);
    expect(st.connected, isTrue);
    expect(st.syncing, isFalse);
    expect(st.error, isNull);
  });
}
