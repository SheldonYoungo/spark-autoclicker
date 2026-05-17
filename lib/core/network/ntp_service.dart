import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class NtpService {
  static const String primaryServer = 'time.google.com';
  static const String fallbackServer = 'pool.ntp.org';

  /// Obtiene la hora actual desde servidores NTP.
  /// Devuelve la hora de la red si es posible, de lo contrario la hora local (con advertencia).
  static Future<DateTime> getNetworkTime() async {
    try {
      return await _fetchNtpTime(primaryServer);
    } catch (e) {
      debugPrint('NTP Primary failed: $e. Trying fallback...');
      try {
        return await _fetchNtpTime(fallbackServer);
      } catch (e2) {
        debugPrint('NTP Fallback failed: $e2. Using local time (Unsafe).');
        return DateTime.now();
      }
    }
  }

  static Future<DateTime> _fetchNtpTime(String server) async {
    final List<int> ntpData = List<int>.filled(48, 0);
    ntpData[0] = 0x1B; // LI = 0 (no warning), VN = 3 (IPv4 only), Mode = 3 (Client)

    final RawDatagramSocket socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final InternetAddress address = (await InternetAddress.lookup(server)).first;
    
    socket.send(ntpData, address, 123);
    
    final Completer<DateTime> completer = Completer<DateTime>();
    
    socket.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final Datagram? dg = socket.receive();
        if (dg != null && dg.data.length >= 48) {
          final int secondsSince1900 = _parseTimestamp(dg.data, 40);
          final DateTime networkTime = DateTime.fromMillisecondsSinceEpoch(
            (secondsSince1900 - 2208988800) * 1000,
            isUtc: true,
          );
          completer.complete(networkTime.toLocal());
          socket.close();
        }
      }
    });

    return completer.future.timeout(const Duration(seconds: 4), onTimeout: () {
      socket.close();
      throw Exception('NTP Timeout');
    });
  }

  static int _parseTimestamp(Uint8List data, int offset) {
    return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
  }
}
