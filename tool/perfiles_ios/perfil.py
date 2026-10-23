"""Construye perfiles .mobileconfig a partir de un JSON de configuración y los datos del proyecto.

Formato del JSON (ver config/video_downloader_acceso.json):

    {
      "archivo": "video-downloader-acceso.mobileconfig",
      "identificador": "io.github.markoyam.videodownloader.acceso",
      "version": 1,
      "nombre": "Video Downloader · acceso directo",
      "organizacion": "Marco Yam",
      "descripcion": "Texto que verá la persona antes de instalar.",
      "fecha_creacion": "2026-10-23",
      "caducidad": {"tipo": "ninguna"}            // o {"tipo": "fecha", "fecha": "2027-10-23T00:00:00Z"}
                                                  // o {"tipo": "duracion", "dias": 365}
      "payloads": [
        {"tipo": "webclip", "url": "https://markoyam.github.io/video-downloader/",
         "etiqueta": "Video Downloader", "icono": "icono-webclip.png", "pantalla_completa": true}
      ]
    }

"etiqueta" e "icono" se toman del proyecto si se omiten ("icono": "proyecto" = el ícono de la app).
Los UUID se derivan del identificador y la versión: el mismo JSON da siempre el mismo archivo, y
subir "version" cambia los UUID (iOS lo trata como actualización por tener el mismo identificador).
"""

from __future__ import annotations

import datetime as dt
import json
import plistlib
import re
import tempfile
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from icono import errores_icono, preparar_icono
from proyecto import Proyecto
from validar import es_reverso_dns, promesas_falsas

ESPACIO_UUID = uuid.UUID("6f0c7a52-3d0e-4d8b-9a55-7b9f0d1c2e41")
RUTA_QUITAR = "Ajustes → General → VPN y gestión de dispositivos"


@dataclass
class ConfigPerfil:
    archivo: str
    identificador: str
    version: int
    nombre: str
    organizacion: str
    descripcion: str
    fecha_creacion: dt.date
    caducidad: Dict[str, Any]
    payloads: List[Dict[str, Any]]
    carpeta: Path = field(default_factory=Path)


def _fecha(texto: Any) -> Optional[dt.datetime]:
    if not isinstance(texto, str):
        return None
    try:
        valor = dt.datetime.fromisoformat(texto.replace("Z", "+00:00"))
    except ValueError:
        return None
    if valor.tzinfo is not None:
        valor = valor.astimezone(dt.timezone.utc).replace(tzinfo=None)
    return valor


def cargar_config(ruta: Path) -> Tuple[Optional[ConfigPerfil], List[str]]:
    """Lee y revisa el JSON. Devuelve (config, errores); con errores, config es None."""
    try:
        datos = json.loads(Path(ruta).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None, [f"No existe {ruta}."]
    except json.JSONDecodeError as e:
        return None, [f"{ruta}: JSON inválido en la línea {e.lineno}: {e.msg}."]
    if not isinstance(datos, dict):
        return None, [f"{ruta}: se esperaba un objeto JSON."]

    errores: List[str] = []
    for campo in ("archivo", "identificador", "version", "nombre", "organizacion", "descripcion", "fecha_creacion", "payloads"):
        if campo not in datos:
            errores.append(f"Falta el campo obligatorio '{campo}'.")
    archivo = datos.get("archivo", "")
    if "archivo" in datos and (not isinstance(archivo, str) or not re.fullmatch(r"[A-Za-z0-9._-]+\.mobileconfig", archivo)):
        errores.append("'archivo' debe ser un nombre simple que termine en .mobileconfig (sin carpetas ni espacios).")
    if "identificador" in datos and not es_reverso_dns(datos.get("identificador")):
        errores.append("'identificador' debe ser estilo DNS inverso (p. ej. io.github.markoyam.videodownloader.acceso).")
    version = datos.get("version")
    if "version" in datos and (not isinstance(version, int) or isinstance(version, bool) or version < 1):
        errores.append("'version' debe ser un entero de 1 en adelante.")
    for campo in ("nombre", "organizacion", "descripcion"):
        if campo in datos and (not isinstance(datos[campo], str) or not datos[campo].strip()):
            errores.append(f"'{campo}' debe ser un texto no vacío.")
    for frase in promesas_falsas(str(datos.get("descripcion", "")) + " " + str(datos.get("nombre", ""))):
        errores.append(f"La descripción promete algo que Apple no permite: «{frase}».")
    fecha = None
    if "fecha_creacion" in datos:
        try:
            fecha = dt.date.fromisoformat(str(datos["fecha_creacion"]))
        except ValueError:
            errores.append("'fecha_creacion' debe ser una fecha AAAA-MM-DD.")

    caducidad = datos.get("caducidad", {"tipo": "ninguna"})
    tipo = caducidad.get("tipo") if isinstance(caducidad, dict) else None
    if tipo not in ("ninguna", "fecha", "duracion"):
        errores.append("'caducidad.tipo' debe ser 'ninguna', 'fecha' o 'duracion'.")
    elif tipo == "fecha" and _fecha(caducidad.get("fecha")) is None:
        errores.append("'caducidad.fecha' debe ser una fecha ISO 8601 (p. ej. 2027-10-23T00:00:00Z).")
    elif tipo == "duracion":
        dias = caducidad.get("dias")
        if not isinstance(dias, (int, float)) or isinstance(dias, bool) or dias <= 0:
            errores.append("'caducidad.dias' debe ser un número mayor que 0.")

    payloads = datos.get("payloads")
    if "payloads" in datos:
        if not isinstance(payloads, list) or not payloads:
            errores.append("'payloads' debe ser una lista con al menos un elemento.")
        else:
            for i, p in enumerate(payloads):
                if not isinstance(p, dict) or p.get("tipo") != "webclip":
                    errores.append(f"payloads[{i}]: solo se admite el tipo 'webclip' (acceso directo, no sensible).")
                elif not isinstance(p.get("url"), str) or not p["url"].startswith("https://"):
                    errores.append(f"payloads[{i}]: 'url' debe empezar con https://.")

    if errores:
        return None, errores
    return ConfigPerfil(
        archivo=archivo,
        identificador=datos["identificador"],
        version=version,
        nombre=datos["nombre"].strip(),
        organizacion=datos["organizacion"].strip(),
        descripcion=datos["descripcion"].strip(),
        fecha_creacion=fecha,
        caducidad=caducidad,
        payloads=payloads,
        carpeta=Path(ruta).resolve().parent,
    ), []


def texto_caducidad(cfg: ConfigPerfil) -> str:
    """Cómo y cuándo se quita el perfil, sin prometer de más."""
    tipo = cfg.caducidad.get("tipo")
    if tipo == "fecha":
        fecha = _fecha(cfg.caducidad.get("fecha"))
        return f"iOS lo quitará solo el {fecha:%Y-%m-%d} (UTC); antes puedes quitarlo cuando quieras."
    if tipo == "duracion":
        return f"iOS lo quitará solo {cfg.caducidad['dias']:g} días después de instalarlo; antes puedes quitarlo cuando quieras."
    return ("No tiene fecha de eliminación automática: queda instalado hasta que lo quites. Eso no lo hace "
            "permanente: puedes quitarlo cuando quieras y futuras versiones de iOS podrían cambiar cómo funciona.")


def _icono(payload: Dict[str, Any], cfg: ConfigPerfil, proyecto: Proyecto) -> bytes:
    nombre = payload.get("icono", "proyecto")
    if nombre == "proyecto":
        if proyecto.icono_app is None:
            raise ValueError("El proyecto no tiene ícono de app (ios/Runner/Assets.xcassets/AppIcon.appiconset).")
        with tempfile.TemporaryDirectory() as tmp:
            return preparar_icono(proyecto.icono_app, Path(tmp) / "icono.png").read_bytes()
    ruta = (cfg.carpeta / str(nombre)).resolve()
    if not ruta.exists():
        raise ValueError(f"No existe el ícono {ruta}.")
    datos = ruta.read_bytes()
    problemas = errores_icono(datos)
    if problemas:
        raise ValueError(f"{ruta.name}: " + "; ".join(problemas))
    return datos


def textos(cfg: ConfigPerfil, proyecto: Proyecto) -> Dict[str, str]:
    """Descripción y consentimiento: qué configura, qué permisos pide y cómo quitarlo."""
    destinos = ", ".join(p["url"] for p in cfg.payloads)
    que_hace = f"Agrega a tu pantalla de inicio un acceso directo a {destinos}."
    permisos = ("No pide permisos ni lee datos del iPhone. No instala certificados, VPN, proxies, perfiles de "
                "administración (MDM) ni restricciones.")
    app = (f"Este perfil no instala la app {proyecto.nombre_visible}: solo abre su página de descargas. Las apps "
           "de iPhone necesitan una firma válida de Apple, que caduca (7 días con una cuenta gratuita).")
    quitar = f"Para quitarlo: {RUTA_QUITAR} → {cfg.nombre} → Eliminar perfil."
    descripcion = "\n\n".join([
        cfg.descripcion,
        f"Qué configura: {que_hace}",
        f"Permisos: {permisos}",
        app,
        f"Duración: {texto_caducidad(cfg)}",
        quitar,
        f"Versión {cfg.version} · creado el {cfg.fecha_creacion.isoformat()} · {cfg.organizacion}.",
    ])
    consentimiento = "\n\n".join([que_hace, permisos, app, quitar])
    return {"descripcion": descripcion, "consentimiento": consentimiento}


def construir_perfil(cfg: ConfigPerfil, proyecto: Proyecto) -> Dict[str, Any]:
    t = textos(cfg, proyecto)
    contenido = []
    for i, p in enumerate(cfg.payloads):
        sufijo = "webclip" if len(cfg.payloads) == 1 else f"webclip{i + 1}"
        pid = f"{cfg.identificador}.{sufijo}"
        contenido.append({
            "PayloadType": "com.apple.webClip.managed",
            "PayloadVersion": 1,
            "PayloadIdentifier": pid,
            "PayloadUUID": str(uuid.uuid5(ESPACIO_UUID, f"{pid}:{cfg.version}")).upper(),
            "PayloadDisplayName": f"Acceso directo: {p.get('etiqueta') or proyecto.nombre_visible}",
            "URL": p["url"],
            "Label": p.get("etiqueta") or proyecto.nombre_visible,
            "Icon": _icono(p, cfg, proyecto),
            "FullScreen": bool(p.get("pantalla_completa", True)),
            "IsRemovable": True,
            "Precomposed": True,
        })
    perfil: Dict[str, Any] = {
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": cfg.identificador,
        "PayloadUUID": str(uuid.uuid5(ESPACIO_UUID, f"{cfg.identificador}:{cfg.version}")).upper(),
        "PayloadDisplayName": cfg.nombre,
        "PayloadOrganization": cfg.organizacion,
        "PayloadDescription": t["descripcion"],
        "PayloadRemovalDisallowed": False,
        "TargetDeviceType": 1,  # iPhone/iPad: evita que iOS pregunte en qué dispositivo instalar
        "ConsentText": {"default": t["consentimiento"], "es": t["consentimiento"]},
        "PayloadContent": contenido,
    }
    tipo = cfg.caducidad.get("tipo")
    if tipo == "fecha":
        perfil["RemovalDate"] = _fecha(cfg.caducidad["fecha"])
    elif tipo == "duracion":
        perfil["DurationUntilRemoval"] = float(cfg.caducidad["dias"]) * 86400.0
    return perfil


def serializar(perfil: Dict[str, Any]) -> bytes:
    """XML con claves ordenadas: el mismo perfil da siempre los mismos bytes."""
    return plistlib.dumps(perfil, fmt=plistlib.FMT_XML, sort_keys=True)
