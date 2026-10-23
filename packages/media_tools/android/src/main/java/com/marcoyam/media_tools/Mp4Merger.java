package com.marcoyam.media_tools;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;

import java.io.File;
import java.nio.ByteBuffer;

/** Une video H.264/HEVC y audio AAC en un MP4 sin recodificar (port de Mp4Processor.kt). */
final class Mp4Merger {
    private static final int MIN_BUFFER = 4 << 20;

    private Mp4Merger() {}

    static void merge(String videoPath, String audioPath, String outputPath) throws Exception {
        MediaExtractor videoEx = new MediaExtractor();
        MediaExtractor audioEx = new MediaExtractor();
        MediaMuxer muxer = null;
        File output = new File(outputPath);
        boolean ok = false;
        try {
            videoEx.setDataSource(videoPath);
            audioEx.setDataSource(audioPath);
            int vIndex = findTrack(videoEx, "video/");
            int aIndex = findTrack(audioEx, "audio/");
            if (vIndex < 0) throw new IllegalStateException("el archivo de video no contiene pista de video");
            if (aIndex < 0) throw new IllegalStateException("el archivo de audio no contiene pista de audio");
            MediaFormat vFormat = videoEx.getTrackFormat(vIndex);
            MediaFormat aFormat = audioEx.getTrackFormat(aIndex);
            String vMime = vFormat.getString(MediaFormat.KEY_MIME);
            String aMime = aFormat.getString(MediaFormat.KEY_MIME);
            if (!MediaFormat.MIMETYPE_VIDEO_AVC.equals(vMime) && !MediaFormat.MIMETYPE_VIDEO_HEVC.equals(vMime)) {
                throw new IllegalStateException("el códec de video " + vMime + " no se puede guardar en MP4");
            }
            if (!MediaFormat.MIMETYPE_AUDIO_AAC.equals(aMime)) {
                throw new IllegalStateException("la pista de audio es " + aMime + ", no AAC");
            }
            videoEx.selectTrack(vIndex);
            audioEx.selectTrack(aIndex);
            //noinspection ResultOfMethodCallIgnored
            output.delete();
            muxer = new MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            int vOut = muxer.addTrack(vFormat);
            int aOut = muxer.addTrack(aFormat);
            muxer.start();

            ByteBuffer vBuf = ByteBuffer.allocate(bufferSize(vFormat));
            ByteBuffer aBuf = ByteBuffer.allocate(bufferSize(aFormat));
            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean vDone = false;
            boolean aDone = false;
            // Intercala por marca de tiempo para que el archivo se reproduzca bien en streaming.
            while (!vDone || !aDone) {
                boolean takeVideo = !vDone && (aDone || videoEx.getSampleTime() <= audioEx.getSampleTime());
                MediaExtractor ex = takeVideo ? videoEx : audioEx;
                ByteBuffer buf = takeVideo ? vBuf : aBuf;
                int size = ex.readSampleData(buf, 0);
                if (size < 0) {
                    if (takeVideo) vDone = true; else aDone = true;
                    continue;
                }
                int flags = (ex.getSampleFlags() & MediaExtractor.SAMPLE_FLAG_SYNC) != 0 ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0;
                info.set(0, size, ex.getSampleTime(), flags);
                muxer.writeSampleData(takeVideo ? vOut : aOut, buf, info);
                ex.advance();
            }
            muxer.stop();
            ok = true;
        } finally {
            if (muxer != null) {
                try { muxer.release(); } catch (Exception ignored) { }
            }
            videoEx.release();
            audioEx.release();
            //noinspection ResultOfMethodCallIgnored
            if (!ok) output.delete();
        }
    }

    static int findTrack(MediaExtractor ex, String prefix) {
        for (int i = 0; i < ex.getTrackCount(); i++) {
            String mime = ex.getTrackFormat(i).getString(MediaFormat.KEY_MIME);
            if (mime != null && mime.startsWith(prefix)) return i;
        }
        return -1;
    }

    private static int bufferSize(MediaFormat format) {
        int declared = format.containsKey(MediaFormat.KEY_MAX_INPUT_SIZE) ? format.getInteger(MediaFormat.KEY_MAX_INPUT_SIZE) : 0;
        return Math.max(declared, MIN_BUFFER);
    }
}
