import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter/services.dart';
import 'dart:async';

class OverlayUtil {
  /// Muestra el overlay en un cristal pequeño (150x150) para no bloquear el sistema.
  /// Activa el arrastre nativo para que el usuario pueda moverlo por toda la pantalla.
  static Future<String?> showOverlay() async {
    try {
      bool status = await FlutterOverlayWindow.isPermissionGranted();
      
      if (!status) {
        status = await FlutterOverlayWindow.requestPermission() ?? false;
      }

      if (status) {
        if (await FlutterOverlayWindow.isActive()) {
          await FlutterOverlayWindow.closeOverlay();
          await Future.delayed(const Duration(milliseconds: 200));
        }

        // LANZAMIENTO INICIAL: Ventana pequeña e interactiva
        await FlutterOverlayWindow.showOverlay(
          enableDrag: true, // Arrastre nativo fluido
          overlayTitle: "INIBOT",
          overlayContent: "Bot de Spark Activo",
          flag: OverlayFlag.defaultFlag, // Operable
          visibility: NotificationVisibility.visibilityPublic,
          positionGravity: PositionGravity.none,
          alignment: OverlayAlignment.centerRight,
          width: 150, 
          height: 150,
        );

        // SALIR DE LA APP: Minimiza automáticamente para navegar el sistema
        await SystemChannels.platform.invokeMethod('SystemNavigator.pop');

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
