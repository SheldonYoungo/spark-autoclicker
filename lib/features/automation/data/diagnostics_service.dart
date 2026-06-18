import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'activation_service.dart';
import 'filter_service.dart';

class DiagnosticsService {
  static final DiagnosticsService _instance = DiagnosticsService._();
  factory DiagnosticsService() => _instance;
  DiagnosticsService._();

  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final Map<String, dynamic> _data = {};
  bool _initialized = false;
  String? _deviceId;

  void init() {
    if (_initialized) return;
    _initialized = true;
    Timer.periodic(const Duration(seconds: 15), (_) => flush());
    _collectDeviceInfo();
    _collectFilterConfig();
  }

  Future<void> _collectDeviceInfo() async {
    try {
      _deviceId = await ActivationService().getDeviceId();
      _data['device_id'] = _deviceId;
    } catch (e) {
      _data['device_id'] = 'unknown';
    }
  }

  Future<void> _collectFilterConfig() async {
    try {
      final filters = FilterService().filtersNotifier.value;
      _data['filter_config'] = {
        'storeCode': filters.storeCode ?? '(none)',
        'maxDistance': filters.maxDistance,
        'minPay': filters.minPay,
        'maxPay': filters.maxPay,
        'orderTypes': filters.orderTypes,
        'speedMultiplier': filters.speedMultiplier,
        'scanSpeed': filters.scanSpeed,
      };
    } catch (e) {
      _data['filter_config'] = 'error: $e';
    }
  }

  void set(String key, dynamic value) {
    _data[key] = value;
    if (key == 'scan_result' || key == 'accept_result' || key == 'rejection_reason') {
      flush();
    }
  }

  Future<void> flush() async {
    try {
      if (_deviceId == null) await _collectDeviceInfo();
      final safeId = (_deviceId ?? 'unknown').replaceAll(RegExp(r'[.#$\[\]]'), '_');

      if (_data.containsKey('filter_config') == false) {
        _collectFilterConfig();
      }

      await _db.ref('health_check/diagnostics/$safeId/latest').update({
        ..._data,
        'timestamp': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint("DiagnosticsService: Error uploading: $e");
    }
  }

  void onNativeLog(String message) {
    if (!message.startsWith('DIAG:')) return;
    final payload = message.substring(5).trim();

    try {
      final parsed = jsonDecode(payload);
      if (parsed is Map) {
        for (final entry in parsed.entries) {
          set(entry.key.toString(), entry.value);
        }
      }
    } catch (_) {
      final eqIdx = payload.indexOf('=');
      if (eqIdx > 0) {
        final key = payload.substring(0, eqIdx).trim();
        final value = payload.substring(eqIdx + 1).trim();
        set(key, value);
      }
    }
  }
}
