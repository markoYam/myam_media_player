// Prueba del ecualizador en C:  cc -O2 -I ios/Classes test_native/eq_dsp_test.c ios/Classes/MTEqualizerDSP.c -lm && ./a.out
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "MTEqualizerDSP.h"

static int failures = 0;
#define CHECK(cond, ...)            \
  do {                              \
    if (!(cond)) {                  \
      printf("FALLA: " __VA_ARGS__); \
      printf("\n");                 \
      failures++;                   \
    }                               \
  } while (0)

int main(void) {
  const double fs = 44100;
  const double freqs[6] = {60, 170, 470, 1300, 3600, 10000};
  mt_eq eq;

  // 1. Plano: respuesta 0 dB y la señal sale igual.
  double flat[6] = {0};
  mt_eq_design(&eq, fs, 6, freqs, flat);
  mt_eq_reset(&eq);
  for (double f = 30; f < 18000; f *= 1.5) CHECK(fabs(mt_eq_response_db(&eq, fs, f)) < 0.01, "plano en %.0f Hz", f);
  float buf[256];
  for (int i = 0; i < 256; i++) buf[i] = sinf(i * 0.1f) * 0.5f;
  float copy[256];
  for (int i = 0; i < 256; i++) copy[i] = buf[i];
  mt_eq_process(&eq, 0, buf, 256, 1);
  for (int i = 0; i < 256; i++) CHECK(buf[i] == copy[i], "plano cambia la muestra %d", i);

  // 2. Cada banda sola: en su frecuencia da su ganancia (±1 dB) y lejos casi nada.
  for (int b = 0; b < 6; b++) {
    for (double g = -12; g <= 12; g += 24) {
      double gains[6] = {0};
      gains[b] = g;
      mt_eq_design(&eq, fs, 6, freqs, gains);
      double at = mt_eq_response_db(&eq, fs, freqs[b]);
      // En los shelf la ganancia completa está más allá de la frecuencia de corte.
      double probe = b == 0 ? 25 : b == 5 ? 16000 : freqs[b];
      double full = mt_eq_response_db(&eq, fs, probe);
      CHECK(fabs(full - g) < 1.5, "banda %d (%.0f Hz) %+.0f dB: da %+.2f en %.0f Hz", b, freqs[b], g, full, probe);
      CHECK(fabs(at) > fabs(g) * 0.4, "banda %d no actúa en su frecuencia (%.2f)", b, at);
      double far = b < 3 ? mt_eq_response_db(&eq, fs, 12000) : mt_eq_response_db(&eq, fs, 50);
      CHECK(fabs(far) < 1.0, "banda %d %+.0f dB se filtra lejos: %.2f", b, g, far);
    }
  }

  // 3. "Más graves": refuerzo en 60 Hz, agudos intactos, y el preamp evita saturar.
  double bass[6] = {6, 4, 0, 0, 0, 0};
  mt_eq_design(&eq, fs, 6, freqs, bass);
  mt_eq_reset(&eq);
  CHECK(mt_eq_response_db(&eq, fs, 25) > 5.5, "graves profundos no suben: %.2f", mt_eq_response_db(&eq, fs, 25));
  CHECK(mt_eq_response_db(&eq, fs, 60) > 3, "60 Hz no sube: %.2f", mt_eq_response_db(&eq, fs, 60));
  CHECK(fabs(mt_eq_response_db(&eq, fs, 8000)) < 0.5, "agudos cambian");
  CHECK(fabs(eq.preamp - pow(10, -6.0 / 20)) < 1e-9, "preamp %.4f", eq.preamp);
  // Un seno de 60 Hz a amplitud 1 no satura tras el filtro: preamp + refuerzo ≈ respuesta − 6 dB.
  float peak = 0;
  float *tone = malloc(sizeof(float) * 44100);
  for (int i = 0; i < 44100; i++) tone[i] = (float)sin(2 * 3.14159265358979 * 60 * i / fs);
  mt_eq_process(&eq, 0, tone, 44100, 1);
  for (int i = 22050; i < 44100; i++) if (fabsf(tone[i]) > peak) peak = fabsf(tone[i]);
  double expected = pow(10, (mt_eq_response_db(&eq, fs, 60) - 6) / 20);
  CHECK(peak <= 1.0f && fabs(peak - expected) < 0.03, "pico de 60 Hz = %.3f (esperado %.3f)", peak, expected);

  // 4. Estéreo intercalado: cada canal con su propio estado (L con seno, R en silencio queda en 0).
  double some[6] = {3, -2, 1, 0, 2, -4};
  mt_eq_design(&eq, 48000, 6, freqs, some);
  mt_eq_reset(&eq);
  float st[2 * 512];
  for (int i = 0; i < 512; i++) {
    st[2 * i] = sinf(i * 0.05f);
    st[2 * i + 1] = 0;
  }
  mt_eq_process(&eq, 0, st, 512, 2);
  mt_eq_process(&eq, 1, st + 1, 512, 2);
  int clean = 1;
  for (int i = 0; i < 512; i++) if (st[2 * i + 1] != 0) clean = 0;
  CHECK(clean, "el canal derecho recibió señal del izquierdo");

  // 5. Frecuencias imposibles (sobre Nyquist) se ignoran sin romper nada.
  double hi[2] = {30000, 100};
  double hg[2] = {12, 0};
  mt_eq_design(&eq, 22050, 2, hi, hg);
  CHECK(!eq.active[0], "banda sobre Nyquist activa");
  CHECK(eq.preamp == 1.0, "preamp con banda inactiva");

  // 6. Estabilidad con ganancias extremas: no hay NaN ni explosión.
  double ext[6] = {12, -12, 12, -12, 12, -12};
  mt_eq_design(&eq, 44100, 6, freqs, ext);
  mt_eq_reset(&eq);
  for (int i = 0; i < 44100; i++) tone[i] = (float)((rand() / (double)RAND_MAX) * 2 - 1);
  mt_eq_process(&eq, 0, tone, 44100, 1);
  int finite = 1;
  float mx = 0;
  for (int i = 0; i < 44100; i++) {
    if (!isfinite(tone[i])) finite = 0;
    if (fabsf(tone[i]) > mx) mx = fabsf(tone[i]);
  }
  CHECK(finite && mx < 8, "inestable: max %.2f", mx);
  free(tone);

  printf(failures ? "%d fallas\n" : "ecualizador DSP: todo bien\n", failures);
  return failures ? 1 : 0;
}
