"""Utilidades comunes de las pruebas: rutas, perfil de ejemplo del proyecto y certificados de prueba."""

from __future__ import annotations

import copy
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

PAQUETE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PAQUETE))

from perfil import cargar_config, construir_perfil, serializar  # noqa: E402
from proyecto import leer_proyecto  # noqa: E402

CONFIG_EJEMPLO = PAQUETE / "config" / "video_downloader_acceso.json"
HAY_OPENSSL = shutil.which("openssl") is not None


def perfil_ejemplo():
    """(config, perfil) del ejemplo real del proyecto."""
    cfg, errores = cargar_config(CONFIG_EJEMPLO)
    assert cfg is not None, errores
    return cfg, construir_perfil(cfg, leer_proyecto())


def copia(perfil):
    return copy.deepcopy(perfil)


def certificado_prueba(carpeta: Path, nombre: str = "prueba", cn: str = "localhost"):
    """Certificado autofirmado SOLO para pruebas (se crea en una carpeta temporal y se borra)."""
    cert, clave = carpeta / f"{nombre}.pem", carpeta / f"{nombre}.key"
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", f"/CN={cn}",
         "-addext", "subjectAltName=DNS:localhost,IP:127.0.0.1", "-keyout", str(clave), "-out", str(cert)],
        check=True, capture_output=True,
    )
    return cert, clave


def carpeta_temporal():
    return tempfile.TemporaryDirectory()


__all__ = ["PAQUETE", "CONFIG_EJEMPLO", "HAY_OPENSSL", "perfil_ejemplo", "copia", "certificado_prueba",
           "carpeta_temporal", "serializar"]
