"""Perfiles de configuración iOS de Video Downloader.

Uso (desde la carpeta del proyecto):

    python3 tool/perfiles_ios proyecto                 # datos leídos del proyecto y avisos
    python3 tool/perfiles_ios generar                  # genera los .mobileconfig de config/*.json en build/perfiles_ios/
    python3 tool/perfiles_ios validar ARCHIVO...       # valida perfiles (también firmados)
    python3 tool/perfiles_ios publicar [--destino DIR] # genera la página del perfil en docs/perfiles/ (GitHub Pages)
         [--certificado C --clave K [--cadena X]]      #   firmando los perfiles, si das certificado y clave
    python3 tool/perfiles_ios verificar URL            # revisa el sitio ya publicado por HTTPS

La página va por defecto a docs/perfiles/: GitHub Pages publica la carpeta docs/ de este repositorio en
https://markoyam.github.io/myam_media_player/, así que queda en .../myam_media_player/perfiles/ al hacer push.
"""

from __future__ import annotations

import argparse
import datetime as dt
import sys
from pathlib import Path
from typing import List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))

from firmar import firmar  # noqa: E402
from perfil import cargar_config, construir_perfil, serializar  # noqa: E402
from proyecto import RAIZ_PROYECTO, leer_proyecto  # noqa: E402
from sitio import Publicado, escribir_sitio  # noqa: E402
from validar import validar_archivo, validar_perfil  # noqa: E402
from verificar import verificar_sitio  # noqa: E402

CARPETA_CONFIG = Path(__file__).resolve().parent / "config"
SALIDA = RAIZ_PROYECTO / "build" / "perfiles_ios"


def _configs(rutas: List[str]) -> List[Path]:
    return [Path(r) for r in rutas] if rutas else sorted(CARPETA_CONFIG.glob("*.json"))


def _construir(rutas: List[str], certificado: Optional[Path], clave: Optional[Path], cadena: Optional[Path]) -> List[Publicado]:
    proyecto = leer_proyecto()
    for aviso in proyecto.avisos:
        print(f"⚠ {aviso}")
    publicados: List[Publicado] = []
    fallos = 0
    for ruta in _configs(rutas):
        cfg, errores = cargar_config(ruta)
        if cfg is None:
            fallos += 1
            print(f"✗ {ruta.name}:")
            for e in errores:
                print(f"    {e}")
            continue
        try:
            perfil = construir_perfil(cfg, proyecto)
        except ValueError as e:
            fallos += 1
            print(f"✗ {ruta.name}: {e}")
            continue
        errores = validar_perfil(perfil)
        if errores:
            fallos += 1
            print(f"✗ {ruta.name}: el perfil generado no pasó la validación:")
            for e in errores:
                print(f"    {e}")
            continue
        datos = serializar(perfil)
        firmado = False
        if certificado and clave:
            datos = firmar(datos, certificado, clave, cadena)
            firmado = True
            errores = validar_archivo(datos)
            if errores:
                fallos += 1
                print(f"✗ {ruta.name}: tras firmarlo no pasó la validación: {'; '.join(errores)}")
                continue
        publicados.append(Publicado(cfg=cfg, perfil=perfil, datos=datos, firmado=firmado))
        print(f"✓ {cfg.archivo} · {cfg.identificador} · versión {cfg.version}{' · firmado' if firmado else ''}")
    if fallos:
        raise SystemExit(f"{fallos} perfil(es) con errores: no se escribió nada.")
    if not publicados:
        raise SystemExit("No hay configuraciones en tool/perfiles_ios/config/.")
    return publicados


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="perfiles_ios", description="Perfiles de configuración iOS de Video Downloader")
    sub = ap.add_subparsers(dest="comando", required=True)
    sub.add_parser("proyecto", help="datos leídos del proyecto")

    g = sub.add_parser("generar", help="genera los .mobileconfig")
    g.add_argument("configs", nargs="*")
    g.add_argument("--salida", type=Path, default=SALIDA)

    v = sub.add_parser("validar", help="valida archivos .mobileconfig")
    v.add_argument("archivos", nargs="+", type=Path)

    pub = sub.add_parser("publicar", help="genera el sitio de descarga")
    pub.add_argument("configs", nargs="*")
    pub.add_argument("--destino", type=Path, default=RAIZ_PROYECTO / "docs" / "perfiles")
    for nombre in ("--certificado", "--clave", "--cadena"):
        pub.add_argument(nombre, type=Path)

    ver = sub.add_parser("verificar", help="revisa el sitio publicado")
    ver.add_argument("url")
    ver.add_argument("--cafile", type=Path, help="CA propia (solo para pruebas locales)")

    a = ap.parse_args(argv)

    if a.comando == "proyecto":
        p = leer_proyecto()
        print(f"App: {p.nombre_visible} ({p.nombre_paquete}) {p.version}+{p.build}")
        print(f"Bundle id (Runner): {p.bundle_id}")
        print(f"Ícono: {p.icono_app}")
        for aviso in p.avisos:
            print(f"⚠ {aviso}")
        return 0

    if a.comando == "generar":
        publicados = _construir(a.configs, None, None, None)
        a.salida.mkdir(parents=True, exist_ok=True)
        for p in publicados:
            (a.salida / p.cfg.archivo).write_bytes(p.datos)
        print(f"Listo en {a.salida}")
        return 0

    if a.comando == "validar":
        malos = 0
        for ruta in a.archivos:
            errores = ["No existe el archivo."] if not ruta.exists() else validar_archivo(ruta.read_bytes())
            if errores:
                malos += 1
                print(f"✗ {ruta}")
                for e in errores:
                    print(f"    {e}")
            else:
                print(f"✓ {ruta}")
        return 1 if malos else 0

    if a.comando == "publicar":
        if bool(a.certificado) != bool(a.clave):
            ap.error("--certificado y --clave van juntos.")
        publicados = _construir(a.configs, a.certificado, a.clave, a.cadena)
        icono = (CARPETA_CONFIG / "icono-webclip.png").read_bytes()
        escritos = escribir_sitio(publicados, leer_proyecto(), a.destino, icono, dt.datetime.now(dt.timezone.utc).replace(tzinfo=None))
        print(f"Listo en {a.destino} ({len(escritos)} archivos). Súbelo con git (commit + push) y revisa con:")
        print("  python3 tool/perfiles_ios verificar https://markoyam.github.io/myam_media_player/perfiles/")
        return 0

    if a.comando == "verificar":
        ok, informe = verificar_sitio(a.url, a.cafile)
        print("\n".join(informe))
        return 0 if ok else 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
