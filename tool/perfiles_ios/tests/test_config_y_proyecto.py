"""Configuración JSON (errores claros) y datos leídos del proyecto Flutter."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

from apoyo import CONFIG_EJEMPLO, carpeta_temporal

from perfil import cargar_config, construir_perfil
from proyecto import bundle_id_de_runner, leer_proyecto


def _escribir(carpeta: Path, datos) -> Path:
    ruta = carpeta / "perfil.json"
    ruta.write_text(datos if isinstance(datos, str) else json.dumps(datos), encoding="utf-8")
    # El ícono de ejemplo, para que las configuraciones válidas lo encuentren.
    (carpeta / "icono-webclip.png").write_bytes((CONFIG_EJEMPLO.parent / "icono-webclip.png").read_bytes())
    return ruta


def _base():
    return json.loads(CONFIG_EJEMPLO.read_text(encoding="utf-8"))


class ConfigTest(unittest.TestCase):
    def test_json_invalido(self):
        with carpeta_temporal() as tmp:
            cfg, errores = cargar_config(_escribir(Path(tmp), "{ no es json"))
            self.assertIsNone(cfg)
            self.assertIn("JSON inválido", errores[0])

    def test_archivo_inexistente(self):
        cfg, errores = cargar_config(Path("/no/existe.json"))
        self.assertIsNone(cfg)
        self.assertIn("No existe", errores[0])

    def test_cada_campo_obligatorio(self):
        for campo in ("archivo", "identificador", "version", "nombre", "organizacion", "descripcion", "fecha_creacion", "payloads"):
            with self.subTest(campo=campo), carpeta_temporal() as tmp:
                datos = _base()
                del datos[campo]
                cfg, errores = cargar_config(_escribir(Path(tmp), datos))
                self.assertIsNone(cfg)
                self.assertTrue(any(campo in e for e in errores), errores)

    def test_valores_invalidos(self):
        casos = {
            "archivo": ("../fuera.mobileconfig", "nombre simple"),
            "identificador": ("Video Downloader", "DNS inverso"),
            "version": (0, "entero"),
            "fecha_creacion": ("23/10/2026", "AAAA-MM-DD"),
        }
        for campo, (valor, mensaje) in casos.items():
            with self.subTest(campo=campo), carpeta_temporal() as tmp:
                datos = _base()
                datos[campo] = valor
                cfg, errores = cargar_config(_escribir(Path(tmp), datos))
                self.assertIsNone(cfg)
                self.assertTrue(any(mensaje in e for e in errores), errores)

    def test_solo_web_clips_https(self):
        with carpeta_temporal() as tmp:
            datos = _base()
            datos["payloads"] = [{"tipo": "vpn", "servidor": "x"}]
            self.assertIsNone(cargar_config(_escribir(Path(tmp), datos))[0])
            datos["payloads"] = [{"tipo": "webclip", "url": "http://markoyam.github.io/"}]
            cfg, errores = cargar_config(_escribir(Path(tmp), datos))
            self.assertIsNone(cfg)
            self.assertTrue(any("https://" in e for e in errores))

    def test_no_acepta_promesas_falsas_en_la_descripcion(self):
        with carpeta_temporal() as tmp:
            datos = _base()
            datos["descripcion"] = "Instala la app gratis y para siempre."
            cfg, errores = cargar_config(_escribir(Path(tmp), datos))
            self.assertIsNone(cfg)
            self.assertTrue(any("promete" in e for e in errores))

    def test_caducidad_por_fecha_y_por_duracion(self):
        proyecto = leer_proyecto()
        with carpeta_temporal() as tmp:
            datos = _base()
            datos["caducidad"] = {"tipo": "fecha", "fecha": "2030-01-01T00:00:00Z"}
            cfg, errores = cargar_config(_escribir(Path(tmp), datos))
            self.assertEqual(errores, [])
            perfil = construir_perfil(cfg, proyecto)
            self.assertEqual(perfil["RemovalDate"].year, 2030)
            datos["caducidad"] = {"tipo": "duracion", "dias": 30}
            cfg, _ = cargar_config(_escribir(Path(tmp), datos))
            self.assertEqual(construir_perfil(cfg, proyecto)["DurationUntilRemoval"], 30 * 86400.0)
            datos["caducidad"] = {"tipo": "duracion", "dias": 0}
            self.assertIsNone(cargar_config(_escribir(Path(tmp), datos))[0])
            datos["caducidad"] = {"tipo": "para-siempre"}
            self.assertIsNone(cargar_config(_escribir(Path(tmp), datos))[0])

    def test_icono_inexistente(self):
        with carpeta_temporal() as tmp:
            datos = _base()
            datos["payloads"][0]["icono"] = "no-existe.png"
            cfg, _ = cargar_config(_escribir(Path(tmp), datos))
            with self.assertRaises(ValueError):
                construir_perfil(cfg, leer_proyecto())


class ProyectoTest(unittest.TestCase):
    def test_datos_del_proyecto_real(self):
        p = leer_proyecto()
        self.assertEqual(p.nombre_visible, "Video Downloader")
        self.assertEqual(p.nombre_paquete, "video_downloader")
        self.assertRegex(p.version, r"^\d+\.\d+\.\d+$")
        self.assertIsNotNone(p.bundle_id)
        self.assertIsNotNone(p.icono_app)

    def test_avisa_del_prefijo_com_example(self):
        p = leer_proyecto()
        if p.bundle_id and p.bundle_id.startswith("com.example."):
            self.assertTrue(any("com.example" in a for a in p.avisos))
        else:
            self.assertFalse(any("com.example" in a for a in p.avisos))

    def test_bundle_id_de_runner_ignora_tests_y_extension(self):
        pbx = (
            "\t\tA /* Debug */ = {\n\t\t\tbuildSettings = {\n\t\t\t\tINFOPLIST_FILE = ShareExtension/Info.plist;\n"
            "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.marcoyam.app.ShareExtension;\n\t\t\t};\n"
            "\t\tB /* Debug */ = {\n\t\t\tbuildSettings = {\n\t\t\t\tINFOPLIST_FILE = Runner/Info.plist;\n"
            "\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.marcoyam.app;\n\t\t\t};\n"
            "\t\tC /* Debug */ = {\n\t\t\tbuildSettings = {\n\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.marcoyam.app.RunnerTests;\n\t\t\t};\n"
        )
        self.assertEqual(bundle_id_de_runner(pbx), "com.marcoyam.app")
        self.assertIsNone(bundle_id_de_runner(""))

    def test_el_perfil_usa_el_nombre_del_proyecto(self):
        cfg, _ = cargar_config(CONFIG_EJEMPLO)
        perfil = construir_perfil(cfg, leer_proyecto())
        self.assertIn(leer_proyecto().nombre_visible, perfil["PayloadDescription"])


if __name__ == "__main__":
    unittest.main()
