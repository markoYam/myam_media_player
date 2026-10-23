"""Validación estricta de perfiles de configuración (.mobileconfig) antes de publicarlos.

Las claves y tipos siguen la referencia de Apple (Device Management → TopLevel y WebClip). Solo se
permiten por defecto payloads no sensibles: un perfil que instale certificados raíz, VPN, proxies, MDM,
Wi-Fi, cuentas o restricciones se rechaza aunque la estructura sea correcta.
"""

from __future__ import annotations

import datetime as dt
import plistlib
import re
import uuid
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

from icono import errores_icono

# Claves de primer nivel documentadas por Apple (TopLevel).
CLAVES_NIVEL_SUPERIOR = {
    "PayloadContent": list,
    "PayloadDescription": str,
    "PayloadDisplayName": str,
    "PayloadExpirationDate": dt.datetime,
    "PayloadIdentifier": str,
    "PayloadOrganization": str,
    "PayloadRemovalDisallowed": bool,
    "PayloadScope": str,
    "PayloadType": str,
    "PayloadUUID": str,
    "PayloadVersion": int,
    "RemovalDate": dt.datetime,
    "DurationUntilRemoval": (int, float),
    "ConsentText": dict,
    "TargetDeviceType": int,
}
OBLIGATORIAS_NIVEL_SUPERIOR = ("PayloadContent", "PayloadIdentifier", "PayloadType", "PayloadUUID", "PayloadVersion")

# Comunes a todo payload.
CLAVES_PAYLOAD_COMUNES = {
    "PayloadType": str,
    "PayloadVersion": int,
    "PayloadIdentifier": str,
    "PayloadUUID": str,
    "PayloadDisplayName": str,
    "PayloadDescription": str,
    "PayloadOrganization": str,
}

# Web Clip (com.apple.webClip.managed): acceso directo en la pantalla de inicio. No sensible.
CLAVES_WEBCLIP = {
    "URL": str,
    "Label": str,
    "Icon": bytes,
    "FullScreen": bool,
    "IsRemovable": bool,
    "Precomposed": bool,
    "IgnoreManifestScope": bool,
    "TargetApplicationBundleIdentifier": str,
}

PAYLOADS_PERMITIDOS = {"com.apple.webClip.managed"}

# Payloads sensibles: nunca se publican por defecto (motivo para el mensaje).
PAYLOADS_SENSIBLES = {
    "com.apple.security.root": "instala un certificado raíz de confianza",
    "com.apple.security.pkcs1": "instala un certificado",
    "com.apple.security.pem": "instala un certificado",
    "com.apple.security.pkcs12": "instala un certificado con clave privada",
    "com.apple.security.scep": "solicita certificados (SCEP)",
    "com.apple.security.acme": "solicita certificados (ACME)",
    "com.apple.vpn.managed": "configura una VPN",
    "com.apple.vpn.managed.applayer": "configura una VPN por app",
    "com.apple.proxy.http.global": "configura un proxy global",
    "com.apple.mdm": "inscribe el iPhone en un MDM",
    "com.apple.dnsSettings.managed": "cambia el DNS",
    "com.apple.dnsProxy.managed": "configura un proxy DNS",
    "com.apple.webcontent-filter": "filtra el tráfico web",
    "com.apple.relay.managed": "enruta el tráfico por un relay",
    "com.apple.wifi.managed": "configura una red Wi-Fi",
    "com.apple.eap.managed": "configura autenticación de red",
    "com.apple.cellular": "cambia la configuración celular",
    "com.apple.apn.managed": "cambia el APN",
    "com.apple.eas.account": "agrega una cuenta de correo Exchange",
    "com.apple.mail.managed": "agrega una cuenta de correo",
    "com.apple.applicationaccess": "aplica restricciones al iPhone",
    "com.apple.mobiledevice.passwordpolicy": "impone una política de código",
    "com.apple.app.lock": "bloquea el iPhone en una app",
    "com.apple.notificationsettings": "cambia las notificaciones",
}

_REVERSO_DNS = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$")

# Frases que no se pueden afirmar: un perfil no instala apps ni garantiza duración ilimitada.
_PROMESAS_FALSAS = [
    re.compile(r"\b(permanente(s|mente)?|para siempre|ilimitad[oa]s?|sin caducidad|nunca caduca|no caduca|no expira|nunca expira)\b", re.IGNORECASE),
    re.compile(r"\binstala(r)? (la |cualquier )?(app|aplicaci[oó]n|ipa)\b", re.IGNORECASE),
    re.compile(r"\bsin firma\b", re.IGNORECASE),
]


_NEGACION_PREVIA = re.compile(r"\b(no|ni|nunca|jam[aá]s)\b[^.;:]{0,20}$", re.IGNORECASE)


def promesas_falsas(texto: str) -> List[str]:
    """Frases de [texto] que prometen algo que Apple no permite (duración ilimitada, instalar apps).

    "No instala la app" o "no es permanente" son advertencias correctas y no cuentan; "no caduca" sí
    (es una promesa en sí misma).
    """
    texto = texto or ""
    hallazgos = []
    for patron in _PROMESAS_FALSAS:
        for m in patron.finditer(texto):
            frase = m.group(0)
            promesa_negativa = re.match(r"(no|nunca)\b", frase, re.IGNORECASE)
            if not promesa_negativa and _NEGACION_PREVIA.search(texto[max(0, m.start() - 30):m.start()]):
                continue
            hallazgos.append(frase)
    return hallazgos


def es_uuid(valor: Any) -> bool:
    if not isinstance(valor, str):
        return False
    try:
        uuid.UUID(valor)
    except ValueError:
        return False
    return len(valor) == 36


def es_reverso_dns(valor: Any) -> bool:
    return isinstance(valor, str) and bool(_REVERSO_DNS.match(valor))


def _tipo_ok(valor: Any, tipo: Any) -> bool:
    # bool es subclase de int en Python: True no cuenta como entero ni un entero como booleano.
    if isinstance(valor, bool):
        return tipo is bool
    return isinstance(valor, tipo)


def _revisar_claves(d: Dict[str, Any], esquema: Dict[str, Any], donde: str, errores: List[str]) -> None:
    for clave, valor in d.items():
        if clave not in esquema:
            errores.append(f"{donde}: clave desconocida '{clave}' (no está en la referencia de Apple).")
        elif not _tipo_ok(valor, esquema[clave]):
            errores.append(f"{donde}: '{clave}' tiene un tipo incorrecto.")


def validar_perfil(perfil: Any, permitir: Iterable[str] = (), ahora: Optional[dt.datetime] = None) -> List[str]:
    """Errores del perfil (lista vacía = válido para publicar)."""
    errores: List[str] = []
    if not isinstance(perfil, dict):
        return ["El perfil no es un diccionario de propiedades."]
    permitidos: Set[str] = set(PAYLOADS_PERMITIDOS) | set(permitir)
    ahora = ahora or dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)

    for clave in OBLIGATORIAS_NIVEL_SUPERIOR:
        if clave not in perfil:
            errores.append(f"Falta la clave obligatoria '{clave}'.")
    _revisar_claves(perfil, CLAVES_NIVEL_SUPERIOR, "Perfil", errores)

    if perfil.get("PayloadType") not in (None, "Configuration"):
        errores.append("PayloadType del perfil debe ser 'Configuration'.")
    if "PayloadVersion" in perfil and perfil.get("PayloadVersion") != 1:
        errores.append("PayloadVersion del perfil debe ser 1.")
    if "PayloadIdentifier" in perfil and not es_reverso_dns(perfil.get("PayloadIdentifier")):
        errores.append("PayloadIdentifier debe ser estilo DNS inverso (p. ej. io.github.markoyam.videodownloader).")
    if "PayloadUUID" in perfil and not es_uuid(perfil.get("PayloadUUID")):
        errores.append("PayloadUUID no es un UUID válido.")
    if not str(perfil.get("PayloadDisplayName") or "").strip():
        errores.append("Falta un nombre visible (PayloadDisplayName): iOS lo muestra al instalar.")
    if not str(perfil.get("PayloadDescription") or "").strip():
        errores.append("Falta la descripción (PayloadDescription): debe decir qué configura y cómo quitarlo.")
    if perfil.get("PayloadRemovalDisallowed") is True:
        errores.append("PayloadRemovalDisallowed = true no se permite: el usuario siempre debe poder quitar el perfil.")
    if "PayloadScope" in perfil and perfil.get("PayloadScope") not in ("System", "User"):
        errores.append("PayloadScope debe ser 'System' o 'User'.")
    if "TargetDeviceType" in perfil and perfil.get("TargetDeviceType") not in range(0, 7):
        errores.append("TargetDeviceType debe estar entre 0 y 6.")

    # Caducidad: opcional; si viene, debe tener sentido.
    removal = perfil.get("RemovalDate")
    if isinstance(removal, dt.datetime) and removal <= ahora:
        errores.append("RemovalDate ya pasó: iOS quitaría el perfil en cuanto se instale.")
    duracion = perfil.get("DurationUntilRemoval")
    if isinstance(duracion, (int, float)) and not isinstance(duracion, bool) and duracion <= 0:
        errores.append("DurationUntilRemoval debe ser mayor que 0 segundos.")
    expira = perfil.get("PayloadExpirationDate")
    if isinstance(expira, dt.datetime) and expira <= ahora:
        errores.append("PayloadExpirationDate ya pasó.")

    consent = perfil.get("ConsentText")
    if isinstance(consent, dict):
        for idioma, texto in consent.items():
            if not isinstance(idioma, str) or not isinstance(texto, str) or not texto.strip():
                errores.append("ConsentText debe ser idioma → texto no vacío.")

    for campo in ("PayloadDescription", "PayloadDisplayName"):
        for frase in promesas_falsas(str(perfil.get(campo) or "")):
            errores.append(f"{campo} promete algo que Apple no permite: «{frase}».")
    if isinstance(consent, dict):
        for texto in consent.values():
            for frase in promesas_falsas(str(texto)):
                errores.append(f"ConsentText promete algo que Apple no permite: «{frase}».")

    contenido = perfil.get("PayloadContent")
    if "PayloadContent" in perfil:
        if not isinstance(contenido, list) or not contenido:
            errores.append("PayloadContent debe ser una lista con al menos un payload.")
            contenido = []
    else:
        contenido = []

    identificadores = {perfil.get("PayloadIdentifier")}
    uuids = {perfil.get("PayloadUUID")}
    for i, payload in enumerate(contenido):
        donde = f"Payload {i + 1}"
        if not isinstance(payload, dict):
            errores.append(f"{donde}: no es un diccionario.")
            continue
        tipo = payload.get("PayloadType")
        for clave in ("PayloadType", "PayloadVersion", "PayloadIdentifier", "PayloadUUID"):
            if clave not in payload:
                errores.append(f"{donde}: falta la clave obligatoria '{clave}'.")
        if payload.get("PayloadVersion", 1) != 1:
            errores.append(f"{donde}: PayloadVersion debe ser 1.")
        pid = payload.get("PayloadIdentifier")
        if pid is not None and not es_reverso_dns(pid):
            errores.append(f"{donde}: PayloadIdentifier debe ser estilo DNS inverso.")
        elif pid in identificadores:
            errores.append(f"{donde}: PayloadIdentifier repetido ({pid}).")
        identificadores.add(pid)
        puid = payload.get("PayloadUUID")
        if puid is not None and not es_uuid(puid):
            errores.append(f"{donde}: PayloadUUID no es un UUID válido.")
        elif puid is not None and str(puid).lower() in {str(u).lower() for u in uuids if u}:
            errores.append(f"{donde}: PayloadUUID repetido ({puid}).")
        uuids.add(puid)

        if tipo in PAYLOADS_SENSIBLES and tipo not in permitidos:
            errores.append(f"{donde}: {tipo} {PAYLOADS_SENSIBLES[tipo]}; no se publica por defecto.")
            continue
        if tipo not in permitidos:
            errores.append(f"{donde}: el tipo '{tipo}' no está permitido (solo {', '.join(sorted(permitidos))}).")
            continue
        if tipo == "com.apple.webClip.managed":
            _validar_webclip(payload, donde, errores)
    return errores


def _validar_webclip(p: Dict[str, Any], donde: str, errores: List[str]) -> None:
    _revisar_claves(p, {**CLAVES_PAYLOAD_COMUNES, **CLAVES_WEBCLIP}, donde, errores)
    url = p.get("URL")
    if not isinstance(url, str) or not url.strip():
        errores.append(f"{donde}: el Web Clip necesita URL.")
    elif not url.startswith("https://"):
        errores.append(f"{donde}: la URL del Web Clip debe ser https:// ({url}).")
    if not str(p.get("Label") or "").strip():
        errores.append(f"{donde}: el Web Clip necesita Label (nombre en la pantalla de inicio).")
    icono = p.get("Icon")
    if icono is None:
        errores.append(f"{donde}: falta Icon; sin él iOS muestra un cuadro blanco.")
    elif isinstance(icono, bytes):
        errores.extend(f"{donde}: {e}" for e in errores_icono(icono))
    if "TargetApplicationBundleIdentifier" in p:
        errores.append(f"{donde}: TargetApplicationBundleIdentifier solo funciona instalado por MDM.")
    if p.get("IsRemovable") is False:
        errores.append(f"{donde}: IsRemovable = false no se permite: el usuario debe poder quitar el acceso directo.")


# ---- archivos ----

def es_firmado(datos: bytes) -> bool:
    """Un perfil firmado es CMS/PKCS#7 en DER: empieza con una SEQUENCE (0x30) y no es XML ni plist binario."""
    return len(datos) > 2 and datos[0] == 0x30 and datos[1] in (0x80, 0x81, 0x82, 0x83, 0x84)


def leer_perfil(datos: bytes) -> Tuple[Optional[Dict[str, Any]], List[str]]:
    """Lee un .mobileconfig (XML o binario; si está firmado, extrae el contenido con openssl)."""
    if not datos:
        return None, ["El archivo está vacío."]
    contenido = datos
    if es_firmado(datos):
        from firmar import contenido_firmado

        try:
            contenido = contenido_firmado(datos)
        except (RuntimeError, ValueError) as e:
            return None, [f"Perfil firmado ilegible: {e}"]
    try:
        perfil = plistlib.loads(contenido)
    except Exception as e:  # noqa: BLE001 - cualquier daño del archivo es un error de validación
        return None, [f"El archivo no es una lista de propiedades válida (¿dañado o incompleto?): {type(e).__name__}."]
    if not isinstance(perfil, dict):
        return None, ["El archivo no contiene un perfil (se esperaba un diccionario)."]
    return perfil, []


def validar_archivo(datos: bytes, permitir: Iterable[str] = ()) -> List[str]:
    perfil, errores = leer_perfil(datos)
    if perfil is None:
        return errores
    return validar_perfil(perfil, permitir=permitir)
