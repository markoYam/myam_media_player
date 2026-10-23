#import <Flutter/Flutter.h>

/// Enlaces que llegan de fuera: el esquema videodownloader:// (lo usa la extensión "Compartir")
/// y el enlace que la extensión deja copiado si no pudo abrir la app.
/// Canal "com.marcoyam/share": getInitial, hasClipboardLink, takeClipboardLink; avisa con "link".
@interface MTShare : NSObject <FlutterPlugin>
@end
