import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'deck_client.dart';

class DiscoveredDeck {
  const DiscoveredDeck({required this.host, required this.port, required this.info});
  final String host;
  final int port;
  final DeviceInfo info;
}

/// Finds decks on the local network: UDP broadcast "OPENDECK?" to port 7778,
/// each deck answers with its hello JSON.
class DeckDiscovery {
  static const _probePort = 7778;

  static Future<List<DiscoveredDeck>> scan({Duration timeout = const Duration(milliseconds: 1500)}) async {
    final found = <String, DiscoveredDeck>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      sock.broadcastEnabled = true;
      final s = sock;
      s.listen((e) {
        if (e != RawSocketEvent.read) return;
        final d = s.receive();
        if (d == null) return;
        try {
          final j = (jsonDecode(utf8.decode(d.data, allowMalformed: true)) as Map).cast<String, dynamic>();
          if (j['t'] != 'hello') return;
          final host = d.address.address;
          found[host] = DiscoveredDeck(
            host: host,
            port: (j['port'] as num?)?.toInt() ?? 7777,
            info: DeviceInfo.fromJson(j),
          );
        } catch (_) {}
      });
      final probe = ascii.encode('OPENDECK?');
      void send() {
        for (final addr in ['255.255.255.255', '192.168.4.1']) {
          try {
            s.send(probe, InternetAddress(addr), _probePort);
          } catch (_) {}
        }
      }

      send();
      final step = timeout ~/ 3;
      await Future<void>.delayed(step);
      send();
      await Future<void>.delayed(step);
      send();
      await Future<void>.delayed(timeout - step * 2);
    } catch (_) {
      // return whatever was found
    } finally {
      sock?.close();
    }
    return found.values.toList();
  }
}
