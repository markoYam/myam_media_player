package com.marcoyam.media_tools;

/** Codificador MP3 CBR sobre LAME en C (ver src/media_tools_jni.c). */
final class LameEncoder implements AutoCloseable {
    static {
        System.loadLibrary("media_tools");
    }

    private static native long nativeInit(int sampleRate, int channels, int kbps);
    private static native int nativeEncode(long handle, short[] pcm, int frames, boolean stereo, byte[] out);
    private static native int nativeFlush(long handle, byte[] out);
    private static native void nativeClose(long handle);

    private static final int FLUSH_BUFFER = 7200 + 16384;

    private long handle;
    private final boolean stereo;
    private byte[] out = new byte[0];

    LameEncoder(int sampleRate, int channels, int kbps) {
        stereo = channels >= 2;
        handle = nativeInit(sampleRate, stereo ? 2 : 1, kbps);
        if (handle == 0) {
            throw new IllegalArgumentException("LAME no aceptó " + sampleRate + " Hz, " + channels + " canales a " + kbps + " kbps");
        }
    }

    /** [pcm]: muestras de 16 bits (intercaladas si es estéreo). Devuelve los bytes MP3 en [buffer()]. */
    int encode(short[] pcm, int frames) {
        // Tamaño recomendado por LAME: 1.25 × muestras + 7200 bytes.
        int needed = frames * 5 / 4 + 7200;
        if (out.length < needed) out = new byte[needed];
        int written = nativeEncode(handle, pcm, frames, stereo, out);
        if (written < 0) throw new IllegalStateException("error de LAME al codificar (" + written + ")");
        return written;
    }

    int flush() {
        if (out.length < FLUSH_BUFFER) out = new byte[FLUSH_BUFFER];
        return Math.max(0, nativeFlush(handle, out));
    }

    byte[] buffer() {
        return out;
    }

    @Override
    public void close() {
        if (handle != 0) {
            nativeClose(handle);
            handle = 0;
        }
    }
}
