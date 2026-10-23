package com.marcoyam.media_tools;

import android.app.Activity;
import android.app.Application;
import android.app.PictureInPictureParams;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.util.Rational;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.RequiresApi;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Canal "com.marcoyam/pip": imagen en imagen en Android (8.0+).
 *
 * - enter: la actividad entra en imagen en imagen (16:9).
 * - setAutoEnter: Android 12+ entra solo al salir de la app (mientras suena un video).
 * - "modeChanged" (hacia Dart): true/false al entrar o salir.
 *
 * La actividad de la app (AudioServiceActivity, una FlutterActivity) no es ComponentActivity, así
 * que no hay OnPictureInPictureModeChangedProvider: el cambio se detecta con las devoluciones de
 * ciclo de vida de la app (Android llama onPause al entrar en la ventanita y onResume al volver),
 * consultando isInPictureInPictureMode() en cada una.
 */
public class PipHandler implements FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private MethodChannel channel;
    private Activity activity;
    private boolean lastMode;
    private boolean autoEnter;

    private final Application.ActivityLifecycleCallbacks callbacks = new Application.ActivityLifecycleCallbacks() {
        @Override public void onActivityResumed(@NonNull Activity a) { check(a); }
        @Override public void onActivityPaused(@NonNull Activity a) { check(a); }
        @Override public void onActivityStopped(@NonNull Activity a) { check(a); }
        @Override public void onActivityStarted(@NonNull Activity a) { check(a); }
        @Override public void onActivityCreated(@NonNull Activity a, @Nullable Bundle b) {}
        @Override public void onActivitySaveInstanceState(@NonNull Activity a, @NonNull Bundle b) {}
        @Override public void onActivityDestroyed(@NonNull Activity a) {}
    };

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), "com.marcoyam/pip");
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }

    private boolean supported() {
        return activity != null
                && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                && activity.getPackageManager().hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE);
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private PictureInPictureParams params() {
        PictureInPictureParams.Builder builder = new PictureInPictureParams.Builder().setAspectRatio(new Rational(16, 9));
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) builder.setAutoEnterEnabled(autoEnter);
        return builder.build();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "isSupported":
                result.success(supported());
                break;
            case "enter":
                // (La comprobación de versión va aquí mismo para que lint la vea.)
                if (!supported() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    result.success(false);
                    break;
                }
                try {
                    result.success(activity.enterPictureInPictureMode(params()));
                } catch (IllegalStateException | IllegalArgumentException e) {
                    // Falta android:supportsPictureInPicture en el manifest o la actividad no puede ahora.
                    result.success(false);
                }
                break;
            case "setAutoEnter":
                Boolean enabled = call.argument("enabled");
                autoEnter = enabled != null && enabled;
                if (supported() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    try {
                        activity.setPictureInPictureParams(params());
                    } catch (IllegalStateException | IllegalArgumentException ignored) {
                        // Sin soporte en el manifest: solo con el botón (que también fallará).
                    }
                }
                result.success(null);
                break;
            case "present":
                result.success(null); // solo iOS
                break;
            default:
                result.notImplemented();
        }
    }

    private void check(Activity a) {
        if (a != activity || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return;
        boolean mode = a.isInPictureInPictureMode();
        if (mode == lastMode) return;
        lastMode = mode;
        if (channel != null) channel.invokeMethod("modeChanged", mode);
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        activity.getApplication().registerActivityLifecycleCallbacks(callbacks);
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
        if (activity != null) activity.getApplication().unregisterActivityLifecycleCallbacks(callbacks);
        activity = null;
    }
}
