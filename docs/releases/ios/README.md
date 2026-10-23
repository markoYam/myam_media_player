# Release iOS

Archivos esperados aquí:

    video-downloader.ipa   (Ad Hoc firmado, o sin firmar para AltStore/SideStore)
    manifest.plist         (instalación OTA con itms-services; ver ../../DISTRIBUCION.md)

Compilar y copiar:

    flutter build ipa --release --export-method ad-hoc
    cp build/ios/ipa/video_downloader.ipa docs/releases/ios/video-downloader.ipa

En `manifest.plist` la URL del .ipa debe ser la de GitHub Pages (HTTPS):
https://markoyam.github.io/myam_media_player/releases/ios/video-downloader.ipa
