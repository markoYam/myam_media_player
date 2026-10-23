package com.marcoyam.media_tools;

import android.annotation.SuppressLint;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

import io.flutter.plugin.common.MethodChannel;

/**
 * Motores JavaScript para resolver los retos de YouTube. Android no trae un motor suelto, así que
 * se usa un WebView invisible (V8, con JIT). Todo ocurre en el hilo principal, como exige WebView;
 * evaluateJavascript es asíncrono y no lo bloquea.
 *
 * El resultado llega codificado como JSON (una cadena llega entre comillas); Dart lo decodifica.
 */
final class JsEngines {
    private final Context context;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Map<String, WebView> engines = new HashMap<>();

    JsEngines(Context context) {
        this.context = context;
    }

    @SuppressLint("SetJavaScriptEnabled")
    void create(MethodChannel.Result result) {
        main.post(() -> {
            try {
                WebView view = new WebView(context);
                view.getSettings().setJavaScriptEnabled(true);
                String id = UUID.randomUUID().toString();
                final boolean[] replied = {false};
                view.setWebViewClient(new WebViewClient() {
                    @Override
                    public void onPageFinished(WebView v, String url) {
                        if (replied[0]) return;
                        replied[0] = true;
                        engines.put(id, view);
                        result.success(id);
                    }
                });
                // Página vacía: evaluateJavascript necesita un documento cargado.
                view.loadDataWithBaseURL(null, "<html><body></body></html>", "text/html", "utf-8", null);
            } catch (Throwable e) {
                result.error("media_tools", "no se pudo crear el motor JavaScript: " + e.getMessage(), null);
            }
        });
    }

    void eval(String id, String code, MethodChannel.Result result) {
        main.post(() -> {
            WebView view = engines.get(id);
            if (view == null) {
                result.error("media_tools", "el motor JavaScript ya no existe", null);
                return;
            }
            view.evaluateJavascript(code, result::success);
        });
    }

    void dispose(String id, MethodChannel.Result result) {
        main.post(() -> {
            WebView view = engines.remove(id);
            if (view != null) view.destroy();
            result.success(null);
        });
    }
}
