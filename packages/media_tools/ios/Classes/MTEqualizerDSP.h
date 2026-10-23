// Ecualizador paramétrico (filtros biquad del "Audio EQ Cookbook" de R. Bristow-Johnson).
// C puro, sin dependencias: se prueba en cualquier máquina (ver test/dsp en el plugin).
#ifndef MT_EQUALIZER_DSP_H
#define MT_EQUALIZER_DSP_H

#define MT_EQ_MAX_BANDS 10
#define MT_EQ_MAX_CHANNELS 8

typedef struct {
  double b0, b1, b2, a1, a2;
} mt_biquad;

typedef struct {
  double x1, x2, y1, y2;
} mt_biquad_state;

typedef struct {
  int band_count;
  mt_biquad coeffs[MT_EQ_MAX_BANDS];
  /// Bandas sin efecto (ganancia ~0 o frecuencia fuera de rango): se saltan.
  int active[MT_EQ_MAX_BANDS];
  /// Atenuación previa para que los refuerzos no saturen (lineal, <= 1).
  double preamp;
  mt_biquad_state state[MT_EQ_MAX_CHANNELS][MT_EQ_MAX_BANDS];
} mt_eq;

/// Calcula los filtros. La primera banda es un "shelf" de graves, la última de agudos y las del
/// medio son picos (Q = 1). No borra el estado: cambiar el ajuste no produce chasquidos fuertes.
void mt_eq_design(mt_eq *eq, double sample_rate, int count, const double *freqs_hz, const double *gains_db);

/// Borra la memoria de los filtros (al cambiar de canción o de formato).
void mt_eq_reset(mt_eq *eq);

/// Procesa en el lugar [frames] muestras float de un canal. [stride] = 1 para audio no
/// intercalado; = número de canales para intercalado (y [samples] apunta al canal).
void mt_eq_process(mt_eq *eq, int channel, float *samples, long frames, int stride);

/// Respuesta total en dB a [freq_hz] (sin preamp). Para pruebas.
double mt_eq_response_db(const mt_eq *eq, double sample_rate, double freq_hz);

#endif
