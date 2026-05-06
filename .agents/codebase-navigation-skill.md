# SKILL: Navegación de Codebase - Spark Autoclicker

## Objetivo
Optimizar la exploración y comprensión del proyecto para reducir el consumo de tokens y acelerar la resolución de tareas.

## Estructura del Proyecto
- `lib/core/`: Componentes transversales (Temas, Red, Utils).
- `lib/features/`: Lógica por funcionalidad (Admin, Automation, Overlay).
- `android/`: Motor nativo (Kotlin, Accessibility Service).
- `docs/`: Documentación técnica y reglas de negocio.

## Reglas de Navegación
1. **Búsqueda Quirúrgica:** Usar `grep_search` con patrones específicos antes de leer archivos completos.
2. **Contexto Primero:** Leer `docs/access_control_system.md` antes de modificar lógica de autenticación.
3. **Validación Cruzada:** Al modificar `MethodChannels` en Kotlin, verificar siempre su contraparte en Dart (`lib/features/automation/`).

## Herramientas Preferidas
- **Engram:** Consultar `mem_search` para evitar repetir errores pasados.
- **Figma:** Usar `get_design_context` para obtener especificaciones exactas de componentes UI.
