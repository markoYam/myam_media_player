package com.marcoyam.media_tools;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Canal "com.marcoyam/share": texto o enlace que llega con "Compartir" (ACTION_SEND text/plain) o
 * al abrir un enlace de YouTube (ACTION_VIEW). El de arranque se guarda hasta que Dart lo pide con
 * getInitial; los siguientes (la actividad es singleTop: llegan por onNewIntent) se mandan con "link".
 */
public class ShareHandler implements FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler, PluginRegistry.NewIntentListener {
    /** Marca para no volver a entregar el mismo intent (al rotar o volver a la actividad). */
    private static final String HANDLED = "com.marcoyam.media_tools.SHARE_HANDLED";

    private MethodChannel channel;
    private ActivityPluginBinding activityBinding;
    private String initial;
    private boolean dartReady;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.marcoyam/share");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "getInitial":
                dartReady = true;
                result.success(initial);
                initial = null;
                break;
            case "hasClipboardLink":
                result.success(false); // solo iOS
                break;
            case "takeClipboardLink":
                result.success(null);
                break;
            default:
                result.notImplemented();
        }
    }

    /** Texto o enlace del intent, o null si no es para nosotros. */
    static String textOf(Intent intent) {
        // Al volver desde Recientes, Android repite el intent original: ya se abrió, no repetirlo.
        if (intent == null || intent.getBooleanExtra(HANDLED, false)
                || (intent.getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0) return null;
        String action = intent.getAction();
        if (Intent.ACTION_SEND.equals(action)) {
            CharSequence text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
            if (text == null) return null;
            String subject = intent.getStringExtra(Intent.EXTRA_SUBJECT);
            // Algunas apps mandan el enlace en el asunto y el título en el texto: se juntan.
            return subject != null && !text.toString().contains("http") ? subject + " " + text : text.toString();
        }
        if (Intent.ACTION_VIEW.equals(action)) {
            Uri data = intent.getData();
            return data == null ? null : data.toString();
        }
        return null;
    }

    private void deliver(Intent intent) {
        String text = textOf(intent);
        if (text == null) return;
        intent.putExtra(HANDLED, true);
        if (dartReady && channel != null) {
            channel.invokeMethod("link", text);
        } else {
            initial = text;
        }
    }

    @Override
    public boolean onNewIntent(@NonNull Intent intent) {
        deliver(intent);
        return false; // que otros plugins también lo vean
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addOnNewIntentListener(this);
        Activity activity = binding.getActivity();
        deliver(activity.getIntent());
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        if (activityBinding != null) activityBinding.removeOnNewIntentListener(this);
        activityBinding = null;
    }
}
