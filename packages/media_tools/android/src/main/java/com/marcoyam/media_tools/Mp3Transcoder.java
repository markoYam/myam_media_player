package com.marcoyam.media_tools;

import android.media.AudioFormat;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;

import java.io.File;
import java.io.FileOutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.FloatBuffer;
import java.nio.ShortBuffer;

/**
 * Cualquier audio que Android sepa decodificar (AAC/M4A, Opus…) → MP3 CBR:
 * MediaExtractor → MediaCodec (PCM) → LAME. Port de Mp3Transcoder.kt, con LAME en C.
 */
final class Mp3Transcoder {
    private static final long TIMEOUT_US = 10_000;

    private Mp3Transcoder() {}

    static void transcode(String inputPath, String outputPath, int kbps) throws Exception {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec decoder = null;
        LameEncoder encoder = null;
        File output = new File(outputPath);
        boolean ok = false;
        try (FileOutputStream out = new FileOutputStream(output)) {
            extractor.setDataSource(inputPath);
            int track = Mp4Merger.findTrack(extractor, "audio/");
            if (track < 0) throw new IllegalStateException("el archivo no contiene pista de audio");
            MediaFormat inFormat = extractor.getTrackFormat(track);
            String mime = inFormat.getString(MediaFormat.KEY_MIME);
            extractor.selectTrack(track);

            decoder = MediaCodec.createDecoderByType(mime);
            decoder.configure(inFormat, null, null, 0);
            decoder.start();

            int sampleRate = inFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int channels = inFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
            boolean floatPcm = false;
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false;
            boolean outputDone = false;
            short[] pcm = new short[0];

            while (!outputDone) {
                if (!inputDone) {
                    int inIndex = decoder.dequeueInputBuffer(TIMEOUT_US);
                    if (inIndex >= 0) {
                        ByteBuffer buffer = decoder.getInputBuffer(inIndex);
                        int size = buffer == null ? -1 : extractor.readSampleData(buffer, 0);
                        if (size < 0) {
                            decoder.queueInputBuffer(inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int outIndex = decoder.dequeueOutputBuffer(info, TIMEOUT_US);
                if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat f = decoder.getOutputFormat();
                    sampleRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                    channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
                    floatPcm = f.containsKey(MediaFormat.KEY_PCM_ENCODING)
                            && f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT;
                } else if (outIndex >= 0) {
                    if (info.size > 0) {
                        if (encoder == null) encoder = new LameEncoder(sampleRate, channels, kbps);
                        ByteBuffer buffer = decoder.getOutputBuffer(outIndex);
                        if (buffer != null) {
                            buffer.position(info.offset);
                            buffer.limit(info.offset + info.size);
                            ByteBuffer slice = buffer.slice().order(ByteOrder.nativeOrder());
                            int outChannels = channels >= 2 ? 2 : 1;
                            int frames = floatPcm ? slice.remaining() / 4 / channels : slice.remaining() / 2 / channels;
                            if (pcm.length < frames * outChannels) pcm = new short[frames * outChannels];
                            // Se quedan los dos primeros canales (los videos 5.1 se reducen a estéreo).
                            if (floatPcm) {
                                FloatBuffer fb = slice.asFloatBuffer();
                                for (int i = 0; i < frames; i++) {
                                    for (int c = 0; c < outChannels; c++) {
                                        float v = Math.max(-1f, Math.min(1f, fb.get(i * channels + c)));
                                        pcm[i * outChannels + c] = (short) (v * 32767f);
                                    }
                                }
                            } else {
                                ShortBuffer sb = slice.asShortBuffer();
                                for (int i = 0; i < frames; i++) {
                                    for (int c = 0; c < outChannels; c++) pcm[i * outChannels + c] = sb.get(i * channels + c);
                                }
                            }
                            int written = encoder.encode(pcm, frames);
                            out.write(encoder.buffer(), 0, written);
                        }
                    }
                    decoder.releaseOutputBuffer(outIndex, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true;
                }
            }
            if (encoder == null) throw new IllegalStateException("la pista de audio está vacía");
            int tail = encoder.flush();
            out.write(encoder.buffer(), 0, tail);
            ok = true;
        } finally {
            if (decoder != null) {
                try { decoder.stop(); } catch (Exception ignored) { }
                try { decoder.release(); } catch (Exception ignored) { }
            }
            if (encoder != null) encoder.close();
            extractor.release();
            //noinspection ResultOfMethodCallIgnored
            if (!ok) output.delete();
        }
    }
}
