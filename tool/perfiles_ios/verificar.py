"""Revisa un sitio ya publicado: HTTPS, tipo de contenido, que cada perfil coincida con perfiles.json y
que siga siendo válido. Solo lee: no envía datos ni identificadores del dispositivo.
"""

from __future__ import annotations

import hashlib
import json
import ssl
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import List, Optional, Tuple

from validar import validar_archivo

TIPO_CORRECTO = "application/x-apple-aspen-config"


def descargar(url: str, cafile: Optional[Path] = None, timeout: float = 20) -> Tuple[int, str, bytes]:
    """(estado HTTP, tipo de contenido, cuerpo). Solo https://, con verificación de certificado."""
    if urllib.parse.urlparse(url).scheme != "https":
        raise ValueError(f"Solo se permite HTTPS: {url}")
    contexto = ssl.create_default_context(cafile=str(cafile) if cafile else None)
    req = urllib.request.Request(url, headers={"User-Agent": "perfiles_ios-verificar/1"})
    try:
        with urllib.request.urlopen(req, context=contexto, timeout=timeout) as r:
            return r.status, r.headers.get("Content-Type", ""), r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type", "") if e.headers else "", b""


def verificar_sitio(base: str, cafile: Optional[Path] = None) -> Tuple[bool, List[str]]:
    """(todo bien, informe). [base] es la carpeta publicada, p. ej. https://markoyam.github.io/video-downloader/."""
    base = base if base.endswith("/") else base + "/"
    informe: List[str] = []
    ok = True
    try:
        estado, _, cuerpo = descargar(base + "perfiles.json", cafile)
    except (ValueError, urllib.error.URLError, ssl.SSLError, OSError) as e:
        return False, [f"✗ No se pudo abrir {base}perfiles.json: {e}"]
    if estado != 200:
        return False, [f"✗ {base}perfiles.json respondió HTTP {estado}."]
    try:
        publicado = json.loads(cuerpo.decode("utf-8"))
        perfiles = publicado["perfiles"]
    except (ValueError, KeyError, UnicodeDecodeError):
        return False, ["✗ perfiles.json está dañado."]
    informe.append(f"• {publicado.get('app', '?')} {publicado.get('version_app', '')} · generado {publicado.get('generado', '?')}")

    for p in perfiles:
        url = base + urllib.parse.quote(p["archivo"])
        try:
            estado, tipo, datos = descargar(url, cafile)
        except (ValueError, urllib.error.URLError, ssl.SSLError, OSError) as e:
            informe.append(f"✗ {p['archivo']}: {e}")
            ok = False
            continue
        if estado != 200:
            informe.append(f"✗ {p['archivo']}: HTTP {estado}.")
            ok = False
            continue
        tipo_base = tipo.split(";")[0].strip().lower()
        if tipo_base == TIPO_CORRECTO:
            informe.append(f"✓ {p['archivo']}: tipo de contenido correcto ({TIPO_CORRECTO}).")
        elif tipo_base in ("application/octet-stream", "application/x-plist", "application/xml", "text/xml"):
            informe.append(f"⚠ {p['archivo']}: se entrega como {tipo_base}, no como {TIPO_CORRECTO}. Prueba en Safari "
                           "si ofrece instalarlo; si no, publica en un hosting que lea _headers (Cloudflare Pages, Netlify).")
        else:
            informe.append(f"✗ {p['archivo']}: se entrega como '{tipo_base or 'sin tipo'}'; Safari no lo instalará.")
            ok = False
        suma = hashlib.sha256(datos).hexdigest()
        if suma != p.get("sha256"):
            informe.append(f"✗ {p['archivo']}: el SHA-256 no coincide con perfiles.json (¿archivo viejo en caché o a medio subir?).")
            ok = False
        else:
            informe.append(f"✓ {p['archivo']}: SHA-256 coincide · versión {p.get('version')} · {len(datos)} bytes.")
        errores = validar_archivo(datos)
        if errores:
            ok = False
            informe.extend(f"✗ {p['archivo']}: {e}" for e in errores)
        else:
            informe.append(f"✓ {p['archivo']}: perfil válido.")
    return ok, informe
