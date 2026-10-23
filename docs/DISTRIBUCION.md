# Publicar la app en tu sitio (sin App Store ni Google Play)

## Android: el `.apk`

1. **Crea una llave de firma** (una sola vez; guárdala bien: sin ella no podrás publicar actualizaciones):

   ```bash
   keytool -genkey -v -keystore ~/video-downloader.jks -keyalg RSA -keysize 2048 -validity 10000 -alias videodownloader
   ```

2. **Configura la firma** en `android/key.properties` (no lo subas a git):

   ```properties
   storePassword=…
   keyPassword=…
   keyAlias=videodownloader
   storeFile=/Users/marcoyamcetina/video-downloader.jks
   ```

   y en `android/app/build.gradle.kts`, dentro de `android { … }`, usa esa firma para `release`
   (la guía oficial: https://docs.flutter.dev/deployment/android#sign-the-app).

3. **Compila:** `flutter build apk --release` → `build/app/outputs/flutter-apk/app-release.apk`.

4. **Súbelo a tu sitio** y enlázalo. Quien lo instale debe permitir "Instalar apps desconocidas" para su navegador.
   Android mostrará un aviso de Play Protect; es normal en apps fuera de la tienda.

## iPhone: el `.ipa` con distribución Ad Hoc

> El proyecto usa el bundle id `com.marcoyam.videoDownloader` (la extensión: `com.marcoyam.videoDownloader.ShareExtension`);
> `python3 tool/perfiles_ios proyecto` avisa si el `manifest.plist` o el `.ipa` publicados no coinciden. Qué caduca,
> qué cuesta cada opción y el acceso directo gratuito (`.mobileconfig`) están en
> [CADUCIDAD_Y_DISTRIBUCION.md](CADUCIDAD_Y_DISTRIBUCION.md) y [PERFILES_IOS.md](PERFILES_IOS.md).

Apple no deja instalar apps desde una página web a cualquiera. Lo que sí permite, sin App Store, es la
**distribución Ad Hoc**: un `.ipa` firmado para una lista de iPhones registrados.

### Lo que necesitas

- **Apple Developer Program (99 USD al año).** Con la cuenta gratuita no se puede hacer Ad Hoc.
- **El UDID de cada iPhone** que vaya a instalarla. Máximo **100 iPhones por año** por cuenta.
- **Tu sitio con HTTPS** y un certificado válido (Let's Encrypt sirve). iOS no instala por HTTP.

> El programa **Enterprise** no sirve para esto: es solo para empleados de una empresa, y repartir apps al público
> con él hace que Apple revoque el certificado.

### 1. Registrar los iPhones

Cada persona te pasa el UDID de su iPhone. La forma más fácil:

- Conecta el iPhone a una Mac, ábrelo en **Finder** y haz clic en la línea bajo el nombre del iPhone hasta que
  aparezca el UDID (clic derecho → Copiar).

Luego en https://developer.apple.com/account → **Certificates, Identifiers & Profiles → Devices → +**, agrega
cada UDID con un nombre.

### 2. Crear el identificador y el perfil

1. **Identifiers → +** → App IDs → App → Bundle ID explícito `com.marcoyam.videoDownloader` (el que pusiste en Xcode, pestaña
   *General*; `python3 tool/perfiles_ios proyecto` muestra el actual). No hace falta activar capacidades.
2. **Profiles → +** → **Ad Hoc** → elige ese App ID, tu certificado de distribución y **todos** los dispositivos.
   Ponle nombre, por ejemplo `Video Downloader Ad Hoc`.

   Cada vez que registres un iPhone nuevo, **edita el perfil**, márcalo y vuelve a compilar el `.ipa`.

Si en Xcode dejas "Automatically manage signing" activado, Xcode crea el certificado y el perfil Ad Hoc solo al
exportar; los pasos de este punto son la forma manual.

### 3. Compilar el `.ipa`

```bash
flutter build ipa --release --export-method ad-hoc
```

Queda en `build/ios/ipa/video_downloader.ipa`. Si falla la firma, abre `ios/Runner.xcworkspace`, elige tu equipo
en *Signing & Capabilities* y repite.

### 4. Subirlo a tu sitio

Sube dos archivos, por ejemplo a `https://tusitio.com/apps/video-downloader/`:

- `video_downloader.ipa`
- `manifest.plist` (plantilla en [`docs/manifest.plist`](manifest.plist); cambia la URL del `.ipa`, la versión y
  el bundle id).

En tu página, el botón de instalar es un enlace así (la URL del manifiesto va completa y con HTTPS):

```html
<a href="itms-services://?action=download-manifest&url=https://tusitio.com/apps/video-downloader/manifest.plist">
  Instalar en iPhone
</a>
```

El servidor debe entregar el `.ipa` como `application/octet-stream` y el `.plist` como `text/xml` o
`application/xml`.

### 5. Instalarla en el iPhone

1. Abrir tu página **en Safari** y tocar "Instalar en iPhone". Aparece un aviso para confirmar.
2. La app se instala en la pantalla de inicio.
3. Si al abrirla iOS pide **Modo de desarrollador** (pasa en algunos iPhone con iOS 16 o superior), activarlo en
   **Ajustes → Privacidad y seguridad → Modo de desarrollador**, reiniciar y confirmar.

Si el iPhone no está en el perfil, la instalación falla con "No se pudo instalar la app".

### Duración

El `.ipa` funciona mientras el perfil Ad Hoc sea válido (un año) y tu membresía esté activa. Antes de que venza,
renueva el perfil, vuelve a compilar y sube el `.ipa` nuevo; quien la tenga la reinstala desde tu página y
conserva sus datos.

## Alternativa sin pagar: AltStore o SideStore

Puedes publicar el `.ipa` **sin firmar** y cada persona lo instala con AltStore o SideStore usando su propio Apple ID
gratuito. Funciona para cualquiera (sin registrar UDIDs), pero la app caduca cada **7 días** y la persona tiene que
renovarla desde esa app.

Para generar un `.ipa` sin firmar:

```bash
flutter build ios --release --no-codesign
cd build/ios/iphoneos && mkdir -p Payload && cp -R Runner.app Payload/ && zip -r video_downloader-sin-firmar.ipa Payload
```
