// Puente JNI entre Kotlin (MediaToolsPlugin) y LAME. Solo Android.
#include <jni.h>
#include <stdint.h>
#include "lame/lame.h"

#define JNI_FN(name) Java_com_marcoyam_media_1tools_LameEncoder_##name

// Crea un codificador MP3 CBR. Devuelve 0 si LAME no acepta los parámetros.
JNIEXPORT jlong JNICALL JNI_FN(nativeInit)(JNIEnv *env, jclass cls, jint sampleRate, jint channels, jint kbps) {
    lame_t gf = lame_init();
    if (!gf) return 0;
    lame_set_num_channels(gf, channels >= 2 ? 2 : 1);
    lame_set_in_samplerate(gf, sampleRate);
    lame_set_brate(gf, kbps);
    lame_set_mode(gf, channels >= 2 ? JOINT_STEREO : MONO);
    lame_set_VBR(gf, vbr_off);
    lame_set_quality(gf, 3);               // 0 = mejor/más lento … 9 = peor/más rápido
    lame_set_bWriteVbrTag(gf, 0);          // se escribe en streaming: no hay cabecera Xing que reescribir
    lame_set_write_id3tag_automatic(gf, 0); // la etiqueta ID3 la agrega la app (UTF-16)
    if (lame_init_params(gf) < 0) {
        lame_close(gf);
        return 0;
    }
    return (jlong)(intptr_t)gf;
}

// PCM de 16 bits intercalado (estéreo) o mono → bytes MP3. Devuelve los bytes escritos o < 0 si falla.
JNIEXPORT jint JNICALL JNI_FN(nativeEncode)(JNIEnv *env, jclass cls, jlong handle, jshortArray pcm, jint frames,
                                            jboolean stereo, jbyteArray out) {
    lame_t gf = (lame_t)(intptr_t)handle;
    jshort *samples = (*env)->GetShortArrayElements(env, pcm, NULL);
    jbyte *mp3 = (*env)->GetByteArrayElements(env, out, NULL);
    jsize capacity = (*env)->GetArrayLength(env, out);
    int written = stereo
        ? lame_encode_buffer_interleaved(gf, samples, frames, (unsigned char *)mp3, capacity)
        : lame_encode_buffer(gf, samples, samples, frames, (unsigned char *)mp3, capacity);
    (*env)->ReleaseShortArrayElements(env, pcm, samples, JNI_ABORT);
    (*env)->ReleaseByteArrayElements(env, out, mp3, 0);
    return written;
}

JNIEXPORT jint JNICALL JNI_FN(nativeFlush)(JNIEnv *env, jclass cls, jlong handle, jbyteArray out) {
    lame_t gf = (lame_t)(intptr_t)handle;
    jbyte *mp3 = (*env)->GetByteArrayElements(env, out, NULL);
    jsize capacity = (*env)->GetArrayLength(env, out);
    int written = lame_encode_flush(gf, (unsigned char *)mp3, capacity);
    (*env)->ReleaseByteArrayElements(env, out, mp3, 0);
    return written;
}

JNIEXPORT void JNICALL JNI_FN(nativeClose)(JNIEnv *env, jclass cls, jlong handle) {
    if (handle) lame_close((lame_t)(intptr_t)handle);
}
