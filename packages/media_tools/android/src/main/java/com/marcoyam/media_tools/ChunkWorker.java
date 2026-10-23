package com.marcoyam.media_tools;

import android.content.Context;
import android.util.Base64;

import androidx.annotation.NonNull;
import androidx.work.Data;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.Iterator;

/**
 * Descarga un bloque (una petición HTTP) a un archivo. Lo programa {@link BackgroundTransfer} con
 * WorkManager, así sigue aunque la app se cierre. No reintenta solo: Dart decide (p. ej. renovar
 * la URL si YouTube responde 403).
 */
public class ChunkWorker extends Worker {
    static final String KEY_URL = "url";
    static final String KEY_METHOD = "method";
    static final String KEY_HEADERS = "headers";
    static final String KEY_BODY = "body";
    static final String KEY_DESTINATION = "destination";
    static final String KEY_BYTES = "bytes";
    static final String KEY_HTTP = "http";
    static final String KEY_ERROR = "error";

    public ChunkWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        Data in = getInputData();
        String destination = in.getString(KEY_DESTINATION);
        File part = new File(destination + ".part");
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection) new URL(in.getString(KEY_URL)).openConnection();
            String method = in.getString(KEY_METHOD);
            connection.setRequestMethod(method == null ? "GET" : method);
            connection.setConnectTimeout(30000);
            connection.setReadTimeout(30000);
            String headers = in.getString(KEY_HEADERS);
            if (headers != null) {
                JSONObject json = new JSONObject(headers);
                for (Iterator<String> it = json.keys(); it.hasNext(); ) {
                    String key = it.next();
                    connection.setRequestProperty(key, json.getString(key));
                }
            }
            String body = in.getString(KEY_BODY);
            if (body != null) {
                byte[] bytes = Base64.decode(body, Base64.NO_WRAP);
                connection.setDoOutput(true);
                connection.setFixedLengthStreamingMode(bytes.length);
                try (OutputStream out = connection.getOutputStream()) {
                    out.write(bytes);
                }
            }
            int code = connection.getResponseCode();
            if (code != 200 && code != 206) {
                return Result.failure(new Data.Builder().putInt(KEY_HTTP, code).build());
            }
            File parent = part.getParentFile();
            if (parent != null) parent.mkdirs();
            long received = 0;
            long lastReport = 0;
            try (InputStream input = connection.getInputStream(); OutputStream output = new FileOutputStream(part)) {
                byte[] buffer = new byte[64 * 1024];
                int n;
                while ((n = input.read(buffer)) != -1) {
                    if (isStopped()) {
                        part.delete();
                        return Result.failure();
                    }
                    output.write(buffer, 0, n);
                    received += n;
                    if (received - lastReport >= 256 * 1024) {
                        lastReport = received;
                        setProgressAsync(new Data.Builder().putLong(KEY_BYTES, received).build());
                    }
                }
            }
            File target = new File(destination);
            target.delete();
            if (!part.renameTo(target)) {
                return Result.failure(new Data.Builder().putString(KEY_ERROR, "no se pudo guardar el bloque").build());
            }
            return Result.success(new Data.Builder().putInt(KEY_HTTP, code).putLong(KEY_BYTES, received).build());
        } catch (Exception e) {
            part.delete();
            String message = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
            return Result.failure(new Data.Builder().putString(KEY_ERROR, message).build());
        } finally {
            if (connection != null) connection.disconnect();
        }
    }
}
