"""Firma opcional de perfiles (CMS/S-MIME en DER) con `openssl`, incluido en macOS.

Un perfil sin firmar es válido: iOS lo instala y lo marca como "No verificado". Firmarlo solo cambia
esa etiqueta si el certificado lleva a una raíz en la que el iPhone confía. Este módulo nunca guarda,
descarga ni genera certificados de terceros: usa el certificado y la clave que tú le indiques, fuera
del repositorio.
"""

from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional


def _openssl() -> str:
    ruta = shutil.which("openssl")
    if ruta is None:
        raise RuntimeError("No encontré `openssl` (en macOS viene instalado).")
    return ruta


def firmar(datos: bytes, certificado: Path, clave: Path, cadena: Optional[Path] = None) -> bytes:
    """Devuelve [datos] firmados (DER, con el contenido adentro: -nodetach)."""
    for ruta in (certificado, clave) + ((cadena,) if cadena else ()):
        if not Path(ruta).exists():
            raise ValueError(f"No existe {ruta}.")
    with tempfile.TemporaryDirectory() as tmp:
        entrada, salida = Path(tmp) / "perfil.mobileconfig", Path(tmp) / "firmado.mobileconfig"
        entrada.write_bytes(datos)
        cmd = [_openssl(), "smime", "-sign", "-signer", str(certificado), "-inkey", str(clave), "-nodetach",
               "-outform", "der", "-in", str(entrada), "-out", str(salida)]
        if cadena:
            cmd[cmd.index("-nodetach"):cmd.index("-nodetach")] = ["-certfile", str(cadena)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0 or not salida.exists():
            raise RuntimeError(f"openssl no pudo firmar: {r.stderr.strip() or r.stdout.strip()}")
        return salida.read_bytes()


def contenido_firmado(datos: bytes) -> bytes:
    """El perfil que va dentro de un .mobileconfig firmado (no comprueba en quién confía)."""
    with tempfile.TemporaryDirectory() as tmp:
        entrada = Path(tmp) / "firmado.mobileconfig"
        entrada.write_bytes(datos)
        r = subprocess.run([_openssl(), "smime", "-verify", "-noverify", "-inform", "der", "-in", str(entrada)],
                           capture_output=True)
        if r.returncode != 0 or not r.stdout:
            raise ValueError("la firma está dañada o incompleta")
        return r.stdout


def firma_confiable(datos: bytes, cafile: Path) -> bool:
    """¿La firma lleva a una raíz de [cafile]? (para probar antes de publicar)."""
    with tempfile.TemporaryDirectory() as tmp:
        entrada = Path(tmp) / "firmado.mobileconfig"
        entrada.write_bytes(datos)
        r = subprocess.run([_openssl(), "smime", "-verify", "-inform", "der", "-CAfile", str(cafile), "-in", str(entrada),
                            "-purpose", "any"], capture_output=True)
        return r.returncode == 0
