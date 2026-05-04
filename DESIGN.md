# Documentación de Diseño - Spark Autoclicker

Este documento detalla los lineamientos visuales, componentes de interfaz y reglas de experiencia de usuario (UX) para el proyecto Spark Autoclicker, basados en el diseño oficial en Figma y los requerimientos técnicos.

---

## 1. Identidad Visual

### Paleta de Colores
*   **Fondo Principal (Background):** `#020e21` (Azul profundo/oscuro).
*   **Color Primario (Destacados):** `#ffe816` (Amarillo Spark). Utilizado para el título principal e íconos de estado.
*   **Color Secundario (Descripciones):** `#00d9f7` (Cian brillante). Utilizado para textos de ayuda y valores secundarios.
*   **Color de Borde:** `#0043aa` (Azul corporativo). Utilizado en bordes de tarjetas y contenedores.
*   **Texto Principal:** `#ffffff` (Blanco).
*   **Texto Desactivado/Pie:** `rgba(255, 255, 255, 0.2)` (Blanco con 20% opacidad).

### Tipografía
*   **Fuente Principal:** Inter (Sans-serif) y SF Pro Text (para elementos del sistema operativo como el subheadline).
*   **Títulos de Pantalla:** 32px, Bold, Tracking -0.5px.
*   **Títulos de Tarjetas:** 14px, Regular, Blanco.
*   **Descripciones de Tarjetas:** 12px, Regular, Color `#00d9f7`.
*   **Cuerpo de Texto:** 14px, Regular, Blanco.
*   **Énfasis:** 14px, Bold Italic (usado en resúmenes de configuración).

---

## 2. Componentes de la Interfaz

### 2.1 Panel de Configuración (App Principal)
*   **Hero Card (INIBOT):** Tarjeta superior con gradiente radial (Azul a Negro) y borde azul. Muestra el estado actual y el tipo de orden seleccionado.
*   **Tarjetas de Filtro (Grid 2x2):**
    *   **Código de Walmart:** Entrada para ID de tienda (ej: #7178).
    *   **Distancia:** Control para establecer el radio máximo de búsqueda en millas.
    *   **Orden:** Selector para tipos de servicio (Compras, Recolección).
    *   **Tarifa:** Selector de monto mínimo por hora (USD).
*   **Impulso de Velocidad IA:** Tarjeta horizontal para configurar la frecuencia de escaneo (1x, 1.5x, 2x, 3x).

### 2.2 Ventana Flotante (Overlay)
*   **Diseño:** Contenedor con esquinas redondeadas (24px), fondo semi-transparente oscuro y borde azul.
*   **Estados:**
    *   **Configuración Pendiente:** Muestra mensaje de advertencia y botón "Ir a Configurar".
    *   **Confirmación:** Lista los criterios seleccionados antes de iniciar.
    *   **Activo:** Muestra el bot en funcionamiento con opción de "Detener".
*   **Interacción:** Debe poder moverse por la pantalla sin obstruir elementos críticos de la app Spark.

### 2.3 Modales y Diálogos
*   **Estructura:** Fondo desenfocado (Blur), tarjeta central blanca/oscura con título, descripción clara del parámetro y botones de "Cancelar" (sin relleno) y "Confirmar" (con borde/relleno).

---

## 3. Reglas de UX y Negocio

### Lógica de Filtrado (Accesibilidad)
El bot utiliza el `AccessibilityService` para buscar los siguientes patrones en la pantalla de Spark:
1.  **Monto ($):** Debe ser igual o mayor a la **Tarifa** configurada.
2.  **Distancia (miles):** Debe ser menor o igual a las **Millas** configuradas.
3.  **Tienda (#):** Debe coincidir exactamente con el **Código de Walmart** (si se configuró).
4.  **Tipo de Orden:** Coincidencia de texto exacto con "Compras" o "Recolección".

### Simulación Humana (Anti-Ban)
*   **Modo Invisible:** Los clics no son instantáneos; incluyen retrasos aleatorios y variaciones en las coordenadas del toque para simular un dedo humano.
*   **Velocidad IA:** Controla la frecuencia con la que el servicio de accesibilidad inspecciona los nodos de la pantalla.

### Gestión de Accesos (Owner)
*   La UI de administración permite al propietario habilitar/deshabilitar conductores mediante un interruptor (switch) vinculado a Firebase Realtime Database.
*   Las suscripciones se validan contra la fecha del servidor para evitar trampas con el reloj local del dispositivo.

---

## 4. Estados de la Aplicación
1.  **Loading:** Pantalla con logo de Spark y spinner de carga centrado.
2.  **Auth (SMS):** Pantalla limpia con 4 campos de entrada para el código de verificación.
3.  **Main:** Panel de control con todas las tarjetas de configuración.
4.  **Overlay:** Burbuja flotante activa sobre Spark.

---
*Nota: Este diseño debe implementarse siguiendo la **Vertical Slice Architecture**, manteniendo la lógica de UI en Flutter y la lógica de interacción en Kotlin nativo.*