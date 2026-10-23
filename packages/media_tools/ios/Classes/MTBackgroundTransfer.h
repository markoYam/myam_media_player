#import <Flutter/Flutter.h>

/// Descargas que siguen con la app minimizada (NSURLSession en segundo plano).
///
/// Cada petición es un bloque de un archivo (Dart decide los bloques). El sistema la descarga
/// aunque la app esté suspendida, o la vuelva a abrir si iOS la cerró por memoria; al terminar,
/// el archivo queda en el destino pedido. Si el usuario cierra la app a mano (deslizándola en el
/// selector de apps), iOS cancela las transferencias: al volver a abrirla se reanudan.
///
/// Métodos del canal media_tools: bgEnqueue, bgStatus, bgCancel (ver media_tools.dart).
@interface MTBackgroundTransfer : NSObject <NSURLSessionDownloadDelegate, FlutterApplicationLifeCycleDelegate>

+ (instancetype)shared;

/// Atiende bgEnqueue / bgStatus / bgCancel. Devuelve NO si el método no es suyo.
- (BOOL)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result;

@end
