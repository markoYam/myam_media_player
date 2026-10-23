"""Estructura, identificadores únicos, campos obligatorios, payloads sensibles y archivos dañados."""

from __future__ import annotations

import datetime as dt
import os
import unittest
import uuid
from pathlib import Path

from apoyo import HAY_OPENSSL, carpeta_temporal, certificado_prueba, copia, perfil_ejemplo, serializar

from firmar import firma_confiable, firmar
from proyecto import RAIZ_PROYECTO, ICONO_APP
from validar import PAYLOADS_SENSIBLES, es_firmado, leer_perfil, validar_archivo, validar_perfil


def _tiene(errores, texto):
    return any(texto in e for e in errores)


class EstructuraTest(unittest.TestCase):
    def setUp(self):
        self.cfg, self.perfil = perfil_ejemplo()

    def test_el_perfil_de_ejemplo_es_valido(self):
        self.assertEqual(validar_perfil(self.perfil), [])
        self.assertEqual(validar_archivo(serializar(self.perfil)), [])

    def test_es_reproducible(self):
        _, otro = perfil_ejemplo()
        self.assertEqual(serializar(self.perfil), serializar(otro))

    def test_tipo_y_version_de_formato(self):
        p = copia(self.perfil)
        p["PayloadType"] = "Otra"
        p["PayloadVersion"] = 2
        errores = validar_perfil(p)
        self.assertTrue(_tiene(errores, "'Configuration'"))
        self.assertTrue(_tiene(errores, "PayloadVersion del perfil debe ser 1"))

    def test_un_booleano_no_cuenta_como_entero(self):
        p = copia(self.perfil)
        p["PayloadVersion"] = True
        self.assertTrue(_tiene(validar_perfil(p), "tipo incorrecto"))

    def test_clave_desconocida(self):
        p = copia(self.perfil)
        p["InventadaPorMi"] = "x"
        self.assertTrue(_tiene(validar_perfil(p), "clave desconocida 'InventadaPorMi'"))

    def test_no_se_permite_impedir_quitarlo(self):
        p = copia(self.perfil)
        p["PayloadRemovalDisallowed"] = True
        self.assertTrue(_tiene(validar_perfil(p), "PayloadRemovalDisallowed"))
        p = copia(self.perfil)
        p["PayloadContent"][0]["IsRemovable"] = False
        self.assertTrue(_tiene(validar_perfil(p), "IsRemovable"))


class CamposObligatoriosTest(unittest.TestCase):
    def setUp(self):
        _, self.perfil = perfil_ejemplo()

    def test_cada_clave_obligatoria_del_perfil(self):
        for clave in ("PayloadContent", "PayloadIdentifier", "PayloadType", "PayloadUUID", "PayloadVersion"):
            with self.subTest(clave=clave):
                p = copia(self.perfil)
                del p[clave]
                self.assertTrue(_tiene(validar_perfil(p), f"'{clave}'"))

    def test_nombre_y_descripcion_visibles(self):
        for clave in ("PayloadDisplayName", "PayloadDescription"):
            with self.subTest(clave=clave):
                p = copia(self.perfil)
                p[clave] = "  "
                self.assertTrue(_tiene(validar_perfil(p), clave))

    def test_cada_clave_obligatoria_del_payload(self):
        for clave in ("PayloadType", "PayloadVersion", "PayloadIdentifier", "PayloadUUID"):
            with self.subTest(clave=clave):
                p = copia(self.perfil)
                del p["PayloadContent"][0][clave]
                self.assertTrue(_tiene(validar_perfil(p), f"'{clave}'"))

    def test_web_clip_necesita_url_https_etiqueta_e_icono(self):
        p = copia(self.perfil)
        p["PayloadContent"][0]["URL"] = "http://markoyam.github.io/video-downloader/"
        self.assertTrue(_tiene(validar_perfil(p), "https://"))
        p = copia(self.perfil)
        del p["PayloadContent"][0]["Label"]
        self.assertTrue(_tiene(validar_perfil(p), "Label"))
        p = copia(self.perfil)
        del p["PayloadContent"][0]["Icon"]
        self.assertTrue(_tiene(validar_perfil(p), "Icon"))

    def test_contenido_vacio(self):
        p = copia(self.perfil)
        p["PayloadContent"] = []
        self.assertTrue(_tiene(validar_perfil(p), "al menos un payload"))


class IdentificadoresTest(unittest.TestCase):
    def setUp(self):
        self.cfg, self.perfil = perfil_ejemplo()

    def test_uuid_validos_y_distintos(self):
        top = self.perfil["PayloadUUID"]
        hijo = self.perfil["PayloadContent"][0]["PayloadUUID"]
        uuid.UUID(top)
        uuid.UUID(hijo)
        self.assertNotEqual(top, hijo)
        self.assertNotEqual(self.perfil["PayloadIdentifier"], self.perfil["PayloadContent"][0]["PayloadIdentifier"])

    def test_uuid_repetido_o_invalido(self):
        p = copia(self.perfil)
        p["PayloadContent"][0]["PayloadUUID"] = p["PayloadUUID"].lower()
        self.assertTrue(_tiene(validar_perfil(p), "PayloadUUID repetido"))
        p = copia(self.perfil)
        p["PayloadUUID"] = "no-es-un-uuid"
        self.assertTrue(_tiene(validar_perfil(p), "UUID válido"))

    def test_identificador_repetido_o_mal_formado(self):
        p = copia(self.perfil)
        segundo = copia(p["PayloadContent"][0])
        segundo["PayloadUUID"] = str(uuid.uuid4()).upper()
        p["PayloadContent"].append(segundo)
        self.assertTrue(_tiene(validar_perfil(p), "PayloadIdentifier repetido"))
        p = copia(self.perfil)
        p["PayloadIdentifier"] = "sin puntos"
        self.assertTrue(_tiene(validar_perfil(p), "DNS inverso"))

    def test_subir_la_version_cambia_los_uuid_y_conserva_el_identificador(self):
        from perfil import construir_perfil
        from proyecto import leer_proyecto

        self.cfg.version += 1
        nuevo = construir_perfil(self.cfg, leer_proyecto())
        self.assertEqual(nuevo["PayloadIdentifier"], self.perfil["PayloadIdentifier"])
        self.assertNotEqual(nuevo["PayloadUUID"], self.perfil["PayloadUUID"])
        self.assertNotEqual(nuevo["PayloadContent"][0]["PayloadUUID"], self.perfil["PayloadContent"][0]["PayloadUUID"])


class PayloadsSensiblesTest(unittest.TestCase):
    def setUp(self):
        _, self.perfil = perfil_ejemplo()

    def _con_payload(self, tipo):
        p = copia(self.perfil)
        p["PayloadContent"].append({
            "PayloadType": tipo, "PayloadVersion": 1, "PayloadUUID": str(uuid.uuid4()).upper(),
            "PayloadIdentifier": "io.github.markoyam.prueba." + tipo.replace(".", "-"),
        })
        return p

    def test_todos_los_sensibles_se_rechazan(self):
        for tipo in PAYLOADS_SENSIBLES:
            with self.subTest(tipo=tipo):
                self.assertTrue(_tiene(validar_perfil(self._con_payload(tipo)), "no se publica por defecto"))

    def test_tipos_desconocidos_se_rechazan(self):
        self.assertTrue(_tiene(validar_perfil(self._con_payload("com.ejemplo.raro")), "no está permitido"))

    def test_se_pueden_permitir_explicitamente(self):
        errores = validar_perfil(self._con_payload("com.apple.wifi.managed"), permitir={"com.apple.wifi.managed"})
        self.assertFalse(_tiene(errores, "no se publica por defecto"))

    def test_el_ejemplo_no_trae_nada_sensible(self):
        tipos = {c["PayloadType"] for c in self.perfil["PayloadContent"]}
        self.assertEqual(tipos, {"com.apple.webClip.managed"})
        self.assertNotIn("TargetApplicationBundleIdentifier", self.perfil["PayloadContent"][0])

    def test_abrir_en_una_app_requiere_mdm(self):
        p = copia(self.perfil)
        p["PayloadContent"][0]["TargetApplicationBundleIdentifier"] = "com.example.videoDownloader"
        self.assertTrue(_tiene(validar_perfil(p), "MDM"))


class IconoTest(unittest.TestCase):
    def test_el_icono_de_1024_de_la_app_es_demasiado_grande(self):
        _, p = perfil_ejemplo()
        p["PayloadContent"][0]["Icon"] = (RAIZ_PROYECTO / ICONO_APP).read_bytes()
        self.assertTrue(_tiene(validar_perfil(p), "400×400"))

    def test_icono_que_no_es_png(self):
        _, p = perfil_ejemplo()
        p["PayloadContent"][0]["Icon"] = b"GIF89a....."
        self.assertTrue(_tiene(validar_perfil(p), "PNG válido"))


class CaducidadTest(unittest.TestCase):
    def setUp(self):
        _, self.perfil = perfil_ejemplo()
        self.ahora = dt.datetime(2026, 10, 23, 12, 0)

    def test_sin_caducidad_es_valido_y_no_tiene_claves_de_eliminacion(self):
        self.assertEqual(validar_perfil(self.perfil, ahora=self.ahora), [])
        for clave in ("RemovalDate", "DurationUntilRemoval", "PayloadExpirationDate"):
            self.assertNotIn(clave, self.perfil)

    def test_fecha_pasada_o_duracion_no_positiva(self):
        p = copia(self.perfil)
        p["RemovalDate"] = dt.datetime(2020, 1, 1)
        self.assertTrue(_tiene(validar_perfil(p, ahora=self.ahora), "RemovalDate ya pasó"))
        p = copia(self.perfil)
        p["DurationUntilRemoval"] = 0
        self.assertTrue(_tiene(validar_perfil(p, ahora=self.ahora), "mayor que 0"))
        p = copia(self.perfil)
        p["RemovalDate"] = dt.datetime(2027, 1, 1)
        self.assertEqual(validar_perfil(p, ahora=self.ahora), [])


class ArchivosDanadosTest(unittest.TestCase):
    def setUp(self):
        _, perfil = perfil_ejemplo()
        self.bueno = serializar(perfil)

    def test_vacio(self):
        self.assertTrue(_tiene(validar_archivo(b""), "vacío"))

    def test_basura(self):
        self.assertTrue(_tiene(validar_archivo(os.urandom(512)), "no es una lista de propiedades"))

    def test_cortado_a_la_mitad(self):
        self.assertTrue(_tiene(validar_archivo(self.bueno[: len(self.bueno) // 2]), "dañado o incompleto"))

    def test_raiz_que_no_es_diccionario(self):
        import plistlib

        self.assertTrue(_tiene(validar_archivo(plistlib.dumps(["hola"])), "se esperaba un diccionario"))

    def test_json_en_vez_de_plist(self):
        self.assertTrue(validar_archivo(b'{"PayloadType": "Configuration"}'))

    @unittest.skipUnless(HAY_OPENSSL, "requiere openssl")
    def test_firmado_dañado(self):
        self.assertTrue(es_firmado(b"\x30\x82\x01\x00" + os.urandom(200)))
        self.assertTrue(_tiene(validar_archivo(b"\x30\x82\x01\x00" + os.urandom(200)), "firmado ilegible"))


@unittest.skipUnless(HAY_OPENSSL, "requiere openssl")
class FirmaTest(unittest.TestCase):
    def test_firmar_y_leer(self):
        _, perfil = perfil_ejemplo()
        datos = serializar(perfil)
        with carpeta_temporal() as tmp:
            cert, clave = certificado_prueba(Path(tmp), cn="Perfiles de prueba")
            firmado = firmar(datos, cert, clave)
            self.assertTrue(es_firmado(firmado))
            leido, errores = leer_perfil(firmado)
            self.assertEqual(errores, [])
            self.assertEqual(leido["PayloadIdentifier"], perfil["PayloadIdentifier"])
            self.assertEqual(validar_archivo(firmado), [])
            self.assertTrue(firma_confiable(firmado, cert))
            otro, _ = certificado_prueba(Path(tmp), nombre="otro", cn="Otra CA")
            self.assertFalse(firma_confiable(firmado, otro))
            # Un byte cambiado dentro del contenido firmado rompe la firma.
            roto = bytearray(firmado)
            i = bytes(firmado).find(b"Video Downloader")
            roto[i] ^= 0x01
            self.assertFalse(firma_confiable(bytes(roto), cert))

    def test_sin_certificado_no_se_firma(self):
        with self.assertRaises(ValueError):
            firmar(b"x", Path("/no/existe.pem"), Path("/no/existe.key"))


if __name__ == "__main__":
    unittest.main()
