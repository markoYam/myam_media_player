package com.marcoyam.media_tools;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.Base64;

import androidx.work.Constraints;
import androidx.work.Data;
import androidx.work.ExistingWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkInfo;
import androidx.work.WorkManager;

import org.json.JSONObject;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Descargas que siguen con la app cerrada: cada bloque es un trabajo de WorkManager
 * ({@link ChunkWorker}). Métodos del canal media_tools: bgEnqueue, bgStatus, bgCancel.
 */
final class BackgroundTransfer {
    private static final String TAG_ALL = "mt_bg";
    private static final String TAG_ID = "mt_id:";

    private final Context context;
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    BackgroundTransfer(Context context) {
        this.context = context.getApplicationContext();
    }

    /** Atiende el método si es suyo; devuelve false si no. */
    boolean handle(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "bgEnqueue":
                enqueue(call, result);
                return true;
            case "bgStatus":
                status(stringArg(call, "prefix"), result);
                return true;
            case "bgCancel":
                cancel(stringArg(call, "prefix"), result);
                return true;
            default:
                return false;
        }
    }

    private static String stringArg(MethodCall call, String key) {
        String value = call.argument(key);
        return value == null ? "" : value;
    }

    private void enqueue(MethodCall call, MethodChannel.Result result) {
        String id = call.argument("id");
        String url = call.argument("url");
        String destination = call.argument("destination");
        if (id == null || url == null || destination == null) {
            result.error("media_tools", "bgEnqueue: faltan id, url o destino", null);
            return;
        }
        Data.Builder data = new Data.Builder()
                .putString(ChunkWorker.KEY_URL, url)
                .putString(ChunkWorker.KEY_METHOD, call.argument("method"))
                .putString(ChunkWorker.KEY_DESTINATION, destination);
        Map<String, Object> headers = call.argument("headers");
        if (headers != null) data.putString(ChunkWorker.KEY_HEADERS, new JSONObject(headers).toString());
        byte[] body = call.argument("body");
        if (body != null) data.putString(ChunkWorker.KEY_BODY, Base64.encodeToString(body, Base64.NO_WRAP));

        OneTimeWorkRequest request = new OneTimeWorkRequest.Builder(ChunkWorker.class)
                .setInputData(data.build())
                .setConstraints(new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                .addTag(TAG_ALL)
                .addTag(TAG_ID + id)
                .build();
        WorkManager.getInstance(context).enqueueUniqueWork(TAG_ALL + ":" + id, ExistingWorkPolicy.REPLACE, request);
        result.success(null);
    }

    private static String idOf(WorkInfo info) {
        for (String tag : info.getTags()) {
            if (tag.startsWith(TAG_ID)) return tag.substring(TAG_ID.length());
        }
        return null;
    }

    /** Prioridad al juntar varios trabajos del mismo bloque (el viejo reemplazado y el nuevo). */
    private static int rank(String state) {
        switch (state) {
            case "running":
                return 3;
            case "done":
                return 2;
            default:
                return 1;
        }
    }

    private void status(String prefix, MethodChannel.Result result) {
        io.execute(() -> {
            try {
                List<WorkInfo> infos = WorkManager.getInstance(context).getWorkInfosByTag(TAG_ALL).get();
                Map<String, Map<String, Object>> out = new HashMap<>();
                for (WorkInfo info : infos) {
                    String id = idOf(info);
                    if (id == null || !id.startsWith(prefix)) continue;
                    Map<String, Object> entry = new HashMap<>();
                    switch (info.getState()) {
                        case ENQUEUED:
                        case RUNNING:
                        case BLOCKED:
                            entry.put("state", "running");
                            entry.put("bytes", info.getProgress().getLong(ChunkWorker.KEY_BYTES, 0));
                            break;
                        case SUCCEEDED:
                            entry.put("state", "done");
                            break;
                        case FAILED:
                            entry.put("state", "failed");
                            int http = info.getOutputData().getInt(ChunkWorker.KEY_HTTP, 0);
                            if (http != 0) entry.put("http", http);
                            String error = info.getOutputData().getString(ChunkWorker.KEY_ERROR);
                            if (error != null) entry.put("error", error);
                            break;
                        default:
                            continue; // cancelado
                    }
                    Map<String, Object> previous = out.get(id);
                    if (previous == null || rank((String) entry.get("state")) > rank((String) previous.get("state"))) {
                        out.put(id, entry);
                    }
                }
                main.post(() -> result.success(out));
            } catch (Exception e) {
                String message = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
                main.post(() -> result.error("media_tools", message, null));
            }
        });
    }

    private void cancel(String prefix, MethodChannel.Result result) {
        io.execute(() -> {
            try {
                WorkManager manager = WorkManager.getInstance(context);
                for (WorkInfo info : manager.getWorkInfosByTag(TAG_ALL).get()) {
                    String id = idOf(info);
                    if (id != null && id.startsWith(prefix)) manager.cancelWorkById(info.getId());
                }
                main.post(() -> result.success(null));
            } catch (Exception e) {
                String message = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
                main.post(() -> result.error("media_tools", message, null));
            }
        });
    }
}
