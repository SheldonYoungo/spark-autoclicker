# Conexión Técnica de Firebase - Spark Autoclicker

Este documento explica cómo hemos "conectado" la aplicación con la nube de Google Firebase.

---

## 1. El Motor de Inicio (`lib/main.dart`)
He modificado el punto de entrada de la app para que, nada más abrirse, haga tres cosas:
1.  **Despertar a Flutter:** Asegurarse de que el motor gráfico esté listo.
2.  **Cargar Secretos:** Leer el archivo `.env` (donde irán tus llaves privadas).
3.  **Encender Firebase:** Intentar conectar con tu proyecto en la nube.

---

## 2. El Servicio de Autenticación (`lib/features/admin/data/auth_service.dart`)
Este es el archivo que hace el "trabajo sucio" del login. Contiene dos funciones principales:

### A. `verifyPhone` (Enviar el SMS)
Esta función le dice a Firebase: *"Oye, este número quiere entrar, mándale un código de 6 dígitos por SMS"*.

### B. `signInWithCode` (Validar y Filtrar)
Esta es la parte más importante. Cuando el usuario pone el código de 6 dígitos:
1.  **Valida el SMS:** Verifica que el código sea correcto.
2.  **Consulta la Lista VIP:** Entra a tu base de datos y busca ese número de teléfono.
3.  **Decisión Final:** 
    *   Si el número está en tu base de datos y Sheldon le dio permiso: **Entra.**
    *   Si el número NO está registrado por ti: **Lo expulsa automáticamente** y le muestra un error.

---

## 3. ¿Qué falta para que funcione?
Como mencionamos antes, el código ya tiene los "cables" puestos, pero falta la "corriente":
*   **Archivo `google-services.json`:** Debe estar en `android/app/`.
*   **Habilitar SMS en Firebase:** Debes activar el método "Phone" en la consola de Firebase.

---
*Nota: Este sistema garantiza que nadie que no haya sido registrado por ti en el Panel de Admin pueda siquiera ver la pantalla principal del bot.*
