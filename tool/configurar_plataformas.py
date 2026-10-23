#!/usr/bin/env python3
"""Ajusta los archivos de Android e iOS que genera `flutter create`.

Uso (desde la carpeta del proyecto, después de `flutter create`):

    python3 tool/configurar_plataformas.py

Se puede ejecutar varias veces: solo agrega lo que falte.

Android (android/app/src/main/AndroidManifest.xml):
  - Permisos de internet y de reproducción en segundo plano.
  - Actividad de audio_service, servicio y receptor de botones multimedia (just_audio_background).
  - Tráfico sin cifrar permitido SOLO hacia 127.0.0.1 (el proxy local de just_audio).
  - Nombre visible "Video Downloader".
  - Recibir enlaces con "Compartir" (ACTION_SEND text/plain) y abrir enlaces de YouTube (ACTION_VIEW).
  - Imagen en imagen (supportsPictureInPicture) en la actividad principal.

iOS (ios/Runner/Info.plist):
  - Audio en segundo plano (UIBackgroundModes = audio).
  - Descargas visibles en la app Archivos (UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace).
  - Conexiones locales sin cifrar para el proxy de just_audio (NSAllowsLocalNetworking).
  - Nombre visible "Video Downloader".
  - Esquema propio videodownloader:// (lo usa la extensión "Compartir"; ver tool/agregar_share_extension.rb).
"""

import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP_NAME = "Video Downloader"

MANIFEST = ROOT / "android/app/src/main/AndroidManifest.xml"
NETWORK_CONFIG = ROOT / "android/app/src/main/res/xml/network_security_config.xml"
INFO_PLIST = ROOT / "ios/Runner/Info.plist"

PERMISSIONS = [
    "android.permission.INTERNET",
    "android.permission.WAKE_LOCK",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK",
]

SERVICE_BLOCK = """
        <!-- just_audio_background / audio_service: reproducción en segundo plano -->
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true" tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
"""

SHARE_FILTERS = """
            <!-- Recibir enlaces con "Compartir" (ShareHandler.java del plugin media_tools) -->
            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
            <!-- Abrir enlaces de YouTube con la app (Android pregunta con qué app abrirlos) -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="https" />
                <data android:host="www.youtube.com" />
                <data android:host="youtube.com" />
                <data android:host="m.youtube.com" />
                <data android:host="music.youtube.com" />
                <data android:host="youtu.be" />
            </intent-filter>
"""

URL_SCHEME = "videodownloader"

NETWORK_XML = """<?xml version="1.0" encoding="utf-8"?>
<!-- Solo el proxy local de just_audio (127.0.0.1) puede usar HTTP sin cifrar. Todo lo demás, HTTPS. -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false" />
    <domain-config cleartextTrafficPermitted="true">
        <domain includeSubdomains="false">127.0.0.1</domain>
        <domain includeSubdomains="false">localhost</domain>
    </domain-config>
</network-security-config>
"""


def fail(msg: str) -> None:
    print(f"ERROR: {msg}")
    sys.exit(1)


def android() -> None:
    if not MANIFEST.exists():
        fail(f"No existe {MANIFEST}. Ejecuta antes: flutter create --org com.marcoyam --platforms android,ios .")
    xml = MANIFEST.read_text(encoding="utf-8")

    if "xmlns:tools" not in xml:
        xml = xml.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)

    for perm in PERMISSIONS:
        if perm not in xml:
            xml = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{perm}" />', xml, count=1)

    # "Guardar en Música / Películas" en Android 9 o anterior (en 10+ no hace falta permiso).
    if "android.permission.WRITE_EXTERNAL_STORAGE" not in xml:
        xml = re.sub(
            r"(<manifest[^>]*>)",
            r'\1\n    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="28" />',
            xml,
            count=1,
        )

    # La actividad principal debe ser la de audio_service.
    xml = re.sub(r'android:name="\.MainActivity"', 'android:name="com.ryanheise.audioservice.AudioServiceActivity"', xml)

    xml = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', xml, count=1)

    if "networkSecurityConfig" not in xml:
        xml = xml.replace("<application", '<application\n        android:networkSecurityConfig="@xml/network_security_config"', 1)

    # Actividad principal: imagen en imagen y filtros para "Compartir".
    m = re.search(r"<activity\b[^>]*AudioServiceActivity[^>]*>", xml)
    if m is None:
        fail("No encontré la actividad principal en el AndroidManifest.xml")
    tag = m.group(0)
    new_tag = tag
    if "supportsPictureInPicture" not in new_tag:
        new_tag = new_tag.replace("<activity", '<activity\n            android:supportsPictureInPicture="true"', 1)
    if "resizeableActivity" not in new_tag:
        new_tag = new_tag.replace("<activity", '<activity\n            android:resizeableActivity="true"', 1)
    # Una sola actividad (singleTask): al compartir desde otra app no se abre una segunda copia
    # dentro de la tarea de esa app, que pelearía por el mismo motor de Flutter.
    new_tag = re.sub(r'android:launchMode="[^"]*"', 'android:launchMode="singleTask"', new_tag)
    if "launchMode" not in new_tag:
        new_tag = new_tag.replace("<activity", '<activity\n            android:launchMode="singleTask"', 1)
    xml = xml.replace(tag, new_tag, 1)
    if "android.intent.action.SEND" not in xml:
        start = xml.index(new_tag) + len(new_tag)
        end = xml.rindex("\n", start, xml.index("</activity>", start)) + 1  # inicio de la línea de </activity>
        xml = xml[:end] + SHARE_FILTERS.lstrip("\n") + xml[end:]

    if "com.ryanheise.audioservice.MediaButtonReceiver" not in xml:
        xml = xml.replace("</application>", SERVICE_BLOCK + "    </application>", 1)

    MANIFEST.write_text(xml, encoding="utf-8")
    NETWORK_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    NETWORK_CONFIG.write_text(NETWORK_XML, encoding="utf-8")
    print(f"Android listo: {MANIFEST.relative_to(ROOT)}")


def ios() -> None:
    if not INFO_PLIST.exists():
        fail(f"No existe {INFO_PLIST}. Ejecuta antes: flutter create --org com.marcoyam --platforms android,ios .")
    with INFO_PLIST.open("rb") as f:
        plist = plistlib.load(f)

    modes = plist.setdefault("UIBackgroundModes", [])
    if "audio" not in modes:
        modes.append("audio")
    plist["UIFileSharingEnabled"] = True
    plist["LSSupportsOpeningDocumentsInPlace"] = True
    ats = plist.setdefault("NSAppTransportSecurity", {})
    ats["NSAllowsLocalNetworking"] = True
    plist["CFBundleDisplayName"] = APP_NAME
    # Esquema propio: la extensión "Compartir" abre la app con videodownloader://open?url=…
    url_types = plist.setdefault("CFBundleURLTypes", [])
    if not any(URL_SCHEME in t.get("CFBundleURLSchemes", []) for t in url_types):
        url_types.append({
            "CFBundleURLName": "com.marcoyam.videodownloader",
            "CFBundleURLSchemes": [URL_SCHEME],
        })

    with INFO_PLIST.open("wb") as f:
        plistlib.dump(plist, f)
    print(f"iOS listo: {INFO_PLIST.relative_to(ROOT)}")


if __name__ == "__main__":
    android()
    ios()
    print("Listo. Ahora: flutter pub get && flutter run")
