import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class OverlayUtil {
  /// Muestra el overlay usando PositionGravity.auto para el efecto imán nativo (Messenger style)
  static Future<String?> showOverlay() async {
    try {
      bool status = await FlutterOverlayWindow.isPermissionGranted();
      
      if (!status) {
        status = await FlutterOverlayWindow.requestPermission() ?? false;
      }

      if (status) {
        if (await FlutterOverlayWindow.isActive()) {
          debugPrint("Overlay ya activo, cerrando antes de reabrir...");
          await FlutterOverlayWindow.closeOverlay();
          // Aumentamos ligeramente el delay para asegurar la disposición del motor previo
          await Future.delayed(const Duration(milliseconds: 600));
        }

        debugPrint("Iniciando FlutterOverlayWindow.showOverlay...");
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true, 
          overlayTitle: "INIBOT",
          overlayContent: "Bot de Spark Activo",
          flag: OverlayFlag.defaultFlag, 
          visibility: NotificationVisibility.visibilityPublic,
          positionGravity: PositionGravity.auto,
          alignment: OverlayAlignment.centerRight,
          width: 150,
          height: 150,
        );

        // Resetear el estado de la UI de Flutter (colapsar a burbuja)
        await FlutterOverlayWindow.shareData('reset_overlay_state');

        const MethodChannel channel = MethodChannel('com.spark.autoclicker/core');
        await channel.invokeMethod('moveToBackground');

        return null;
      } else {
        return 'Permiso de superposición denegado.';
      }
    } catch (e) {
      return 'Error al iniciar overlay: ${e.toString()}';
    }
  }

  static Future<void> closeOverlay() async {
    await FlutterOverlayWindow.closeOverlay();
  }
}
