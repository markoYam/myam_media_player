package com.marcoyam.media_tools;

import android.os.Handler;
import android.os.Looper;

import androidx.annotation.NonNull;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/** Canal "com.marcoyam/media_tools": une MP4 y convierte a MP3 en un hilo aparte. */
public class MediaToolsPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private MethodChannel channel;
    private JsEngines js;
    private BackgroundTransfer transfers;
    private MethodChannel mediaStore;
    /** Enlaces recibidos con "Compartir" (canal "com.marcoyam/share"). */
    private final ShareHandler share = new ShareHandler();
    /** Imagen en imagen (canal "com.marcoyam/pip"). */
    private final PipHandler pip = new PipHandler();
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler main = new Handler(Looper.getMainLooper());

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.marcoyam/media_tools");
        js = new JsEngines(binding.getApplicationContext());
        transfers = new BackgroundTransfer(binding.getApplicationContext());
        // Guardar en Música / Películas (canal propio "com.marcoyam/media_store").
        mediaStore = MediaStoreSaver.register(binding.getBinaryMessenger(), binding.getApplicationContext());
        share.onAttachedToEngine(binding);
        pip.onAttachedToEngine(binding);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        if (mediaStore != null) mediaStore.setMethodCallHandler(null);
        share.onDetachedFromEngine(binding);
        pip.onDetachedFromEngine(binding);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        share.onAttachedToActivity(binding);
        pip.onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        share.onDetachedFromActivityForConfigChanges();
        pip.onDetachedFromActivityForConfigChanges();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        share.onReattachedToActivityForConfigChanges(binding);
        pip.onReattachedToActivityForConfigChanges(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        share.onDetachedFromActivity();
        pip.onDetachedFromActivity();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if (transfers.handle(call, result)) return;
        switch (call.method) {
            case "mergeAudioVideo": {
                String video = call.argument("video");
                String audio = call.argument("audio");
                String output = call.argument("output");
                run(result, () -> Mp4Merger.merge(video, audio, output));
                break;
            }
            case "transcodeToMp3": {
                String input = call.argument("input");
                String output = call.argument("output");
                Integer kbps = call.argument("bitrateKbps");
                run(result, () -> Mp3Transcoder.transcode(input, output, kbps == null ? 192 : kbps));
                break;
            }
            case "jsCreate":
                js.create(result);
                break;
            case "jsEval":
                js.eval(call.argument("id"), call.argument("code"), result);
                break;
            case "jsDispose":
                js.dispose(call.argument("id"), result);
                break;
            default:
                result.notImplemented();
        }
    }

    private interface Task {
        void run() throws Exception;
    }

    private void run(MethodChannel.Result result, Task task) {
        worker.execute(() -> {
            try {
                task.run();
                main.post(() -> result.success(null));
            } catch (Throwable e) {
                String message = e.getMessage() != null ? e.getMessage() : e.getClass().getSimpleName();
                main.post(() -> result.error("media_tools", message, null));
            }
        });
    }
}
