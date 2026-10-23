# Perfiles de configuración iOS (`.mobileconfig`) para Video Downloader

Herramienta para **generar, validar, publicar y revisar** perfiles de configuración desde tu sitio con HTTPS
(`https://markoyam.github.io/myam_media_player/`). Vive en `tool/perfiles_ios/`, junto a
`configurar_plataformas.py`, y usa solo Python y `openssl`, que ya vienen en macOS: no instala nada ni usa servicios
de pago.

> **Lo que un perfil hace y lo que no.** El perfil de ejemplo agrega a la pantalla de inicio un **acceso directo**
> (Web Clip) a la página de descargas (`docs/index.html`). **No instala la app**: un perfil de configuración no puede instalar ni firmar un
> `.ipa`. La app de iPhone siempre necesita una firma válida de Apple, que caduca
> (ver [CADUCIDAD_Y_DISTRIBUCION.md](CADUCIDAD_Y_DISTRIBUCION.md)).

## Qué hay

| Archivo | Para qué |
|---|---|
| `tool/perfiles_ios/__main__.py` | Comandos: `proyecto`, `generar`, `validar`, `publicar`, `verificar` |
| `tool/perfiles_ios/proyecto.py` | Lee del proyecto: nombre (`Info.plist`), bundle id (`project.pbxproj`), versión (`pubspec.yaml`), ícono |
| `tool/perfiles_ios/perfil.py` | Arma el perfil desde un JSON (UUID estables, textos de consentimiento, caducidad opcional) |
| `tool/perfiles_ios/validar.py` | Validación estricta y bloqueo de payloads sensibles |
| `tool/perfiles_ios/firmar.py` | Firma opcional con tu certificado (nunca guarda ni descarga certificados) |
| `tool/perfiles_ios/sitio.py` | Página de descarga, `perfiles.json` (estado) y `_headers` |
| `tool/perfiles_ios/verificar.py` | Revisa el sitio ya publicado por HTTPS |
| `tool/perfiles_ios/config/video_downloader_acceso.json` | Perfil de ejemplo (no sensible) |
| `tool/perfiles_ios/config/icono-webclip.png` | Ícono de la app reducido a 400×400 |
| `tool/perfiles_ios/tests/` | 57 pruebas automatizadas |
| `docs/perfiles/` | La página del perfil ya generada (la publica GitHub Pages) |

## Uso en macOS

Desde la carpeta del proyecto (`video_downloader_flutter`):

```bash
python3 tool/perfiles_ios proyecto      # qué leyó del proyecto y avisos
python3 tool/perfiles_ios publicar      # genera la página en docs/perfiles/
python3 tool/perfiles_ios validar docs/perfiles/*.mobileconfig
python3 -m unittest discover -s tool/perfiles_ios/tests -t tool/perfiles_ios/tests   # pruebas
```

`publicar` no escribe nada si algún perfil tiene errores, ni si la página prometiera algo que Apple no permite (duración
ilimitada, instalar apps).

En macOS también puedes revisar un perfil con las herramientas del sistema:

```bash
plutil -lint docs/perfiles/video-downloader-acceso.mobileconfig
```

### Crear o cambiar un perfil

Copia `config/video_downloader_acceso.json` y edítalo:

| Campo | Qué es |
|---|---|
| `archivo` | Nombre del `.mobileconfig` (sin espacios) |
| `identificador` | DNS inverso único, p. ej. `io.github.markoyam.myammediaplayer.acceso`. **No lo cambies** entre versiones: iOS lo usa para reemplazar el perfil anterior |
| `version` | Súbela (2, 3…) en cada cambio: cambia los UUID y queda registrada en `perfiles.json` |
| `nombre`, `organizacion`, `descripcion` | Lo que verá la persona antes de instalar |
| `fecha_creacion` | `AAAA-MM-DD`; se muestra en la descripción y en la página |
| `caducidad` | `{"tipo": "ninguna"}`, `{"tipo": "fecha", "fecha": "2027-10-23T00:00:00Z"}` o `{"tipo": "duracion", "dias": 365}` |
| `payloads` | Solo `webclip`: `url` (https), `etiqueta`, `icono` (`"proyecto"` = el ícono de la app), `pantalla_completa` |

La herramienta agrega sola, en la descripción y en el texto de consentimiento que iOS muestra antes de instalar: qué
configura, qué permisos pide (ninguno), que no instala la app y cómo quitarlo.

### Qué rechaza la validación

- Claves que no están en la referencia de Apple, tipos incorrectos o la falta de claves obligatorias:
  `PayloadContent`, `PayloadIdentifier`, `PayloadType`, `PayloadUUID` y `PayloadVersion`. También exige nombre y
  descripción visibles.
- UUID inválidos o repetidos, e identificadores repetidos o que no son DNS inverso.
- Payloads sensibles: certificados (raíz, PKCS#12, SCEP, ACME), VPN, proxy, MDM, DNS, filtro web, Wi-Fi, celular,
  cuentas de correo, restricciones, código de bloqueo, modo de app única… y cualquier tipo que no sea Web Clip.
- Que no se pueda quitar: `PayloadRemovalDisallowed = true` o `IsRemovable = false`.
- Web Clips con URL `http://`, sin etiqueta, sin ícono o con un ícono que no sea PNG cuadrado de 400×400 o menos.
- Fechas de eliminación ya pasadas, duraciones de 0 o menos, y archivos vacíos, dañados, cortados o con firma rota.

## Publicar con HTTPS (gratis)

### GitHub Pages (tu sitio actual)

Este repositorio (`markoYam/myam_media_player`) publica su carpeta `docs/` en
`https://markoyam.github.io/myam_media_player/`. `publicar` escribe la página del perfil en `docs/perfiles/`, y tu
página principal (`docs/index.html`) la enlaza desde la tarjeta de iPhone ("Acceso directo en tu pantalla de inicio").

1. Genera: `python3 tool/perfiles_ios publicar`.
2. Sube los cambios:

   ```bash
   git add docs/perfiles docs/index.html
   git commit -m "Perfil de acceso directo"
   git push
   ```

3. Espera a que GitHub Pages publique (1 o 2 minutos, pestaña *Actions*) y revisa:

   ```bash
   python3 tool/perfiles_ios verificar https://markoyam.github.io/myam_media_player/perfiles/
   ```

   `verificar` comprueba que todo llegue por HTTPS, que cada archivo coincida con `perfiles.json` (SHA-256), que el
   perfil siga siendo válido y con qué **tipo de contenido** lo entrega el servidor.

**Ojo con el tipo de contenido.** Safari ofrece instalar un perfil cuando el servidor lo entrega como
`application/x-apple-aspen-config`. GitHub Pages no permite configurarlo. Si `verificar` dice `octet-stream`, prueba en
el iPhone: si Safari lo baja como archivo y no muestra **Perfil descargado** en Ajustes, usa una de las opciones de
abajo.

### Cloudflare Pages o Netlify (gratis, con tipo correcto)

La carpeta generada trae `_headers`, que estos servicios leen para entregar el `.mobileconfig` con el tipo correcto.
Sube la carpeta `docs/` como sitio estático (en Cloudflare Pages: *Create → Pages → Upload assets*).
Los dos dan HTTPS gratis. Después corre `verificar` con la URL nueva.

### Servidor propio (nginx o Apache)

- nginx, dentro de `types { }`: `application/x-apple-aspen-config mobileconfig;`
- Apache (`.htaccess`): `AddType application/x-apple-aspen-config .mobileconfig`

Con Let's Encrypt (`certbot`) el HTTPS es gratis.

## Instalar en el iPhone

1. Abre la página **en Safari** y toca **Descargar perfil**. Si Safari pregunta, toca **Permitir** y luego **Cerrar**.
2. Abre **Ajustes**: arriba aparece **Perfil descargado**. Tócalo.
3. Revisa lo que dice y toca **Instalar**. iOS pide el código del iPhone.
4. Hazlo **antes de 8 minutos**: si no, iOS borra el perfil descargado. Solo puede haber un perfil descargado a la vez.
5. Si está activada la *Protección en caso de robo* y no estás en un lugar habitual, iOS puede pedirte esperar o
   desactivarla un momento.

**Quitarlo:** Ajustes → General → VPN y gestión de dispositivos → *Video Downloader · acceso directo* →
**Eliminar perfil**. El acceso directo desaparece con él.

**"No verificado":** un perfil sin firmar se instala igual, pero iOS lo muestra así. Ver *Firmar* abajo.

## Firmar (opcional)

```bash
python3 tool/perfiles_ios publicar --certificado ~/certs/firma.pem --clave ~/certs/firma.key [--cadena ~/certs/cadena.pem]
```

- Guarda el certificado y la clave **fuera del repositorio**. La herramienta no guarda, descarga ni genera
  certificados.
- iOS muestra "Verificado" solo si el certificado lleva a una raíz en la que el iPhone confía. Un certificado
  autofirmado no sirve para eso.
- Con GitHub Pages no tienes la clave del certificado HTTPS del sitio, así que no puedes firmar con él. Con un servidor
  propio y Let's Encrypt sí tienes la clave; muchos firman perfiles así, pero Apple no lo documenta: pruébalo en tu
  iPhone antes de depender de ello.
- Si no firmas, no pasa nada grave: el perfil funciona igual.

## Resolución de problemas

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Safari muestra el XML como texto | El servidor lo entrega como `text/plain` o `text/xml` | Usa un hosting que lea `_headers` o configura el tipo; `verificar` lo detecta |
| Safari lo baja a Archivos y Ajustes no muestra "Perfil descargado" | Tipo `application/octet-stream` (GitHub Pages) | Cloudflare Pages o Netlify con `_headers` |
| `verificar` no encuentra `perfiles.json` | No se subió `docs/perfiles/` o GitHub Pages aún no termina | `git status`, haz push y espera a *Actions* |
| "Perfil descargado" desapareció | Pasaron más de 8 minutos o bajaste otro perfil | Descárgalo de nuevo e instálalo enseguida |
| "El perfil no es válido" / "No se pudo instalar" | Archivo dañado, viejo en caché o editado a mano | `python3 tool/perfiles_ios verificar URL` y vuelve a publicar |
| El ícono sale en blanco | Falta `Icon` o no es PNG | La validación lo impide; usa `icono-webclip.png` |
| Se instaló una versión vieja | Caché del navegador o del CDN | Sube `version`, publica de nuevo y espera unos minutos |
| `verificar` falla con un error de certificado | El sitio no tiene HTTPS válido | Revisa el HTTPS del hosting; GitHub Pages: *Settings → Pages → Enforce HTTPS* |

## Pruebas

```bash
python3 -m unittest discover -s tool/perfiles_ios/tests -t tool/perfiles_ios/tests -v
```

Cubren:
- estructura, identificadores únicos y campos obligatorios;
- manejo de errores de configuración y archivos vacíos, dañados, cortados o con firma rota;
- payloads sensibles, uno por uno;
- firma con un certificado de prueba temporal;
- que la página y el perfil no prometan duración ilimitada ni instalar la app;
- **descarga real por HTTPS** desde un servidor local con certificado de prueba: tipo correcto, `octet-stream`,
  `text/plain`, archivo cambiado, archivo que falta y certificado no confiable.

**Pendiente:** probarlo en un iPhone real. Desde aquí no hay dispositivo. Para hacerlo:
1. Publica (`git push`).
2. Corre `verificar`.
3. En el iPhone, instala, comprueba el ícono en la pantalla de inicio y quita el perfil.
