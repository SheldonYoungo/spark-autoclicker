import 'package:firebase_database/firebase_database.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../../../core/network/ntp_service.dart';
import '../../admin/domain/user_model.dart';
import 'filter_service.dart';
import '../../../core/utils/overlay_util.dart';

class ActivationService {
  final FirebaseDatabase _db = FirebaseDatabase.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static const String _keyLinkedUid = 'linked_uid';
  static const String _keyExpiration = 'auth_expiration_ts';
  static const String _keyStatus = 'auth_status';

  static final ValueNotifier<String?> linkedUidNotifier = ValueNotifier<String?>(null);
  static final ValueNotifier<DateTime?> expirationDateNotifier = ValueNotifier<DateTime?>(null);
  static final ValueNotifier<bool> showExpiredBanner = ValueNotifier<bool>(false);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    linkedUidNotifier.value = prefs.getString(_keyLinkedUid);
    final expTs = prefs.getInt(_keyExpiration);
    if (expTs != null) {
      expirationDateNotifier.value = DateTime.fromMillisecondsSinceEpoch(expTs);
    }
  }

  Future<String> getDeviceId() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      return androidInfo.id;
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      return iosInfo.identifierForVendor ?? 'unknown_ios';
    }
    return 'unknown_platform';
  }

  Future<bool> _isExpired(DateTime expirationDate) async {
    try {
      final now = await NtpService.getNetworkTime();
      return now.isAfter(expirationDate);
    } catch (e) {
      // Si falla el NTP, por seguridad asumimos que no podemos validar y por ende bloqueamos
      debugPrint("ActivationService: Error validando expiración vía NTP: $e");
      return true; 
    }
  }

  Future<void> _saveAuthDataLocally(UserModel user, String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLinkedUid, uid);
    await prefs.setInt(_keyExpiration, user.expirationDate.millisecondsSinceEpoch);
    await prefs.setString(_keyStatus, user.status.name);
    linkedUidNotifier.value = uid;
    expirationDateNotifier.value = user.expirationDate;
  }

  Future<String?> activateKey(String uid, String key) async {
    try {
      final currentDeviceId = await getDeviceId();
      final userRef = _db.ref('users/$uid');
      
      // Primera lectura rápida para validar expiración vía NTP (No soportado de forma asíncrona dentro de la transacción pura de Firebase)
      final preSnap = await userRef.get();
      if (!preSnap.exists) return 'Usuario no encontrado.';
      
      final preUser = UserModel.fromJson(Map<String, dynamic>.from(preSnap.value as Map));
      if (preUser.activationKey != key) {
        return 'La llave de activación es incorrecta.';
      }
      if (await _isExpired(preUser.expirationDate)) {
        return 'Suscripción expirada o error de red (NTP).';
      }

      String? errorMsg;
      UserModel? finalUser;

      final transactionResult = await userRef.runTransaction((Object? postData) {
        if (postData == null) return Transaction.abort();

        final Map<String, dynamic> data = Map<String, dynamic>.from(postData as Map);
        final user = UserModel.fromJson(data);

        // Dispositivo ya registrado
        if (user.authorizedDeviceIds.contains(currentDeviceId)) {
          if (user.status == UserStatus.pending) {
            data['status'] = UserStatus.active.name;
          }
          finalUser = UserModel.fromJson(data);
          return Transaction.success(data);
        }

        // Límite alcanzado
        if (!user.hasAvailableSlots) {
          errorMsg = 'Has alcanzado el límite de dispositivos (${user.maxSlots}).';
          return Transaction.abort();
        }

        // Añadir dispositivo al slot
        final updatedDeviceIds = List<String>.from(user.authorizedDeviceIds)..add(currentDeviceId);
        data['authorizedDeviceIds'] = updatedDeviceIds;
        data['status'] = UserStatus.active.name;
        
        // Limpiar llave SOLO si los slots están llenos
        if (updatedDeviceIds.length >= user.maxSlots) {
          data['activationKey'] = null;
        }

        finalUser = UserModel.fromJson(data);
        return Transaction.success(data);
      });

      if (transactionResult.committed && finalUser != null) {
        await _saveAuthDataLocally(finalUser!, uid);
        showExpiredBanner.value = false;
        return null; // Éxito
      } else {
        return errorMsg ?? 'Error de concurrencia al activar la llave. Intenta de nuevo.';
      }
    } catch (e) {
      debugPrint("ActivationService: Error en activateKey: $e");
      return 'Error de conexión con el servidor.';
    }
  }

  Future<String?> activateDeviceWithKeyOnly(String key, String deviceId) async {
    if (key == '9999') return 'Acceso administrativo requerido.';

    try {
      final keySnapshot = await _db.ref('activation_keys/$key').get().timeout(const Duration(seconds: 10));
      if (!keySnapshot.exists) return 'La llave es incorrecta o ya fue usada.';

      final keyData = Map<String, dynamic>.from(keySnapshot.value as Map);
      final String uid = keyData['uid'];

      final userSnapshot = await _db.ref('users/$uid').get().timeout(const Duration(seconds: 10));
      if (!userSnapshot.exists) return 'Error interno: Usuario no encontrado.';

      final user = UserModel.fromJson(Map<String, dynamic>.from(userSnapshot.value as Map));

      if (await _isExpired(user.expirationDate)) {
        return 'Suscripción expirada o error de red (NTP).';
      }

      List<String> updatedDeviceIds = List<String>.from(user.authorizedDeviceIds);
      if (!updatedDeviceIds.contains(deviceId)) {
        if (!user.hasAvailableSlots) return 'Has alcanzado el límite de dispositivos (${user.maxSlots}).';
        updatedDeviceIds.add(deviceId);
      }

      await _db.ref('users/$uid').update({
        'status': UserStatus.active.name,
        'authorizedDeviceIds': updatedDeviceIds,
      });

      await _saveAuthDataLocally(user, uid);
      showExpiredBanner.value = false;
      return null;
    } catch (e) {
      return 'Error: ${e.toString().split(':').last.trim()}';
    }
  }

  Future<bool> isCurrentDeviceAuthorized() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = prefs.getString(_keyLinkedUid);
      if (uid == null) return false;

      final deviceId = await getDeviceId();
      final snapshot = await _db.ref('users/$uid').get().timeout(const Duration(seconds: 5));
      if (!snapshot.exists) return false;

      final user = UserModel.fromJson(Map<String, dynamic>.from(snapshot.value as Map));
      
      final bool expired = await _isExpired(user.expirationDate);
      final isValid = user.role == UserRole.driver && 
             user.authorizedDeviceIds.contains(deviceId) && 
             user.isActive &&
             !expired;

      if (!isValid) {
        if (expired) showExpiredBanner.value = true;
        await clearLocalLink();
      } else {
        await _saveAuthDataLocally(user, uid);
      }
      
      return isValid;
    } catch (e) {
      debugPrint("Error validando hardware: $e");
      return false;
    }
  }

  Stream<bool> authStateStream(String uid) async* {
    final deviceId = await getDeviceId();
    
    yield* _db.ref('users/$uid').onValue.asyncMap((event) async {
      if (!event.snapshot.exists) return false;
      
      try {
        final user = UserModel.fromJson(Map<String, dynamic>.from(event.snapshot.value as Map));
        final bool expired = await _isExpired(user.expirationDate);
        
        final isValid = user.role == UserRole.driver && 
               user.authorizedDeviceIds.contains(deviceId) && 
               user.isActive &&
               !expired;

        if (!isValid) {
          if (expired) showExpiredBanner.value = true;
          await clearLocalLink();
        } else {
          await _saveAuthDataLocally(user, uid);
        }
        return isValid;
      } catch (e) {
        return false;
      }
    });
  }

  Future<void> clearLocalLink() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLinkedUid);
    await prefs.remove(_keyExpiration);
    await prefs.remove(_keyStatus);
    linkedUidNotifier.value = null;
    expirationDateNotifier.value = null;
    
    // Kill Switch: Forzar apagado del bot y cierre de overlay
    try {
      final filterService = FilterService();
      if (filterService.isBotActiveNotifier.value) {
        await filterService.toggleBot(false);
      }
      OverlayUtil.closeOverlay();
    } catch (e) {
      debugPrint("ActivationService: Error ejecutando Kill Switch: $e");
    }
  }
}
