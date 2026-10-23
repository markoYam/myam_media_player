package com.marcoyam.media_tools;

import android.Manifest;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.provider.MediaStore;

import androidx.annotation.NonNull;
import androidx.annotation.RequiresApi;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Canal "com.marcoyam/media_store": copia una descarga a las carpetas públicas
 * (Música/Video Downloader o Películas/Video Downloader), como la versión Kotlin.
 *
 * <p>Android 10+ (API 29): MediaStore con RELATIVE_PATH e IS_PENDING, sin permisos.
 * Android 9 o anterior: se escribe en la carpeta pública y se avisa al escáner de medios; hace
 * falta el permiso WRITE_EXTERNAL_STORAGE (maxSdkVersion 28) concedido.
 */
public final class MediaStoreSaver {
  public static final String CHANNEL = "com.marcoyam/media_store";
  private static final String FOLDER = "Video Downloader";
  private static final ExecutorService EXECUTOR = Executors.newSingleThreadExecutor();

  private MediaStoreSaver() {}

  /** Registra el canal (llamar desde onAttachedToEngine del plugin). */
  public static MethodChannel register(@NonNull BinaryMessenger messenger, @NonNull Context context) {
    final Context app = context.getApplicationContext();
    MethodChannel channel = new MethodChannel(messenger, CHANNEL);
    channel.setMethodCallHandler((call, result) -> {
      if ("save".equals(call.method)) {
        save(app, call, result);
      } else {
        result.notImplemented();
      }
    });
    return channel;
  }

  static void save(Context context, MethodCall call, MethodChannel.Result result) {
    final String path = call.argument("path");
    final String displayName = call.argument("displayName");
    final String title = call.argument("title");
    final String artist = call.argument("artist");
    final Boolean isAudioArg = call.argument("isAudio");
    final String mime = call.argument("mimeType");
    final boolean isAudio = isAudioArg != null && isAudioArg;
    final Handler main = new Handler(Looper.getMainLooper());
    if (path == null || displayName == null || mime == null) {
      result.error("media_store", "Faltan datos del archivo.", null);
      return;
    }
    EXECUTOR.execute(() -> {
      try {
        String saved = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
            ? saveScoped(context, new File(path), displayName, title, artist, isAudio, mime)
            : saveLegacy(context, new File(path), displayName, isAudio, mime);
        main.post(() -> result.success(saved));
      } catch (SecurityException e) {
        main.post(() -> result.error("media_store",
            "Falta el permiso de almacenamiento. En Android 9 o anterior usa \"Compartir\" para guardarlo.", null));
      } catch (Exception e) {
        main.post(() -> result.error("media_store", "No se pudo guardar la copia: " + e.getMessage(), null));
      }
    });
  }

  @RequiresApi(Build.VERSION_CODES.Q)
  private static String saveScoped(Context context, File source, String displayName, String title, String artist,
                                   boolean isAudio, String mime) throws IOException {
    ContentResolver resolver = context.getContentResolver();
    Uri collection = isAudio
        ? MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        : MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
    ContentValues values = new ContentValues();
    values.put(MediaStore.MediaColumns.DISPLAY_NAME, displayName);
    values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
    values.put(MediaStore.MediaColumns.RELATIVE_PATH,
        (isAudio ? Environment.DIRECTORY_MUSIC : Environment.DIRECTORY_MOVIES) + "/" + FOLDER);
    if (title != null) values.put(MediaStore.MediaColumns.TITLE, title);
    if (isAudio) {
      if (artist != null) values.put(MediaStore.Audio.Media.ARTIST, artist);
      values.put(MediaStore.Audio.Media.IS_MUSIC, 1);
    }
    values.put(MediaStore.MediaColumns.IS_PENDING, 1);
    Uri item = resolver.insert(collection, values);
    if (item == null) throw new IOException("MediaStore no creó el archivo");
    try (InputStream in = new FileInputStream(source); OutputStream out = resolver.openOutputStream(item)) {
      if (out == null) throw new IOException("no se pudo escribir");
      copy(in, out);
    } catch (IOException | RuntimeException e) {
      resolver.delete(item, null, null);
      throw e;
    }
    ContentValues done = new ContentValues();
    done.put(MediaStore.MediaColumns.IS_PENDING, 0);
    resolver.update(item, done, null, null);
    return item.toString();
  }

  @SuppressWarnings("deprecation")
  private static String saveLegacy(Context context, File source, String displayName, boolean isAudio, String mime)
      throws IOException {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M
        && context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
      throw new SecurityException("sin permiso");
    }
    File dir = new File(Environment.getExternalStoragePublicDirectory(
        isAudio ? Environment.DIRECTORY_MUSIC : Environment.DIRECTORY_MOVIES), FOLDER);
    if (!dir.exists() && !dir.mkdirs()) throw new IOException("no se pudo crear " + dir);
    File target = unique(dir, displayName);
    try (InputStream in = new FileInputStream(source); OutputStream out = new FileOutputStream(target)) {
      copy(in, out);
    }
    MediaScannerConnection.scanFile(context, new String[] {target.getAbsolutePath()}, new String[] {mime}, null);
    return target.getAbsolutePath();
  }

  /** "nombre.mp3", "nombre (2).mp3"… */
  private static File unique(File dir, String name) {
    File f = new File(dir, name);
    if (!f.exists()) return f;
    int dot = name.lastIndexOf('.');
    String base = dot > 0 ? name.substring(0, dot) : name;
    String ext = dot > 0 ? name.substring(dot) : "";
    for (int n = 2; ; n++) {
      f = new File(dir, base + " (" + n + ")" + ext);
      if (!f.exists()) return f;
    }
  }

  private static void copy(InputStream in, OutputStream out) throws IOException {
    byte[] buffer = new byte[256 * 1024];
    int read;
    while ((read = in.read(buffer)) != -1) out.write(buffer, 0, read);
    out.flush();
  }
}
