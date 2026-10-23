#include "MTEqualizerDSP.h"

#include <math.h>
#include <string.h>

static const double kPi = 3.14159265358979323846;

static mt_biquad normalize(double b0, double b1, double b2, double a0, double a1, double a2) {
  mt_biquad q = {b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0};
  return q;
}

static mt_biquad peaking(double fs, double f, double gain_db, double Q) {
  const double A = pow(10.0, gain_db / 40.0);
  const double w0 = 2.0 * kPi * f / fs;
  const double alpha = sin(w0) / (2.0 * Q);
  const double c = cos(w0);
  return normalize(1.0 + alpha * A, -2.0 * c, 1.0 - alpha * A, 1.0 + alpha / A, -2.0 * c, 1.0 - alpha / A);
}

static mt_biquad shelf(double fs, double f, double gain_db, int high) {
  const double A = pow(10.0, gain_db / 40.0);
  const double w0 = 2.0 * kPi * f / fs;
  const double c = cos(w0);
  const double alpha = sin(w0) / 2.0 * sqrt(2.0);  // pendiente S = 1
  const double sa = 2.0 * sqrt(A) * alpha;
  if (!high) {
    return normalize(A * ((A + 1) - (A - 1) * c + sa), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - sa),
                     (A + 1) + (A - 1) * c + sa, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - sa);
  }
  return normalize(A * ((A + 1) + (A - 1) * c + sa), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - sa),
                   (A + 1) - (A - 1) * c + sa, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - sa);
}

void mt_eq_design(mt_eq *eq, double sample_rate, int count, const double *freqs_hz, const double *gains_db) {
  if (count > MT_EQ_MAX_BANDS) count = MT_EQ_MAX_BANDS;
  if (count < 0) count = 0;
  eq->band_count = count;
  double max_boost = 0;
  for (int i = 0; i < count; i++) {
    const double f = freqs_hz[i];
    const double g = gains_db[i];
    eq->active[i] = fabs(g) >= 0.05 && f > 10.0 && f < sample_rate * 0.45;
    if (!eq->active[i]) continue;
    if (g > max_boost) max_boost = g;
    if (i == 0 && count > 1) {
      eq->coeffs[i] = shelf(sample_rate, f, g, 0);
    } else if (i == count - 1 && count > 1) {
      eq->coeffs[i] = shelf(sample_rate, f, g, 1);
    } else {
      eq->coeffs[i] = peaking(sample_rate, f, g, 1.0);
    }
  }
  eq->preamp = pow(10.0, -max_boost / 20.0);
}

void mt_eq_reset(mt_eq *eq) { memset(eq->state, 0, sizeof(eq->state)); }

void mt_eq_process(mt_eq *eq, int channel, float *samples, long frames, int stride) {
  if (channel < 0 || channel >= MT_EQ_MAX_CHANNELS) return;
  const double pre = eq->preamp;
  for (long n = 0; n < frames; n++) {
    double x = samples[n * stride] * pre;
    for (int b = 0; b < eq->band_count; b++) {
      if (!eq->active[b]) continue;
      const mt_biquad *q = &eq->coeffs[b];
      mt_biquad_state *s = &eq->state[channel][b];
      const double y = q->b0 * x + q->b1 * s->x1 + q->b2 * s->x2 - q->a1 * s->y1 - q->a2 * s->y2;
      s->x2 = s->x1;
      s->x1 = x;
      s->y2 = s->y1;
      s->y1 = y;
      x = y;
    }
    samples[n * stride] = (float)x;
  }
}

double mt_eq_response_db(const mt_eq *eq, double sample_rate, double freq_hz) {
  const double w = 2.0 * kPi * freq_hz / sample_rate;
  double total = 0;
  for (int b = 0; b < eq->band_count; b++) {
    if (!eq->active[b]) continue;
    const mt_biquad *q = &eq->coeffs[b];
    // |H(e^jw)| con números complejos a mano.
    const double c1 = cos(w), s1 = sin(w), c2 = cos(2 * w), s2 = sin(2 * w);
    const double nr = q->b0 + q->b1 * c1 + q->b2 * c2, ni = -(q->b1 * s1 + q->b2 * s2);
    const double dr = 1.0 + q->a1 * c1 + q->a2 * c2, di = -(q->a1 * s1 + q->a2 * s2);
    total += 10.0 * log10((nr * nr + ni * ni) / (dr * dr + di * di));
  }
  return total;
}
