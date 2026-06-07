import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class NtpService {
  static const String primaryServer = 'time.google.com';
  static const String fallbackServer = 'pool.ntp.org';

  /// Obtiene la hora actual desde servidores NTP.
  /// Lanza una excepción si falla para evitar bypass de seguridad con la hora local.
  static Future<DateTime> getNetworkTime() async {
    try {
      return await _fetchNtpTime(primaryServer);
    } catch (e) {
      debugPrint('NTP Primary failed: $e. Trying fallback...');
      try {
        return await _fetchNtpTime(fallbackServer);
      } catch (e2) {
        debugPrint('NTP Fallback failed: $e2. Security breach blocked.');
        throw Exception('SECURITY_CLOCK_ERROR: No se pudo validar la hora de red.');
      }
    }
  }

  static Future<DateTime> _fetchNtpTime(String server) async {
    final List<int> ntpData = List<int>.filled(48, 0);
    ntpData[0] = 0x1B; // LI = 0, VN = 3, Mode = 3

    RawDatagramSocket? socket;
    try {
      final addresses = await InternetAddress.lookup(server);
      if (addresses.isEmpty) throw Exception('Address not found');
      
      final InternetAddress address = addresses.first;
      socket = await RawDatagramSocket.bind(
        address.type == InternetAddressType.IPv6 
            ? InternetAddress.anyIPv6 
            : InternetAddress.anyIPv4, 
        0
      );
      
      socket.send(ntpData, address, 123);
      
      final Completer<DateTime> completer = Completer<DateTime>();
      
      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? dg = socket?.receive();
          if (dg != null && dg.data.length >= 48) {
            final int secondsSince1900 = _parseTimestamp(dg.data, 40);
            final DateTime networkTime = DateTime.fromMillisecondsSinceEpoch(
              (secondsSince1900 - 2208988800) * 1000,
              isUtc: true,
            );
            if (!completer.isCompleted) completer.complete(networkTime.toLocal());
          }
        }
      }, onError: (e) {
        debugPrint("NTP Socket async error: $e");
        if (!completer.isCompleted) completer.completeError(e);
      });

      return await completer.future.timeout(const Duration(milliseconds: 5000));
    } finally {
      socket?.close();
    }
  }

  static int _parseTimestamp(Uint8List data, int offset) {
    // Unsigned 32-bit integer to avoid negative values on high timestamps
    return (data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
  }
}
