#import <Flutter/Flutter.h>

/// Imagen en imagen en iOS: el video de Flutter no lo admite, así que se abre en el reproductor
/// nativo (AVPlayerViewController) con la misma URL, en el mismo segundo.
/// Canal "com.marcoyam/pip": isSupported; present {url, headers, positionMs, title} → posición (ms)
/// al cerrar el reproductor (o al cerrar la ventanita).
@interface MTPip : NSObject <FlutterPlugin>
@end
