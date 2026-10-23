#import "MTShare.h"

#import <UIKit/UIKit.h>

/// Esquema propio y tipo de portapapeles que pone la extensión "Compartir" (ver tool/ios_share_extension).
static NSString *const kScheme = @"videodownloader";
static NSString *const kClipboardMarker = @"com.marcoyam.videodownloader.shared-link";

@interface MTShare ()
@property(nonatomic, strong) FlutterMethodChannel *channel;
/// Enlace con el que se abrió la app, hasta que Dart lo pida (getInitial).
@property(nonatomic, copy) NSString *initialLink;
/// Dart ya pidió el inicial: los siguientes se mandan directo.
@property(nonatomic, assign) BOOL dartReady;
@end

@implementation MTShare

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  MTShare *instance = [[MTShare alloc] init];
  instance.channel = [FlutterMethodChannel methodChannelWithName:@"com.marcoyam/share" binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:instance channel:instance.channel];
  // Apps con escenas (Flutter 3.38+, como este proyecto): los enlaces llegan por la escena.
  // Se llama por selector para que también compile con versiones de Flutter sin escenas.
  SEL addScene = NSSelectorFromString(@"addSceneDelegate:");
  if ([registrar respondsToSelector:addScene]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    [registrar performSelector:addScene withObject:instance];
#pragma clang diagnostic pop
  }
  // Apps sin escenas: por el delegado de la app.
  [registrar addApplicationDelegate:instance];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"getInitial"]) {
    self.dartReady = YES;
    NSString *link = self.initialLink;
    self.initialLink = nil;
    result(link);
  } else if ([call.method isEqualToString:@"hasClipboardLink"]) {
    // Revisar los tipos no lee el contenido: iOS no muestra el aviso de "pegar".
    result(@([[UIPasteboard generalPasteboard] containsPasteboardTypes:@[ kClipboardMarker ]]));
  } else if ([call.method isEqualToString:@"takeClipboardLink"]) {
    UIPasteboard *board = [UIPasteboard generalPasteboard];
    if (![board containsPasteboardTypes:@[ kClipboardMarker ]]) {
      result(nil);
      return;
    }
    NSString *link = board.string;
    // Se deja solo el texto (sin la marca) para no volver a ofrecerlo.
    if (link != nil) board.items = @[ @{@"public.utf8-plain-text" : link} ];
    result(link);
  } else {
    result(FlutterMethodNotImplemented);
  }
}

/// Entrega el enlace a Dart (o lo guarda si Dart aún no arrancó). Devuelve YES si era nuestro.
- (BOOL)deliver:(NSURL *)url {
  if (url == nil || ![url.scheme.lowercaseString isEqualToString:kScheme]) return NO;
  NSString *text = url.absoluteString;
  if (self.dartReady) {
    [self.channel invokeMethod:@"link" arguments:text];
  } else {
    self.initialLink = text;
  }
  return YES;
}

#pragma mark - Escenas (FlutterSceneLifeCycleDelegate)

- (BOOL)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
    API_AVAILABLE(ios(13.0)) {
  BOOL handled = NO;
  for (UIOpenURLContext *context in connectionOptions.URLContexts) handled = [self deliver:context.URL] || handled;
  return handled;
}

- (BOOL)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts API_AVAILABLE(ios(13.0)) {
  BOOL handled = NO;
  for (UIOpenURLContext *context in URLContexts) handled = [self deliver:context.URL] || handled;
  return handled;
}

#pragma mark - Delegado de la app (sin escenas)

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
  if (url != nil) [self deliver:url];
  return YES;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
  return [self deliver:url];
}

@end
