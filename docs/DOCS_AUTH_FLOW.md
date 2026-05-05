# Flujo de Usuario y Autenticación - Spark Autoclicker

Este documento detalla el proceso paso a paso de cómo un usuario entra al sistema, basado en las reglas de negocio y Firebase.

---

## 1. El Registro (Lado Administrador)
Como tú eres el "Owner", el proceso nace de ti:
1.  **Captura de Datos:** En tu Panel de Admin, ingresas el número de teléfono del conductor (ej: +54 9 11 ...).
2.  **Creación en Base de Datos:** Al darle "Guardar", se crea un registro en **Firebase Realtime Database**:
    ```json
    "users": {
      "+5491112345678": {
        "status": "active",
        "expiration_date": "2026-06-03T00:00:00Z",
        "is_admin": false
      }
    }
    ```
3.  **Resultado:** El usuario ya existe para el sistema, pero aún no se ha "identificado" en su teléfono.

---

## 2. El Login por SMS (Lado Conductor)
Cuando el conductor descarga la app, el flujo es el siguiente:
1.  **Ingreso de Teléfono:** El usuario pone su número.
2.  **Envío de SMS (Firebase Auth):** Firebase envía un mensaje de texto con un código de 6 dígitos (OTP) al celular del conductor.
3.  **Verificación:** El usuario ingresa los 6 dígitos. Firebase confirma que el dueño del chip es quien dice ser.
4.  **Validación de Acceso:** 
    *   La app toma ese número verificado y consulta en tu base de datos (paso 1).
    *   **Si existe y está activo:** Entra al panel del Autoclicker.
    *   **Si no existe o está vencido:** Muestra un mensaje: "Acceso no autorizado. Contacta al administrador".

---

## 3. Seguridad y Ventajas
*   **Identidad Real:** No hay contraseñas que se puedan olvidar o robar. El login está amarrado al número de teléfono/chip.
*   **Control Total:** Si un conductor no te paga o se porta mal, cambias su `status` a `inactive` en tu panel y, en menos de 1 segundo, su bot deja de funcionar, aunque tenga la sesión iniciada.
*   **Sin Fricción:** El usuario no tiene que llenar formularios largos.

---

## Próximos Pasos Técnicos
Para implementar esto, necesitamos:
1.  **Configurar Firebase Console:** Habilitar el método "Phone" en la sección de Authentication.
2.  **Crear el Data Model en Flutter:** Definir cómo se ve un "Usuario" en el código.
3.  **Integrar el Plugin de SMS:** Configurar `firebase_auth` para manejar el envío y recepción del código.
