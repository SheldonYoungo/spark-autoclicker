# Sistema de Control de Acceso y Gestión de Licencias

## 1. Visión General
El sistema de seguridad de Spark Autoclicker se basa en un modelo de **Control Total del Administrador**. A diferencia de los sistemas de registro abierto, este modelo requiere que cada usuario y cada dispositivo sea autorizado manualmente por el administrador antes de poder acceder a las funciones del bot.

## 2. Flujo de Activación

### Paso 1: Identificación del Hardware
Al abrir la aplicación por primera vez (o en estado no activado), la app genera un **Device ID** único basado en el hardware del teléfono.

### Paso 2: Solicitud del Usuario
El usuario debe proporcionar al administrador:
- Nombre y Teléfono.
- Comprobante de pago.
- Su **Device ID** (copiado directamente desde la pantalla de login).

### Paso 3: Registro y Generación de Llave (Admin)
El administrador, desde su panel:
1. Crea el perfil del usuario.
2. Define el número de **Slots** (dispositivos permitidos).
3. Registra el **Device ID** en uno de los slots.
4. Genera una **Llave de Activación** única.

### Paso 4: Activación Final
El usuario ingresa la **Llave de Activación** en su app. El sistema valida que:
- La llave sea correcta.
- El **Device ID** actual coincida con uno de los registrados para ese usuario.
- El estado de la licencia sea `ACTIVO` y no haya expirado.

## 3. Gestión Multi-Dispositivo (Slots)
- **Concepto:** Un usuario puede tener múltiples dispositivos autorizados (ej: un teléfono principal y uno de respaldo).
- **Control:** El administrador define cuántos slots tiene cada usuario.
- **Seguridad:** No es posible usar la app en un dispositivo cuyo ID no haya sido previamente "emparejado" por el administrador en la base de datos, incluso si se tiene la llave de activación.

## 4. Reglas de Negocio para el Admin
- **Revocación:** El administrador puede cambiar el estado a `INACTIVO` en cualquier momento, bloqueando el acceso instantáneamente en todos los dispositivos del usuario.
- **Transferencia:** Si un usuario cambia de teléfono, el administrador puede borrar un ID de hardware viejo y registrar el nuevo.
- **Vencimiento:** El sistema verifica la fecha de expiración contra la hora del servidor (NTP) para evitar manipulaciones del reloj local.

---
*Documento de referencia para la implementación técnica de AuthService y AdminPanel.*
