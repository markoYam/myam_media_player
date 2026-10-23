"""Página publicada (sin promesas falsas) y descarga real por HTTPS desde un servidor local."""

from __future__ import annotations

import datetime as dt
import functools
import hashlib
import http.server
import json
import ssl
import threading
import unittest
from pathlib import Path

from apoyo import CONFIG_EJEMPLO, HAY_OPENSSL, carpeta_temporal, certificado_prueba, perfil_ejemplo, serializar

from perfil import texto_caducidad
from proyecto import leer_proyecto
from sitio import Publicado, escribir_sitio, textos_publicos, pagina
from validar import promesas_falsas
from verificar import descargar, verificar_sitio

AHORA = dt.datetime(2026, 10, 23, 15, 0)


def _publicados():
    cfg, perfil = perfil_ejemplo()
    return [Publicado(cfg=cfg, perfil=perfil, datos=serializar(perfil), firmado=False)]


def _icono():
    return (CONFIG_EJEMPLO.parent / "icono-webclip.png").read_bytes()


class SitioTest(unittest.TestCase):
    def test_escribe_todo_y_el_estado_coincide(self):
        with carpeta_temporal() as tmp:
            destino = Path(tmp) / "sitio"
            escribir_sitio(_publicados(), leer_proyecto(), destino, _icono(), AHORA)
            for nombre in ("index.html", "perfiles.json", "icono.png", "_headers", "video-downloader-acceso.mobileconfig"):
                self.assertTrue((destino / nombre).exists(), nombre)
            estado = json.loads((destino / "perfiles.json").read_text(encoding="utf-8"))
            datos = (destino / "video-downloader-acceso.mobileconfig").read_bytes()
            self.assertEqual(estado["perfiles"][0]["sha256"], hashlib.sha256(datos).hexdigest())
            self.assertEqual(estado["version_app"], f"{leer_proyecto().version}+{leer_proyecto().build}")
            self.assertIn("application/x-apple-aspen-config", (destino / "_headers").read_text(encoding="utf-8"))

    def test_la_pagina_informa_lo_necesario(self):
        texto = textos_publicos(pagina(_publicados(), leer_proyecto(), AHORA))
        for frase in ("No instala la app", "7 días", "No verificado", "VPN y gestión de dispositivos",
                      "Eliminar perfil", "8 minutos", "Permisos", "Unión Europea"):
            self.assertIn(frase, texto)

    def test_no_anuncia_duracion_ilimitada(self):
        """La app depende de firmas que caducan: ni la página ni el perfil pueden prometer lo contrario."""
        publicados = _publicados()
        texto = textos_publicos(pagina(publicados, leer_proyecto(), AHORA))
        self.assertEqual(promesas_falsas(texto), [])
        perfil = publicados[0].perfil
        for t in [perfil["PayloadDescription"], *perfil["ConsentText"].values(), texto_caducidad(publicados[0].cfg)]:
            self.assertEqual(promesas_falsas(t), [], t)
        self.assertIn("caduca", perfil["ConsentText"]["es"])

    def test_se_niega_a_publicar_promesas_falsas(self):
        publicados = _publicados()
        publicados[0].cfg.descripcion = "Perfil permanente que instala la app sin firma."
        with carpeta_temporal() as tmp, self.assertRaises(ValueError):
            escribir_sitio(publicados, leer_proyecto(), Path(tmp), _icono(), AHORA)

    def test_detector_de_promesas(self):
        self.assertEqual(promesas_falsas("Este perfil no instala la app."), [])
        self.assertEqual(promesas_falsas("Eso no lo hace permanente."), [])
        self.assertTrue(promesas_falsas("El perfil no caduca."))
        self.assertTrue(promesas_falsas("Instala cualquier IPA."))


class _Manejador(http.server.SimpleHTTPRequestHandler):
    tipo = "application/x-apple-aspen-config"

    def guess_type(self, path):
        if str(path).endswith(".mobileconfig"):
            return self.tipo
        return super().guess_type(path)

    def log_message(self, *args):  # silencio en las pruebas
        pass


@unittest.skipUnless(HAY_OPENSSL, "requiere openssl para el certificado de prueba")
class DescargaHttpsTest(unittest.TestCase):
    """Sirve el sitio generado por HTTPS en 127.0.0.1 y lo revisa con `verificar`, como en producción."""

    def setUp(self):
        self._tmp = carpeta_temporal()
        tmp = Path(self._tmp.name)
        self.sitio = tmp / "sitio"
        escribir_sitio(_publicados(), leer_proyecto(), self.sitio, _icono(), AHORA)
        self.cert, clave = certificado_prueba(tmp)
        self.contexto = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.contexto.load_cert_chain(self.cert, clave)
        self.servidores = []

    def tearDown(self):
        for s in self.servidores:
            s.shutdown()
            s.server_close()
        self._tmp.cleanup()

    def _servir(self, tipo):
        manejador = type("M", (_Manejador,), {"tipo": tipo})
        servidor = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(manejador, directory=str(self.sitio)))
        servidor.socket = self.contexto.wrap_socket(servidor.socket, server_side=True)
        threading.Thread(target=servidor.serve_forever, daemon=True).start()
        self.servidores.append(servidor)
        return f"https://localhost:{servidor.server_address[1]}/"

    def test_descarga_y_verifica_por_https(self):
        base = self._servir("application/x-apple-aspen-config")
        estado, tipo, datos = descargar(base + "video-downloader-acceso.mobileconfig", cafile=self.cert)
        self.assertEqual(estado, 200)
        self.assertEqual(tipo, "application/x-apple-aspen-config")
        self.assertEqual(datos, (self.sitio / "video-downloader-acceso.mobileconfig").read_bytes())
        ok, informe = verificar_sitio(base, cafile=self.cert)
        self.assertTrue(ok, informe)
        self.assertTrue(any("tipo de contenido correcto" in l for l in informe))

    def test_octet_stream_avisa_y_text_plain_falla(self):
        ok, informe = verificar_sitio(self._servir("application/octet-stream"), cafile=self.cert)
        self.assertTrue(ok)
        self.assertTrue(any(l.startswith("⚠") for l in informe))
        ok, informe = verificar_sitio(self._servir("text/plain"), cafile=self.cert)
        self.assertFalse(ok)

    def test_archivo_cambiado_o_dañado(self):
        base = self._servir("application/x-apple-aspen-config")
        archivo = self.sitio / "video-downloader-acceso.mobileconfig"
        archivo.write_bytes(archivo.read_bytes()[:-300])
        ok, informe = verificar_sitio(base, cafile=self.cert)
        self.assertFalse(ok)
        self.assertTrue(any("SHA-256 no coincide" in l for l in informe))
        self.assertTrue(any("dañado o incompleto" in l for l in informe))

    def test_archivo_que_falta(self):
        base = self._servir("application/x-apple-aspen-config")
        (self.sitio / "video-downloader-acceso.mobileconfig").unlink()
        ok, informe = verificar_sitio(base, cafile=self.cert)
        self.assertFalse(ok)
        self.assertTrue(any("HTTP 404" in l for l in informe))

    def test_certificado_no_confiable_falla(self):
        ok, informe = verificar_sitio(self._servir("application/x-apple-aspen-config"))
        self.assertFalse(ok)

    def test_solo_https(self):
        with self.assertRaises(ValueError):
            descargar("http://localhost/perfiles.json")


if __name__ == "__main__":
    unittest.main()
