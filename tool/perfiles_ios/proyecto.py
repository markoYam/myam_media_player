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
    if pbx.exists():
        bundle_id = bundle_id_de_runner(pbx.read_text(encoding="utf-8", errors="replace"))
    if bundle_id is None:
        avisos.append("No encontré el bundle id de Runner en project.pbxproj.")
    elif bundle_id.startswith("com.example."):
        avisos.append(
            f"El bundle id es {bundle_id}: Apple no permite registrar el prefijo 'com.example' para firmar e "
            "instalar en un iPhone real (ni con la cuenta gratuita). Cámbialo en Xcode (target Runner → General → "
            "Bundle Identifier), por ejemplo a com.marcoyam.videoDownloader, y el de ShareExtension a "
            "com.marcoyam.videoDownloader.ShareExtension."
        )

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
