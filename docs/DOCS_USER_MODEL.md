# Implementación del Modelo de Usuario - Spark Autoclicker

Este documento explica el "cerebro" de los datos que acabamos de crear en el código.

---

## 1. El "Molde" del Usuario (`UserModel`)
He creado un archivo que define exactamente qué información necesitamos de cada persona para que la app funcione. Piensa en esto como la ficha técnica de cada conductor.

### Campos incluidos:
*   **Rol (`UserRole`):** Define si es `admin` (tú) o `driver` (conductor).
*   **Estado (`UserStatus`):** Puede estar `active` (trabajando), `inactive` (bloqueado) o `pending` (recién registrado).
*   **Fecha de Expiración:** La app ahora sabe comparar la fecha actual con esta fecha para decidir si deja entrar al usuario o no.
*   **Lista de Dispositivos (`devices`):** Aquí guardamos la "huella" de cada teléfono que el usuario use.

---

## 2. Lógica Inteligente
El código ahora puede responder estas preguntas automáticamente:
1.  **¿Está activo? (`isActive`):** Revisa si el estado es "active" Y si la fecha de hoy es antes de la de vencimiento.
2.  **¿Es el jefe? (`isAdmin`):** Revisa si el rol es de administrador para mostrarte el panel especial.

---

## 3. ¿Por qué es importante?
Este modelo es lo que permite que la base de datos de Firebase y tu app en Flutter hablen el mismo idioma. Sin este "traductor", no podríamos controlar quién paga y quién no.

---

## Próximos Pasos
Ahora que la app "entiende" qué es un usuario, podemos proceder a:
*   Crear el **Servicio de Autenticación** para que el login por SMS realmente empiece a funcionar.
*   Diseñar la pantalla de **Login** en Flutter con los colores de Figma.
