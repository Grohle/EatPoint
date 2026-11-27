# Hogar compartido con Google Drive

EatPoint puede sincronizar el hogar (menús, lista de la compra, registros que
compartís) a través de una carpeta de **tu** Google Drive. Los datos se cifran
en el móvil antes de subirse: Google solo ve ficheros `*.json.enc` ilegibles.

Google exige que cada app que usa Drive tenga un "cliente OAuth" registrado.
Como EatPoint no tiene servidor propio, ese registro lo hace una vez quien
compila la app (o cualquier miembro del hogar). Son unos 10 minutos.

## 1. Crear el proyecto y activar la API de Drive

1. Entra en <https://console.cloud.google.com/> con tu cuenta de Google.
2. Arriba, **Seleccionar proyecto → Proyecto nuevo**. Nombre: `EatPoint`. Crear.
3. Menú **APIs y servicios → Biblioteca**, busca **Google Drive API** y pulsa
   **Habilitar**.

## 2. Pantalla de consentimiento

1. **APIs y servicios → Pantalla de consentimiento de OAuth** (o
   **Google Auth Platform → Branding**).
2. Tipo de usuario: **Externo**. Nombre de la app: `EatPoint`. Correo de
   asistencia y de contacto: el tuyo.
3. En **Acceso a datos / Permisos**, añade el permiso
   `https://www.googleapis.com/auth/drive`.
4. En **Público / Usuarios de prueba**, añade el correo de Google de **cada
   miembro del hogar** (el tuyo también).
5. Deja la app en estado **Prueba (Testing)**. No hace falta publicarla ni
   pasar la verificación de Google mientras solo la uséis los usuarios de
   prueba (hasta 100).

> En modo Prueba Google puede pedir volver a iniciar sesión cada 7 días. En
> EatPoint basta con pulsar **Volver a conectar con Google** en la pantalla
> del hogar.

## 3. Cliente OAuth de Android

**APIs y servicios → Credenciales → Crear credenciales → ID de cliente de
OAuth**:

| Campo | Valor |
|---|---|
| Tipo de aplicación | Android |
| Nombre | `EatPoint Android` |
| Nombre del paquete | `io.github.grohle.eatpoint` |
| Huella SHA-1 | ver abajo |

Para las APK publicadas en las
[releases de EatPoint](https://github.com/Grohle/EatPoint/releases), la huella
del certificado de firma es:

```
AD:2C:BC:7F:C5:7D:C0:2A:1F:C5:83:68:E4:82:0A:70:3C:9D:98:17
```

Si compilas tú la app con otra clave, saca su huella con:

```bash
keytool -list -v -keystore tu-clave.jks -alias tu-alias
```

Este cliente no tiene "secreto" ni hay que copiar nada de él: Google lo
reconoce por el paquete y la huella.

## 4. Cliente OAuth web

Otra vez **Crear credenciales → ID de cliente de OAuth**:

| Campo | Valor |
|---|---|
| Tipo de aplicación | Aplicación web |
| Nombre | `EatPoint web` |

No rellenes orígenes ni URIs de redirección. Al crearlo verás un **ID de
cliente** del estilo `123456789-abc…apps.googleusercontent.com`. **Ese es el
dato que necesita EatPoint.** (El "secreto de cliente" no se usa: no lo
compartas.)

## 5. En la app

1. **Ajustes → Compartir y sincronizar**, escribe tu nombre y pulsa **Crear un
   hogar**.
2. Elige **Google Drive**. Pega el ID de cliente web si no aparece ya
   rellenado.
3. Pulsa **Iniciar sesión con Google** y acepta el permiso de Drive.
4. En **Compartir con**, escribe el correo de Google de los demás miembros
   (separados por comas). EatPoint crea la carpeta **Hogar EatPoint** en tu
   Drive y se la comparte con ellos.
5. Pulsa **Probar y crear**. Después, **Invitar con QR** muestra el código.
6. Cada miembro abre **Compartir y sincronizar**, escribe su nombre, pulsa
   **Unirme con un código QR**, escanea el QR e inicia
   sesión con la cuenta de Google con la que compartiste la carpeta.

El ID de cliente viaja dentro del QR, así que los demás no tienen que pegarlo.

## Para quien publica releases

Si guardas el ID de cliente web como variable del repositorio
`EATPOINT_GOOGLE_WEB_CLIENT_ID` (**Settings → Secrets and variables →
Actions → Variables**), el flujo de release lo incluye en la APK y nadie tiene
que pegarlo. No es un secreto: identifica la app, no da acceso a nada por sí
solo.

## Problemas frecuentes

| Mensaje | Causa probable |
|---|---|
| Error 10 / `DEVELOPER_ERROR` | El paquete o la huella SHA-1 del cliente Android no coinciden con la APK instalada. |
| "Acceso bloqueado: la app no ha completado la verificación" | Ese correo no está en los usuarios de prueba. |
| La prueba de conexión dice que no se puede escribir | La carpeta no está compartida como **Editor** con ese miembro. |
| Pide iniciar sesión a menudo | Normal en modo Prueba (cada 7 días). Usa **Volver a conectar con Google**. |
