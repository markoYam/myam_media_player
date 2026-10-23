"""Genera la página estática de descarga (docs/perfiles/ → markoyam.github.io/myam_media_player/perfiles/, u otro hosting HTTPS).

Archivos que escribe en la carpeta destino:
- index.html: perfiles, qué hacen, cómo instalarlos y quitarlos, la verdad sobre la app en iPhone y el
  estado de lo publicado (versión, fecha, tamaño, SHA-256, firma, caducidad).
- *.mobileconfig: los perfiles.
- perfiles.json: el mismo estado, para `verificar`.
- icono.png: el ícono de la app.
- _headers: tipo de contenido correcto en Cloudflare Pages o Netlify (GitHub Pages no lo lee).
"""

from __future__ import annotations

import datetime as dt
import hashlib
import html
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List

from perfil import RUTA_QUITAR, ConfigPerfil, texto_caducidad
from proyecto import Proyecto
from validar import promesas_falsas

TIPO_CONTENIDO = "application/x-apple-aspen-config"


@dataclass
class Publicado:
    cfg: ConfigPerfil
    perfil: Dict[str, Any]
    datos: bytes
    firmado: bool


def estado(publicados: List[Publicado], proyecto: Proyecto, generado: dt.datetime) -> Dict[str, Any]:
    return {
        "app": proyecto.nombre_visible,
        "version_app": f"{proyecto.version}+{proyecto.build}",
        "bundle_id": proyecto.bundle_id,
        "generado": generado.replace(microsecond=0).isoformat() + "Z",
        "perfiles": [
            {
                "archivo": p.cfg.archivo,
                "nombre": p.cfg.nombre,
                "identificador": p.cfg.identificador,
                "version": p.cfg.version,
                "fecha_creacion": p.cfg.fecha_creacion.isoformat(),
                "bytes": len(p.datos),
                "sha256": hashlib.sha256(p.datos).hexdigest(),
                "firmado": p.firmado,
                "caducidad": texto_caducidad(p.cfg),
                "payloads": [c["PayloadType"] for c in p.perfil["PayloadContent"]],
                "destinos": [c.get("URL") for c in p.perfil["PayloadContent"]],
            }
            for p in publicados
        ],
    }


_CSS = """
/* Mismos colores que la página principal (docs/index.html). */
:root{--bg:#0F0A12;--surface:#1D1524;--surface-2:#17101C;--text:#F8F1F5;--muted:#B9AAC2;--primary:#E11D48;
--on-primary:#FFFFFF;--accent:#7DB3FA;--warn:#FFD479;--border:#33283D;--radius:20px}
@media (prefers-color-scheme: light){:root:not([data-theme="dark"]){--bg:#FFF1F2;--surface:#FFFFFF;--surface-2:#FFE4E8;
--text:#4C0519;--muted:#5B4A55;--primary:#E11D48;--on-primary:#FFFFFF;--accent:#1D4ED8;--warn:#7A4A00;--border:#FECDD3}}
*{box-sizing:border-box}
html{-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 Poppins,-apple-system,BlinkMacSystemFont,"Segoe UI",
Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:16px 16px 48px}
.volver{display:inline-flex;align-items:center;min-height:44px;color:var(--muted);text-decoration:none;font-weight:600}
header{display:flex;gap:16px;align-items:center;margin:8px 0 24px}
header img{width:72px;height:72px;border-radius:18px;flex:none}
h1{font-size:28px;line-height:1.15;margin:0;font-weight:800;letter-spacing:-.01em}
h2{font-size:21px;margin:32px 0 12px;font-weight:800}
h3{font-size:17px;margin:0 0 6px}
p{margin:0 0 12px;overflow-wrap:anywhere}
.muted{color:var(--muted)}
.card{background:var(--surface);border:1px solid var(--border);border-radius:var(--radius);padding:18px;margin:0 0 12px}
.chips{display:flex;flex-wrap:wrap;gap:8px;margin:10px 0 14px;padding:0;list-style:none}
.chips li{background:var(--surface-2);border:1px solid var(--border);border-radius:999px;padding:4px 12px;font-size:14px;
color:var(--muted)}
.chips li.warn{color:var(--warn)}
.btn{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:0 24px;border-radius:999px;
background:var(--primary);color:var(--on-primary);font-weight:700;text-decoration:none;
box-shadow:0 10px 30px -12px var(--primary)}
.btn:focus-visible,a:focus-visible{outline:3px solid var(--accent);outline-offset:3px}
a{color:var(--accent)}
ol,ul{padding-left:22px;margin:0 0 12px}
li{margin:4px 0;overflow-wrap:anywhere}
.tabla{width:100%;overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:14px;min-width:680px}
th,td{text-align:left;padding:8px;border-bottom:1px solid var(--border);vertical-align:top}
th{color:var(--muted);font-weight:600}
code{font:13px ui-monospace,SFMono-Regular,Menlo,monospace}
.nowrap{white-space:nowrap}
footer{margin-top:40px;color:var(--muted);font-size:14px}
@media (max-width:420px){h1{font-size:24px}header img{width:60px;height:60px}}
"""


def _e(texto: Any) -> str:
    return html.escape(str(texto), quote=True)


def _tamano(n: int) -> str:
    return f"{n / 1024:.1f} KB" if n >= 1024 else f"{n} B"


def pagina(publicados: List[Publicado], proyecto: Proyecto, generado: dt.datetime) -> str:
    tarjetas = []
    for p in publicados:
        destino = ", ".join(_e(c.get("URL")) for c in p.perfil["PayloadContent"])
        firma = "Firmado" if p.firmado else "Sin firmar: iOS lo mostrará como «No verificado»"
        tarjetas.append(f"""
<article class="card">
  <h3>{_e(p.cfg.nombre)}</h3>
  <p class="muted">{_e(p.cfg.descripcion)}</p>
  <ul class="chips" aria-label="Detalles del perfil">
    <li>Versión {p.cfg.version}</li>
    <li>Creado el {p.cfg.fecha_creacion.isoformat()}</li>
    <li>{_tamano(len(p.datos))}</li>
    <li class="{'' if p.firmado else 'warn'}">{_e(firma)}</li>
  </ul>
  <p><a class="btn" href="{_e(p.cfg.archivo)}" download>Descargar perfil</a></p>
  <p class="muted">Ábrelo en <strong>Safari</strong> en tu iPhone. Abre: {destino}.</p>
</article>""")

    filas = "".join(
        f"<tr><td><code class=\"nowrap\">{_e(p.cfg.archivo)}</code></td><td>{p.cfg.version}</td>"
        f"<td class=\"nowrap\">{p.cfg.fecha_creacion.isoformat()}</td><td class=\"nowrap\">{_tamano(len(p.datos))}</td>"
        f"<td>{'Sí' if p.firmado else 'No'}</td><td>{_e(texto_caducidad(p.cfg))}</td>"
        f"<td><code title=\"{hashlib.sha256(p.datos).hexdigest()}\">{hashlib.sha256(p.datos).hexdigest()[:16]}…</code></td></tr>"
        for p in publicados
    )
    nombre = _e(proyecto.nombre_visible)
    perfil_nombre = _e(publicados[0].cfg.nombre) if publicados else "el perfil"
    doc = f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{nombre} · Descargas</title>
<meta name="description" content="Acceso directo de {nombre} para iPhone y cómo instalar la app.">
<meta name="color-scheme" content="dark light">
<link rel="apple-touch-icon" href="icono.png">
<style>{_CSS}</style>
</head>
<body>
<main>
<a class="volver" href="../">← Volver a {nombre}</a>
<header>
  <img src="icono.png" alt="" width="72" height="72">
  <div>
    <h1>{nombre}</h1>
    <p class="muted">Versión {_e(proyecto.version)} · Creado por Marco Yam · Powered by Claude</p>
  </div>
</header>

<h2>Acceso directo para iPhone</h2>
{''.join(tarjetas)}

<h2>Qué hace el perfil</h2>
<div class="card">
  <ul>
    <li><strong>Configura:</strong> un ícono en tu pantalla de inicio que abre esta página.</li>
    <li><strong>Permisos:</strong> ninguno. No lee datos del iPhone ni pide tu información. No instala certificados,
      VPN, proxies, perfiles de administración (MDM) ni restricciones.</li>
    <li><strong>No instala la app.</strong> Las apps de iPhone necesitan una firma válida de Apple, y esa firma caduca
      (ver abajo). El perfil solo te trae a esta página.</li>
    <li><strong>Duración:</strong> {_e(texto_caducidad(publicados[0].cfg)) if publicados else ''}</li>
  </ul>
</div>

<h2>Cómo instalarlo</h2>
<div class="card">
  <ol>
    <li>Abre esta página en <strong>Safari</strong> en tu iPhone y toca <strong>Descargar perfil</strong>.</li>
    <li>Si Safari pregunta, toca <strong>Permitir</strong> y luego <strong>Cerrar</strong>.</li>
    <li>Abre <strong>Ajustes</strong>: arriba aparece <strong>Perfil descargado</strong>. Tócalo.</li>
    <li>Revisa lo que hace y toca <strong>Instalar</strong> (arriba a la derecha). iOS pedirá tu código.</li>
    <li>Hazlo antes de 8 minutos: si no, iOS borra el perfil descargado y hay que bajarlo otra vez.</li>
  </ol>
  <p class="muted">Si tienes activada la <em>Protección en caso de robo</em> y no estás en un lugar habitual, iOS puede
    pedirte esperar o desactivarla un momento para instalar perfiles.</p>
</div>

<h2>Cómo quitarlo</h2>
<div class="card">
  <p>{_e(RUTA_QUITAR)} → <strong>{perfil_nombre}</strong> → <strong>Eliminar perfil</strong>.
    El ícono de la pantalla de inicio desaparece con él.</p>
</div>

<h2>La app en iPhone</h2>
<div class="card">
  <p>Apple solo deja instalar apps firmadas, y toda firma caduca. Con lo que permite hoy:</p>
  <ul>
    <li><strong>Desde Xcode con una cuenta gratuita:</strong> en tu propio iPhone; dura 7 días y luego hay que volver a
      instalarla desde la Mac.</li>
    <li><strong>AltStore o SideStore:</strong> cada persona la firma con su Apple ID gratuito; dura 7 días y se renueva desde
      esa app.</li>
    <li><strong>Ad Hoc (Apple Developer Program, 99 USD al año):</strong> hasta 100 iPhones registrados por su UDID; el
      perfil de aprovisionamiento dura hasta un año.</li>
    <li><strong>TestFlight (misma membresía):</strong> versiones de prueba que caducan a los 90 días.</li>
  </ul>
  <p class="muted">Instalar apps directamente desde una página web solo existe en la Unión Europea; no está disponible en
    México.</p>
  <p><a href="../#descargar">Ir a la descarga de la app (APK para Android, IPA para AltStore / SideStore)</a></p>
</div>

<h2>Estado de lo publicado</h2>
<div class="card tabla">
  <table>
    <thead><tr><th>Archivo</th><th>Versión</th><th>Creado</th><th>Tamaño</th><th>Firmado</th><th>Duración</th><th>SHA-256</th></tr></thead>
    <tbody>{filas}</tbody>
  </table>
  <p class="muted">Generado el {generado:%Y-%m-%d %H:%M} UTC para {nombre} {_e(proyecto.version)}+{_e(proyecto.build)}.
    SHA-256 completo y demás datos en <a href="perfiles.json">perfiles.json</a>.</p>
</div>

<footer>Uso personal. {nombre} · Creado por Marco Yam · Powered by Claude</footer>
</main>
</body>
</html>
"""
    return doc


def textos_publicos(doc: str) -> str:
    """Texto visible aproximado (sin etiquetas), para revisar que no prometa de más."""
    import re

    sin_estilo = re.sub(r"<style>.*?</style>", " ", doc, flags=re.DOTALL)
    return html.unescape(re.sub(r"<[^>]+>", " ", sin_estilo))


def escribir_sitio(publicados: List[Publicado], proyecto: Proyecto, destino: Path, icono: bytes,
                   generado: dt.datetime) -> List[Path]:
    """Escribe el sitio en [destino]. Se niega si el texto visible promete algo que Apple no permite."""
    doc = pagina(publicados, proyecto, generado)
    falsas = promesas_falsas(textos_publicos(doc))
    if falsas:
        raise ValueError("La página promete algo que Apple no permite: " + ", ".join(f"«{f}»" for f in falsas))
    destino.mkdir(parents=True, exist_ok=True)
    escritos = []
    for p in publicados:
        ruta = destino / p.cfg.archivo
        ruta.write_bytes(p.datos)
        escritos.append(ruta)
    archivos = {
        "index.html": doc.encode("utf-8"),
        "perfiles.json": (json.dumps(estado(publicados, proyecto, generado), ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
        "icono.png": icono,
        "_headers": (
            "# Cloudflare Pages / Netlify: tipo correcto para que Safari ofrezca instalar el perfil.\n"
            "# (GitHub Pages ignora este archivo; usa `verificar` para ver qué tipo entrega.)\n"
            f"/*.mobileconfig\n  Content-Type: {TIPO_CONTENIDO}\n  X-Content-Type-Options: nosniff\n"
        ).encode("utf-8"),
    }
    for nombre, datos in archivos.items():
        ruta = destino / nombre
        ruta.write_bytes(datos)
        escritos.append(ruta)
    return escritos
