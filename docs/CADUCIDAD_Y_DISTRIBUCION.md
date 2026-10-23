# Caducidad, firma y distribución de Video Downloader en iPhone

Revisado el 2026-10-23 con la documentación de Apple (fuentes al final). Las reglas de Apple cambian: vuelve a
revisarlas antes de cada publicación importante.

## 1. Qué caduca y qué no

| Elemento | ¿Tiene caducidad? | ¿Se puede omitir? | Qué pasa si se omite | Lo usa este proyecto |
|---|---|---|---|---|
| **Perfil de configuración `.mobileconfig`** | Opcional: `RemovalDate` (fecha), `DurationUntilRemoval` (segundos) y `PayloadExpirationDate` (iOS ofrece "Actualizar") | **Sí.** Todas son opcionales | Queda instalado **hasta que la persona lo quite**. No lo hace permanente: siempre se puede quitar, y una versión futura de iOS podría dejar de admitir un payload o cambiar cómo se instala | Sí: el Web Clip, sin caducidad por defecto (`{"tipo": "ninguna"}`) |
| **Firma del `.mobileconfig`** (opcional) | La del certificado con el que firmas | Sí: sin firma iOS lo marca "No verificado" | El perfil se instala igual | No por defecto; `--certificado/--clave` si quieres |
| **Perfil de aprovisionamiento `.mobileprovision`** | **Sí, siempre** (lo genera y firma Apple) | **No** | — | No (lo crea Xcode al firmar la app) |
| **Certificado de firma de código** (Apple Development / Apple Distribution) | **Sí, siempre** | **No** | — | No (lo crea Xcode) |
| **Certificado raíz de confianza** | El de su emisor | — | — | **No.** La herramienta bloquea instalarlos (`com.apple.security.root`) |
| **Firma de la app (`.ipa`)** | Vale mientras el perfil de aprovisionamiento y el certificado sigan vigentes | **No** | Si vence, la app deja de abrir | Sí, cuando instales la app |

**Conclusión:** un `.mobileconfig` sin fecha de eliminación no caduca solo, pero **no hace que una app dure más**. La
duración de la app la decide su firma, que siempre caduca y no se puede saltar con un perfil.

## 2. Formas de instalar la app (cuenta gratuita y alternativas)

| Opción | Costo | Requisitos | Duración | Renovación | ¿En México? | ¿Desde Safari? |
|---|---|---|---|---|---|---|
| **Xcode con cuenta gratuita** (Personal Team) | 0 | Mac con Xcode y el iPhone conectado o en la misma red | **7 días** | Reinstalar desde Xcode. Límites: 3 apps por dispositivo, 10 App IDs y 3 dispositivos, que caducan a los 7 días | Sí | **No** |
| **AltStore / SideStore** (de terceros, no de Apple) | 0 | Cada persona usa su Apple ID gratuito; AltServer o la configuración inicial de SideStore | **7 días** | Desde esa app, antes de que venza | Sí | Baja el `.ipa`, pero instala la app de terceros |
| **Desarrollo con membresía** | 99 USD al año | Apple Developer Program; UDID registrado | Hasta 1 año (o hasta que venza el certificado) | Regenerar el perfil y reinstalar | Sí | Solo con dispositivos registrados |
| **Ad Hoc** | 99 USD al año | Membresía; UDID de cada iPhone; hasta 100 dispositivos por tipo al año | Hasta 1 año | Renovar el perfil, recompilar y volver a publicar (los datos se conservan) | Sí | **Sí**: `itms-services://` + `manifest.plist` por HTTPS ([DISTRIBUCION.md](DISTRIBUCION.md)) |
| **TestFlight** | 99 USD al año | Membresía; revisión de Apple para probadores externos; hasta 10,000 probadores | Cada compilación **90 días** | Subir una compilación nueva | Sí | No: se instala con la app TestFlight, por invitación o enlace público |
| **Enterprise** | 299 USD al año | Organización con 100 o más empleados, entidad legal, número D-U-N-S y entrevista de verificación | 1 año (certificado) | Renovar el certificado, el perfil y la membresía | Sí, pero **no aplica** | Técnicamente sí, pero **solo para empleados**: repartirla al público viola el contrato y Apple revoca el certificado |
| **Distribución web de Apple** | Membresía + términos adicionales | Solo en la **Unión Europea**; notarización de Apple | Según la membresía | — | **No** | Sí, solo en la UE |
| **Tiendas alternativas** | Membresía | Solo en la UE, Japón y Brasil | — | — | **No** | Desde la tienda alternativa |

**Para Video Downloader, con presupuesto cero:**

- **Tú:** Xcode con tu cuenta gratuita. Reinstalas cada 7 días desde la Mac.
- **Otras personas:** AltStore o SideStore, con su propio Apple ID; también caduca cada 7 días.
- **Lo más cercano a "bajar e instalar desde Safari":** Ad Hoc, que cuesta 99 USD al año.
- **El perfil `.mobileconfig`:** sí es gratis, y sirve para dar a la gente un acceso directo a tu página de descargas.

### Antes de instalar en un iPhone real: el bundle id

El proyecto usa **`com.example.videoDownloader`** (lo dejó `flutter create`). Apple no permite registrar el prefijo
`com.example`, así que Xcode no podrá firmar la app para un iPhone real, ni siquiera con la cuenta gratuita. Cámbialo una
vez en Xcode:

1. Target **Runner** → *General* → *Bundle Identifier*: `com.marcoyam.videoDownloader`.
2. Target **ShareExtension**: `com.marcoyam.videoDownloader.ShareExtension`. Debe empezar con el de Runner.

`python3 tool/perfiles_ios proyecto` avisa mientras siga con `com.example`. El `docs/manifest.plist` ya usa
`com.marcoyam.videoDownloader`.

## 3. Cómo renovar

### Perfil `.mobileconfig` (acceso directo)

No necesita renovarse si no tiene caducidad. Para cambiarlo:

1. En `tool/perfiles_ios/config/video_downloader_acceso.json`, sube `version` y ajusta lo que cambie. **No cambies
   `identificador`**: así iOS reemplaza el perfil anterior.
2. Genera y comprueba el sitio:
   ```bash
   python3 tool/perfiles_ios publicar
   python3 -m unittest discover -s tool/perfiles_ios/tests -t tool/perfiles_ios/tests
   ```
3. Copia el sitio a `github_page_marco/video-downloader/`, haz push y corre
   `python3 tool/perfiles_ios verificar https://markoyam.github.io/video-downloader/`.
4. Si lo firmaste y el certificado está por vencer, vuelve a publicar con el certificado nuevo. Los perfiles ya
   instalados no se tocan; la firma se revisa al instalar.

### App con cuenta gratuita (cada 7 días)

1. Conecta el iPhone y corre `flutter run --release`, o abre `ios/Runner.xcworkspace` y usa *Run*.
2. Si Xcode dice que el perfil venció, déjalo regenerarlo: *Signing & Capabilities* → *Automatically manage signing*.
3. Los datos de la app se conservan si el bundle id no cambia.

### Ad Hoc (cada año, si pagas la membresía)

Los pasos completos están en [DISTRIBUCION.md](DISTRIBUCION.md). En resumen:
1. Renueva la membresía y el certificado de distribución si vencieron.
2. Regenera el perfil Ad Hoc con todos los UDID.
3. Corre `flutter build ipa --export-method ad-hoc` y sube el `.ipa` y el `manifest.plist` con la versión nueva.

## 4. Informe: límites reales de Apple

1. **Un perfil de configuración no instala apps ni extiende su firma.** Ningún payload legítimo de un `.mobileconfig`
   instala un `.ipa`. La herramienta y la página lo dicen, y las pruebas impiden publicar textos que prometan lo
   contrario.
2. **Toda app de iPhone depende de algo que caduca:**
   - 7 días con la cuenta gratuita;
   - hasta 1 año con Ad Hoc o con Enterprise, que no aplica para el público;
   - 90 días por compilación de TestFlight.

   No hay forma legítima de evitarlo.
3. **Instalar desde la web sin pagar no existe en México.** La distribución web de Apple solo funciona en la UE.
4. **"Sin caducidad" no es "permanente".** Un perfil sin `RemovalDate` ni `DurationUntilRemoval` queda instalado hasta
   que se quite. La persona puede quitarlo siempre: la herramienta no permite impedirlo, y hacerlo requiere un
   dispositivo supervisado. Una actualización de iOS podría cambiar el comportamiento.
5. **GitHub Pages no deja configurar el tipo de contenido.** Si Safari no ofrece instalar el perfil desde ahí, usa
   Cloudflare Pages o Netlify con el `_headers` generado. Son gratis y con HTTPS.
6. **Firmar el perfil es opcional** y solo cambia la etiqueta "No verificado". Requiere un certificado tuyo de una raíz
   confiable; con GitHub Pages no tienes la clave del certificado del sitio.
7. **Probado:** generación, validación, firma con un certificado de prueba y descarga real por HTTPS desde un servidor
   local (55 pruebas automatizadas). **Falta probar en un iPhone real** (instalar, ver el ícono, quitarlo) y el tipo de
   contenido que entrega GitHub Pages.
8. **No se recopilan datos:** la página no usa scripts, cookies ni analítica, y no pide el UDID ni ningún identificador
   del dispositivo. Ad Hoc sí requiere el UDID de cada iPhone; hay que pedirlo con el consentimiento de la persona y
   registrarlo a mano.

## Fuentes

- [Apple: TopLevel (claves de un perfil)](https://developer.apple.com/documentation/devicemanagement/toplevel)
- [Apple: WebClip](https://developer.apple.com/documentation/devicemanagement/webclip)
- [Apple: instalar un perfil de configuración en iPhone](https://support.apple.com/es-mx/102400)
- [Apple: comparar membresías (límites de la cuenta gratuita)](https://developer.apple.com/support/compare-memberships/)
- [Apple Developer Program (99 USD)](https://developer.apple.com/programs/)
- [Apple Developer Enterprise Program (299 USD, uso interno)](https://developer.apple.com/programs/enterprise/)
- [Apple: distribución alternativa por región (UE, Japón, Brasil)](https://developer.apple.com/documentation/marketplacekit/participating-in-alternative-distribution-for-specific-regions)
