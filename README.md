# Video Downloader (Flutter · Android e iOS)

Migración a Flutter de la app Android nativa (`youtube_downloader`, Kotlin). Un solo código para Android y iPhone.

**Creado por Marco Yam · Powered by Claude**

> ⚠️ Uso personal. Descargar de YouTube va contra sus Términos de servicio y la App Store lo prohíbe
> (regla 5.2.3). Esta app se distribuye desde un sitio propio: ver [docs/DISTRIBUCION.md](docs/DISTRIBUCION.md).

## Estado de la migración

Comparado con la versión Kotlin:

| Función | Kotlin | Flutter |
|---|---|---|
| Inicio con "Para ti", secciones y "Seguir viendo" | ✅ | ✅ (las secciones son búsquedas: youtube_explode no expone tendencias) |
| Búsqueda de videos, listas y canales; pegar enlaces de video, lista o canal | ✅ | ✅ |
| Ver video con "A continuación" y reproducción automática | ✅ | ✅ (con pantalla completa y doble toque ±10 s) |
| Canales (recientes y populares) | ✅ | ✅ |
| Listas de reproducción: Reproducir todo, Aleatorio, Escuchar | ✅ | ✅ |
| Historial, reanudar donde te quedaste | ✅ | ✅ |
| Escuchar en segundo plano con cola (notificación, bloqueo, audífonos) | ✅ | ✅ |
| Descargas MP4 hasta 1080p (video + audio unidos sin pérdida) | ✅ | ✅ plugin `media_tools` |
| M4A sin pérdida y **MP3** con LAME + etiquetas ID3 | ✅ | ✅ plugin `media_tools` |
| Biblioteca con **carpetas** (crear, renombrar, mover, agregar, selección múltiple) | ✅ | ✅ |
| Ajustes (tema, calidad, formato, MP3, descargas a la vez, historial) | ✅ | ✅ |
| **Mixtape sin conexión**: lo que escuchas o ves más de 30 s se guarda solo (canciones de hasta 15 min, con Wi-Fi, hasta N) | — | ✅ nuevo |
| **Minimizar el video** (sigue en un mini reproductor mientras navegas; deslizar hacia abajo) | — | ✅ nuevo |
| **Canción / Video** como YouTube Music (cambia en el mismo punto, la cola se conserva) | — | ✅ nuevo |
| **Listas de reproducción propias** (Guardar desde un video o el reproductor; reordenar, aleatorio, descargar todo para escuchar sin conexión) | — | ✅ nuevo |
| **Ecualizador** con presets (Android: el del teléfono; iOS: filtros propios en `media_tools`, también en streaming) | — | ✅ nuevo |
| Buscar: búsquedas recientes y sugerencias mientras escribes | — | ✅ nuevo |
| **Volumen parejo** (Apagado / Normal / Suave; en Android también sube las bajas) | — | ✅ nuevo |
| **"Tu biblioteca" estilo Spotify**: chips (Listas, Carpetas, Artistas, Canciones, Videos), orden, lista o cuadrícula, mixtape y descargas fijados | — | ✅ nuevo |
| Biblioteca como app de música: búsqueda, artistas, cola visible (saltar, reordenar, quitar), portadas sin internet | — | ✅ nuevo |
| Descargas y audio con el cliente **visionOS** (portado de NewPipe, sin token anti-bots) | NewPipeExtractor | ✅ |
| Video HD en **streaming** | ✅ hasta 1080p | ✅ manifiesto HLS de visionOS (adaptativo: el reproductor sube a HD según la conexión) |
| Picture-in-Picture | ✅ | ✅ iOS: reproductor nativo (botón en el video); Android: modo PiP, también al salir de la app (Android 12+) |
| Internet Archive y enlaces directos | ✅ | ✅ archive.org/details/… (API de metadatos; MP3/M4A/MP4, OGG solo Android) y enlaces .mp3/.m4a/.mp4 sueltos: reproducir y descargar |
| Recibir enlaces con "Compartir" desde otra app | ✅ | ✅ Android: directo; iOS: extensión "Compartir" (se crea con `ruby tool/agregar_share_extension.rb`) |
| Guardar en Música/Películas (Android) | ✅ | ✅ menú ⋮ de la Biblioteca → Música/Video Downloader o Películas/Video Downloader (MediaStore) |
| Descargas que siguen con la app cerrada | ✅ WorkManager | ✅ bloques en segundo plano (iOS: NSURLSession; Android: WorkManager). En iOS siguen minimizada o si el sistema la cierra; si la cierras tú deslizándola, se reanudan al abrirla |

## Requisitos

- Flutter 3.27 o superior (`flutter --version`).
- Para iPhone: una Mac con Xcode y CocoaPods (`sudo gem install cocoapods` o `brew install cocoapods`).
- Para Android: Android Studio con el SDK.

## Después de actualizar: pasos en la Mac

1. `python3 tool/configurar_plataformas.py` (permisos, audio en segundo plano, Compartir, PiP; se puede correr
   varias veces).
2. `ruby tool/agregar_share_extension.rb` (una vez): crea el target **ShareExtension** en Xcode. Luego, en
   `ios/Runner.xcworkspace` → ShareExtension → *Signing & Capabilities*, elige el mismo equipo que Runner.
3. Detén la app y corre `flutter pub get && flutter run`.

## Primera vez: generar las carpetas de Android e iOS

Este repositorio trae el código (`lib/`, `test/`) pero no las carpetas `android/` e `ios/`; esas las genera Flutter
según tu versión instalada. Desde esta carpeta:

```bash
flutter create --org com.marcoyam --project-name video_downloader --platforms android,ios .
python3 tool/configurar_plataformas.py
flutter pub get
flutter test
flutter run
```

`flutter create .` no sobrescribe archivos que ya existen (`lib/`, `pubspec.yaml`, `test/`): solo agrega lo que falta.

`tool/configurar_plataformas.py` agrega a los archivos generados:

- **Android:** permisos de internet y reproducción en segundo plano, servicio de audio, botones multimedia, nombre
  "Video Downloader" y HTTP sin cifrar **solo** hacia `127.0.0.1` (proxy local del reproductor).
- **iOS:** audio en segundo plano, descargas visibles en la app Archivos y conexiones locales para el proxy.

Para iPhone, abre `ios/Runner.xcworkspace` en Xcode una vez, elige tu equipo en *Signing & Capabilities* y conecta
el iPhone. Con la cuenta gratuita de Apple la app dura 7 días instalada.

## Cómo está hecho

```
lib/
  main.dart                     arranque: reproductor en segundo plano + Riverpod
  app.dart                      tema, splash y pestañas (Buscar, Descargas, Biblioteca) con mini reproductor
  providers.dart                servicio de YouTube y base de datos
  core/                         formatos (vistas "1.2 M", duraciones, bytes, nombres de archivo), enlaces, widgets
  data/
    youtube_service.dart        youtube_explode_dart: búsqueda, video, relacionados, flujos (con caché de 30 min)
    stream_selection.dart       qué calidad reproducir y qué opciones de descarga ofrecer (con pruebas)
    download_manager.dart       cola persistente (2 a la vez), progreso, reanudación con archivo parcial
    database.dart, models.dart  SQLite (sqflite)
  playback/audio_controller.dart  just_audio + just_audio_background; cada video de la cola se resuelve al llegar a él
  playback/video_session.dart     video que se está viendo (sobrevive al minimizar; autoplay, mixtape, Canción/Video)
  features/                     search, watch, player, downloads, library, splash
test/                           formatos, enlaces, selección de flujos, modelos
tool/configurar_plataformas.py  ajustes de AndroidManifest e Info.plist
packages/media_tools/           plugin propio: unir MP4 y convertir a MP3
  src/lame/                     LAME 3.99.5 en C (LGPL), compartido por Android e iOS
  android/                      Java: MediaExtractor + MediaMuxer (unir), MediaCodec + LAME (MP3), CMake/NDK
  ios/                          Objective-C: AVFoundation (unir, decodificar) + LAME; MTEqualizer (audio tap sobre
                                el AVQueuePlayer de just_audio) + MTEqualizerDSP.c (filtros biquad en C)
  test_native/eq_dsp_test.c     prueba del ecualizador en C:
                                cc -I ios/Classes test_native/eq_dsp_test.c ios/Classes/MTEqualizerDSP.c -lm && ./a.out
docs/DISTRIBUCION.md            publicar el .apk y el .ipa en tu sitio
```

| Android (Kotlin) | Flutter |
|---|---|
| NewPipeExtractor | youtube_explode_dart (BSD-3) |
| Media3 + MediaSessionService | just_audio + just_audio_background |
| ExoPlayer (video) | video_player |
| Room | sqflite |
| WorkManager | gestor propio dentro de la app (etapa 1) |
| Hilt + ViewModel | Riverpod 3 |

## Lo que hay que saber

- **Video en streaming.** Se reproduce con el manifiesto HLS de visionOS, que es adaptativo: la calidad (hasta
  HD) sube o baja según tu conexión. **Las descargas llegan a 1080p**: se bajan video y audio y el plugin
  `media_tools` los une sin recodificar.
- **MP3.** Se descarga el AAC y se convierte con LAME en el teléfono (tarda unos segundos por canción). La primera
  compilación de Android compila LAME con el NDK; si no lo tienes, Android Studio lo descarga solo.
- **Licencia de LAME.** Es LGPL: al repartir la app hay que incluir su licencia (`packages/media_tools/LICENSE_LAME`)
  y el código de LAME que usas (ya está en `packages/media_tools/src/lame`).
- **Descargas en segundo plano.** Cada archivo se baja en bloques de 10 MB que descarga el sistema
  (NSURLSession en iOS, WorkManager en Android), aunque la app esté minimizada o cerrada. Unir video y audio o
  convertir a MP3 se hace al volver a abrir la app. En iPhone, si cierras la app a mano (deslizándola en el
  selector de apps) iOS cancela lo pendiente; se reanuda al abrirla. Si el sistema no puede, la descarga sigue
  dentro de la app como antes.
- **Dónde quedan los archivos.**
  - iPhone: app **Archivos → En mi iPhone → Video Downloader** (carpetas `Videos` y `Audio`).
  - Android: almacenamiento privado de la app (se ven en la Biblioteca y se pueden compartir).
- **Cuando YouTube cambia**, la búsqueda o la reproducción fallan con "No se pudo leer la información de YouTube".
  Se arregla actualizando: `flutter pub upgrade youtube_explode_dart`.

## Distribución en iPhone y perfiles `.mobileconfig`

- [docs/DISTRIBUCION.md](docs/DISTRIBUCION.md): publicar el `.apk` y el `.ipa` (Ad Hoc) en tu sitio.
- [docs/CADUCIDAD_Y_DISTRIBUCION.md](docs/CADUCIDAD_Y_DISTRIBUCION.md): qué caduca (perfil, aprovisionamiento,
  certificados, firma de la app), opciones gratuitas y de pago, qué funciona en México y cómo renovar.
- [docs/PERFILES_IOS.md](docs/PERFILES_IOS.md): `tool/perfiles_ios`, que genera, valida, publica y revisa el perfil de
  acceso directo de `https://markoyam.github.io/myam_media_player/` (página en `docs/perfiles/`). Un perfil **no instala la app**.

```bash
python3 tool/perfiles_ios publicar     # página en docs/perfiles/ (se publica con git push)
python3 -m unittest discover -s tool/perfiles_ios/tests -t tool/perfiles_ios/tests
```

## Pruebas

```bash
flutter test
```

| Archivo | Cubre |
|---|---|
| `format_test.dart` | "1.2 M" (trunca como YouTube), duraciones, bytes, nombres de archivo seguros |
| `youtube_links_test.dart` | watch, youtu.be, shorts, móvil/música, ids inválidos, dominios que imitan a YouTube |
| `stream_selection_test.dart` | Video reproducible, mejor AAC, opciones de descarga sin video-only ni webm |
| `models_test.dart` | Ida y vuelta a SQLite, progreso, valores desconocidos |
| `widget_test.dart` | Pantalla de error con reintentar |
| `id3_test.dart` | Etiqueta ID3v2.3 en UTF-16 (acentos), tamaño syncsafe |
| `folders_history_test.dart` | Nombres de carpeta, conteos, progreso y reanudar del historial |

## Licencias

- youtube_explode_dart: BSD-3-Clause. just_audio, video_player, sqflite, Riverpod: MIT/BSD.
- A diferencia de la versión Android (NewPipeExtractor es GPLv3), esta versión no arrastra GPL.
# myam_media_player
