# Release Android

Coloca aquí el APK firmado con este nombre exacto (la landing enlaza a él):

    video-downloader.apk

Compilar y copiar:

    flutter build apk --release
    cp build/app/outputs/flutter-apk/app-release.apk docs/releases/android/video-downloader.apk

Opcional: `sha256.txt` con `shasum -a 256 video-downloader.apk > sha256.txt`.
GitHub rechaza archivos de más de 100 MB; si lo superas usa `flutter build apk --split-per-abi`
o sube el APK a GitHub Releases y cambia el enlace en `docs/index.html`.
