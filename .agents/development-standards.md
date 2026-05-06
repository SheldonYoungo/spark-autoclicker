# SKILL: Estándares de Desarrollo - Spark Autoclicker

## Objetivo
Asegurar que todos los sub-agentes (@UI-Dev, @Core-Dev, @Logic-Dev) generen código de alta calidad, modular, eficiente y alineado con los objetivos del proyecto Spark Autoclicker.

## 1. Estándares Generales (Mandatorios para todos)
- **Soluciones Directas:** Evitar introducciones largas. El código debe ser la respuesta principal.
- **Modularidad:** Separar la lógica de negocio de la interfaz y de los servicios nativos.
- **Cero Fricción (Zero Floats):** Código optimizado para velocidad y bajo consumo de batería.
- **Documentación Proactiva:** Usar `mem_save` de Engram para registrar cada decisión técnica importante.

## 2. @UI-Dev (Flutter & UX)
- **Figma First:** Antes de cualquier cambio visual, consultar el MCP de Figma (`6niorSGDgXNUqlsLMh7aUs`).
- **Rendimiento:** Evitar reconstrucciones innecesarias (`const` constructors, `RepaintBoundary` en listas pesadas).
- **Estilo:** Seguir el `AppTheme` definido en `lib/core/theme/app_theme.dart`.

## 3. @Core-Dev (Android Nativo & Kotlin)
- **AccessibilityService:** Mantener el servicio lo más liviano posible. Solo lectura de nodos y ejecución de gestos.
- **MethodChannels:** Usar nombres claros y consistentes para los canales (ej: `com.spark.autoclicker/core`).
- **Seguridad:** No procesar lógica de negocio en Kotlin; recibir órdenes explícitas desde Dart.

## 4. @Logic-Dev (Firebase & Arquitectura)
- **Zero Cost Optimization:** Estructuras de datos en Realtime Database que minimicen el uso de datos.
- **Seguridad:** Validar tiempos de suscripción mediante servidores NTP externos, no confiar en el reloj local.
- **Integridad:** Validar que los Device IDs estén correctamente vinculados a los Slots antes de autorizar el bot.

## Flujo de Trabajo
1. **Investigar:** Consultar MCPs (NotebookLM/Figma) y Memoria (Engram).
2. **Implementar:** Aplicar cambios siguiendo estos estándares.
3. **Validar:** Realizar pruebas de integración y verificar linting.
4. **Persistir:** Guardar aprendizajes en Engram.
