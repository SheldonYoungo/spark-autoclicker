import 'dart:ui' as ui;
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../features/overlay/presentation/overlay_sizes.dart';

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

        final density = ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1.0;
        final pxSize = (OverlaySizes.collapsedWindow * density).round();

        debugPrint("Iniciando FlutterOverlayWindow.showOverlay en px: $pxSize (dp: ${OverlaySizes.collapsedWindow})...");
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true, 
          overlayTitle: "INIBOT",
          overlayContent: "Bot de Spark Activo",
          flag: OverlayFlag.defaultFlag, 
          visibility: NotificationVisibility.visibilityPublic,
          positionGravity: PositionGravity.auto,
          alignment: OverlayAlignment.centerRight,
          width: pxSize,
          height: pxSize,
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
