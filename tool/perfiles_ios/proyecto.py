"""Datos de Video Downloader leídos del propio proyecto Flutter (nada escrito a mano).

- Nombre visible: ios/Runner/Info.plist (CFBundleDisplayName).
- Bundle id: ios/Runner.xcodeproj/project.pbxproj (configuración del target Runner).
- Versión: pubspec.yaml (`version: 1.0.0+1` → versión 1.0.0, build 1).
- Ícono: ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png.
"""

from __future__ import annotations

import plistlib
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

RAIZ_PROYECTO = Path(__file__).resolve().parents[2]

ICONO_APP = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png")


@dataclass
class Proyecto:
    nombre_paquete: str
    nombre_visible: str
    version: str
    build: str
    bundle_id: Optional[str]
    icono_app: Optional[Path]
    avisos: List[str] = field(default_factory=list)


def _version(pubspec: str) -> tuple:
    m = re.search(r"^version:\s*([0-9][^\s+]*)(?:\+(\S+))?\s*$", pubspec, re.MULTILINE)
    if not m:
        return "0.0.0", "0"
    return m.group(1), m.group(2) or "0"


def _nombre_paquete(pubspec: str) -> str:
    m = re.search(r"^name:\s*(\S+)\s*$", pubspec, re.MULTILINE)
    return m.group(1) if m else "app"


def bundle_id_de_runner(pbxproj: str) -> Optional[str]:
    """Bundle id del target Runner: el bloque buildSettings cuyo INFOPLIST_FILE es Runner/Info.plist.

    Así no se confunde con RunnerTests ni con ShareExtension, que tienen sus propios ids.
    """
    ids = set()
    for bloque in re.findall(r"buildSettings = \{(.*?)\n\t\t\t\};", pbxproj, re.DOTALL):
        if re.search(r"INFOPLIST_FILE = \"?Runner/Info\.plist\"?;", bloque):
            m = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([^\";]+)\"?;", bloque)
            if m:
                ids.add(m.group(1).strip())
    return sorted(ids)[0] if ids else None


def bundle_ids_por_plist(pbxproj: str) -> dict:
    """INFOPLIST_FILE → bundle ids que usa (para revisar la extensión y las pruebas)."""
    out: dict = {}
    for bloque in re.findall(r"buildSettings = \{(.*?)\n\t\t\t\};", pbxproj, re.DOTALL):
        plist = re.search(r"INFOPLIST_FILE = \"?([^\";]+)\"?;", bloque)
        bid = re.search(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([^\";]+)\"?;", bloque)
        if plist and bid:
            out.setdefault(plist.group(1).strip(), set()).add(bid.group(1).strip())
    return out


def _avisos_de_ids(raiz: Path, pbxproj: str, bundle_id: str) -> List[str]:
    """Ids que deben coincidir con el de la app: la extensión de Compartir y el manifiesto Ad Hoc."""
    avisos = []
    for plist, ids in bundle_ids_por_plist(pbxproj).items():
        if plist.startswith("ShareExtension"):
            for bid in sorted(ids):
                if not bid.startswith(bundle_id + "."):
                    avisos.append(f"La extensión de Compartir usa {bid}, pero debe empezar con {bundle_id}. "
                                  f"(p. ej. {bundle_id}.ShareExtension); si no, Xcode no la incluye en la app.")
    manifiesto = raiz / "docs/releases/ios/manifest.plist"
    if manifiesto.exists():
        try:
            items = plistlib.loads(manifiesto.read_bytes()).get("items", [])
            ids = {i.get("metadata", {}).get("bundle-identifier") for i in items}
        except Exception:  # noqa: BLE001
            ids = set()
            avisos.append("docs/releases/ios/manifest.plist no se pudo leer.")
        for bid in sorted(i for i in ids if i):
            if bid != bundle_id:
                avisos.append(f"docs/releases/ios/manifest.plist dice {bid} y la app es {bundle_id}: la instalación "
                              "desde Safari fallaría.")
    avisos.extend(_avisos_de_ipa(raiz / "docs/releases/ios/video-downloader.ipa", bundle_id))
    return avisos


def _avisos_de_ipa(ipa: Path, bundle_id: str) -> List[str]:
    """El .ipa publicado: ¿mismo bundle id? ¿firmado? (sin firma solo sirve con AltStore/SideStore)."""
    if not ipa.exists():
        return []
    import zipfile

    try:
        with zipfile.ZipFile(ipa) as z:
            nombres = z.namelist()
            info = next((n for n in nombres if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)), None)
            if info is None:
                return [f"{ipa.name} no tiene Payload/*.app/Info.plist: no es un .ipa válido."]
            datos = plistlib.loads(z.read(info))
            app = info.rsplit("/", 1)[0]
            firmado = any(n.startswith(app + "/_CodeSignature/") for n in nombres)
            aprovisionado = (app + "/embedded.mobileprovision") in nombres
    except (zipfile.BadZipFile, OSError, ValueError):
        return [f"{ipa.name} está dañado (no es un zip válido)."]
    avisos = []
    if datos.get("CFBundleIdentifier") != bundle_id:
        avisos.append(f"docs/releases/ios/{ipa.name} se compiló con {datos.get('CFBundleIdentifier')} y la app ya es "
                      f"{bundle_id}: vuelve a compilarlo y súbelo.")
    if not (firmado and aprovisionado):
        avisos.append(f"docs/releases/ios/{ipa.name} está sin firmar: sirve para AltStore/SideStore, pero el botón "
                      "\"Instalar en iPhone\" (itms-services) no puede instalarlo; eso requiere un .ipa Ad Hoc firmado.")
    return avisos


def leer_proyecto(raiz: Path = RAIZ_PROYECTO) -> Proyecto:
    avisos: List[str] = []
    pubspec_path = raiz / "pubspec.yaml"
    pubspec = pubspec_path.read_text(encoding="utf-8") if pubspec_path.exists() else ""
    if not pubspec:
        avisos.append("No encontré pubspec.yaml: la versión queda en 0.0.0.")
    version, build = _version(pubspec)

    nombre_visible = "Video Downloader"
    info = raiz / "ios/Runner/Info.plist"
    if info.exists():
        try:
            datos = plistlib.loads(info.read_bytes())
            nombre_visible = str(datos.get("CFBundleDisplayName") or datos.get("CFBundleName") or nombre_visible)
        except Exception:  # noqa: BLE001 - Info.plist dañado: se avisa y se sigue
            avisos.append("ios/Runner/Info.plist no se pudo leer; uso el nombre 'Video Downloader'.")
    else:
        avisos.append("No existe ios/Runner/Info.plist (¿falta `flutter create`?).")

    bundle_id = None
    pbx = raiz / "ios/Runner.xcodeproj/project.pbxproj"
    texto_pbx = pbx.read_text(encoding="utf-8", errors="replace") if pbx.exists() else ""
    if texto_pbx:
        bundle_id = bundle_id_de_runner(texto_pbx)
    if bundle_id is None:
        avisos.append("No encontré el bundle id de Runner en project.pbxproj.")
    elif bundle_id.startswith("com.example."):
        avisos.append(
            f"El bundle id es {bundle_id}: Apple no permite registrar el prefijo 'com.example' para firmar e "
            "instalar en un iPhone real (ni con la cuenta gratuita). Cámbialo en Xcode (target Runner → General → "
            "Bundle Identifier), por ejemplo a com.marcoyam.videoDownloader, y el de ShareExtension a "
            "com.marcoyam.videoDownloader.ShareExtension."
        )

    if bundle_id and texto_pbx:
        avisos.extend(_avisos_de_ids(raiz, texto_pbx, bundle_id))

    icono = raiz / ICONO_APP
    return Proyecto(
        nombre_paquete=_nombre_paquete(pubspec),
        nombre_visible=nombre_visible,
        version=version,
        build=build,
        bundle_id=bundle_id,
        icono_app=icono if icono.exists() else None,
        avisos=avisos,
    )
