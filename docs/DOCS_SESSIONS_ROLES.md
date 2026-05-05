# Control de Dispositivos Flexibles - Spark Autoclicker

Este documento redefine cómo controlamos el uso de múltiples dispositivos sin prohibirlos, permitiendo flexibilidad al usuario pero manteniendo el control para el Administrador.

---

## 1. Concepto: "Lista Blanca" de Dispositivos
En lugar de permitir solo 1 dispositivo, el perfil de cada usuario en Firebase tendrá una lista de dispositivos autorizados.

### Estructura en Base de Datos:
```json
"users": {
  "+5491112345678": {
    "role": "driver",
    "devices": {
      "ID_TELEFONO_1": {
        "model": "Samsung S23",
        "last_login": "2026-05-03T18:00:00Z",
        "label": "Personal"
      },
      "ID_TELEFONO_2": {
        "model": "Google Pixel 7",
        "last_login": "2026-05-03T19:00:00Z",
        "label": "Tablet Trabajo"
      }
    }
  }
}
```

---

## 2. Funcionamiento del Control
1.  **Transparencia:** Cuando el usuario entra desde un dispositivo nuevo, la app lo registra automáticamente. No se le bloquea la entrada.
2.  **Visibilidad para el Admin:** En tu **Panel de Administrador**, podrás ver cuántos y qué dispositivos tiene vinculados cada conductor.
3.  **Alertas de Abuso:** Si un usuario registra 10 dispositivos en un solo día, el sistema te enviará una alerta (o marcará al usuario en rojo) para que puedas investigar si está compartiendo su cuenta comercialmente.
4.  **Gestión Remota:** Tú, como Owner, tienes un botón para "Limpiar Dispositivos". Si sospechas de algo, borras su lista y el usuario tendrá que volver a loguearse en sus equipos (obligándolo a recibir el SMS de nuevo).

---

## 3. Beneficios
*   **Mejor Experiencia:** El usuario puede usar su teléfono principal y una tablet sin fricciones.
*   **Detección de Fraude:** Puedes ver patrones sospechosos (mismo número en 5 modelos de teléfono distintos).
*   **Seguridad:** El login por SMS sigue siendo el guardián; aunque tenga 5 dispositivos, necesita el chip para activar uno nuevo.
