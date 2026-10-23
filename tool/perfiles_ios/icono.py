"""Ícono del Web Clip: PNG cuadrado de 400×400 como máximo y menos de 1 MB sin comprimir (Apple)."""

from __future__ import annotations

import shutil
import struct
import subprocess
from pathlib import Path
from typing import List, Optional, Tuple

FIRMA_PNG = b"\x89PNG\r\n\x1a\n"
LADO_MAXIMO = 400
BYTES_SIN_COMPRIMIR_MAX = 1024 * 1024


def tamano_png(datos: bytes) -> Optional[Tuple[int, int]]:
    """(ancho, alto) leído de la cabecera IHDR; None si no es un PNG válido."""
    if len(datos) < 24 or not datos.startswith(FIRMA_PNG) or datos[12:16] != b"IHDR":
        return None
    ancho, alto = struct.unpack(">II", datos[16:24])
    return (ancho, alto) if ancho > 0 and alto > 0 else None


def errores_icono(datos: bytes) -> List[str]:
    """Problemas del ícono para un Web Clip (lista vacía = válido)."""
    medida = tamano_png(datos)
    if medida is None:
        return ["El ícono no es un PNG válido."]
    ancho, alto = medida
    errores = []
    if ancho != alto:
        errores.append(f"El ícono debe ser cuadrado (es {ancho}×{alto}).")
    if max(ancho, alto) > LADO_MAXIMO:
        errores.append(f"El ícono mide {ancho}×{alto}; Apple pide {LADO_MAXIMO}×{LADO_MAXIMO} como máximo.")
    if ancho * alto * 4 >= BYTES_SIN_COMPRIMIR_MAX:
        errores.append("El ícono ocupa 1 MB o más sin comprimir.")
    return errores


def preparar_icono(origen: Path, destino: Path) -> Path:
    """Copia [origen] a [destino] reducido a 400×400 con `sips` (incluido en macOS).

    Si ya cumple, solo lo copia. Fuera de macOS (sin sips), pide un PNG ya preparado.
    """
    datos = origen.read_bytes()
    if not errores_icono(datos):
        destino.write_bytes(datos)
        return destino
    if shutil.which("sips") is None:
        raise ValueError(
            f"{origen} no cumple ({'; '.join(errores_icono(datos))}) y aquí no está `sips` para reducirlo. "
            "Usa un PNG cuadrado de 400×400 o menos."
        )
    destino.write_bytes(datos)
    subprocess.run(["sips", "-z", str(LADO_MAXIMO), str(LADO_MAXIMO), str(destino)], check=True, capture_output=True)
    problemas = errores_icono(destino.read_bytes())
    if problemas:
        raise ValueError("No se pudo preparar el ícono: " + "; ".join(problemas))
    return destino
