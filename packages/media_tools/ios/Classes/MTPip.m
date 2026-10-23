#import "MTPip.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <UIKit/UIKit.h>

/// Avisa cuando el reproductor desaparece de la pantalla (cerrado por el usuario o al pasar a la
/// ventanita).
@interface MTPipPlayerViewController : AVPlayerViewController
@property(nonatomic, copy) void (^onDisappear)(void);
@end

@implementation MTPipPlayerViewController
- (void)viewDidDisappear:(BOOL)animated {
  [super viewDidDisappear:animated];
  if (self.onDisappear != nil && (self.isBeingDismissed || self.presentingViewController == nil)) self.onDisappear();
}
@end

@interface MTPip () <AVPlayerViewControllerDelegate>
@property(nonatomic, strong) MTPipPlayerViewController *controller;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, copy) FlutterResult pending;
@property(nonatomic, assign) BOOL inPip;
@end

@implementation MTPip

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"com.marcoyam/pip" binaryMessenger:[registrar messenger]];
  [registrar addMethodCallDelegate:[[MTPip alloc] init] channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([call.method isEqualToString:@"isSupported"]) {
    result(@([AVPictureInPictureController isPictureInPictureSupported]));
  } else if ([call.method isEqualToString:@"present"]) {
    [self present:call.arguments result:result];
  } else if ([call.method isEqualToString:@"enter"] || [call.method isEqualToString:@"setAutoEnter"]) {
    result(@NO);  // solo Android
  } else {
    result(FlutterMethodNotImplemented);
  }
}

static UIViewController *TopController(void) {
  UIWindow *window = nil;
  for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
    if (![scene isKindOfClass:[UIWindowScene class]]) continue;
    for (UIWindow *w in ((UIWindowScene *)scene).windows) {
      if (w.isKeyWindow) window = w;
    }
    if (window == nil) window = ((UIWindowScene *)scene).windows.firstObject;
  }
  UIViewController *top = window.rootViewController;
  while (top.presentedViewController != nil) top = top.presentedViewController;
  return top;
}

- (void)present:(NSDictionary *)args result:(FlutterResult)result {
  if (self.pending != nil) {
    result([FlutterError errorWithCode:@"pip" message:@"Ya está abierto el reproductor" details:nil]);
    return;
  }
  NSURL *url = [NSURL URLWithString:args[@"url"]];
  UIViewController *top = TopController();
  if (url == nil || top == nil) {
    result([FlutterError errorWithCode:@"pip" message:@"No se pudo abrir el reproductor" details:nil]);
    return;
  }
  // Imagen en imagen pide la sesión de audio de reproducción (just_audio usa la misma).
  [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeMoviePlayback options:0 error:nil];
  [[AVAudioSession sharedInstance] setActive:YES error:nil];

  NSDictionary *headers = [args[@"headers"] isKindOfClass:[NSDictionary class]] ? args[@"headers"] : @{};
  // Mismo User-Agent que el cliente que generó la URL; si no, YouTube responde 403.
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{@"AVURLAssetHTTPHeaderFieldsKey" : headers}];
  AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
  NSString *title = [args[@"title"] isKindOfClass:[NSString class]] ? args[@"title"] : @"";
  if (title.length > 0) {
    // externalMetadata existe en iPhone desde iOS 16 (antes era solo de tvOS).
    if (@available(iOS 16.0, *)) {
      AVMutableMetadataItem *meta = [AVMutableMetadataItem metadataItem];
      meta.identifier = AVMetadataCommonIdentifierTitle;
      meta.value = title;
      item.externalMetadata = @[ meta ];
    }
  }
  self.player = [AVPlayer playerWithPlayerItem:item];
  NSNumber *ms = args[@"positionMs"];
  if ([ms isKindOfClass:[NSNumber class]] && ms.longLongValue > 0) {
    [self.player seekToTime:CMTimeMake(ms.longLongValue, 1000) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
  }

  MTPipPlayerViewController *vc = [[MTPipPlayerViewController alloc] init];
  vc.player = self.player;
  vc.delegate = self;
  vc.allowsPictureInPicturePlayback = YES;
  if (@available(iOS 14.2, *)) vc.canStartPictureInPictureAutomaticallyFromInline = YES;
  vc.modalPresentationStyle = UIModalPresentationFullScreen;
  __weak MTPip *weakSelf = self;
  vc.onDisappear = ^{
    // Si pasó a la ventanita, se espera a que la cierren.
    if (!weakSelf.inPip) [weakSelf finish];
  };
  self.controller = vc;
  self.pending = result;
  [top presentViewController:vc animated:YES completion:^{
    [weakSelf.player play];
  }];
}

/// Devuelve la posición a Dart y suelta el reproductor.
- (void)finish {
  FlutterResult result = self.pending;
  if (result == nil) return;
  self.pending = nil;
  CMTime time = self.player.currentTime;
  long long ms = CMTIME_IS_NUMERIC(time) ? (long long)(CMTimeGetSeconds(time) * 1000) : 0;
  [self.player pause];
  self.player = nil;
  self.controller.onDisappear = nil;
  if (self.controller.presentingViewController != nil) [self.controller dismissViewControllerAnimated:NO completion:nil];
  self.controller = nil;
  self.inPip = NO;
  result(@(ms));
}

#pragma mark - AVPlayerViewControllerDelegate

- (void)playerViewControllerWillStartPictureInPicture:(AVPlayerViewController *)playerViewController {
  self.inPip = YES;
}

- (void)playerViewControllerDidStopPictureInPicture:(AVPlayerViewController *)playerViewController {
  self.inPip = NO;
  // Si al cerrar la ventanita el reproductor no volvió a la pantalla, se termina.
  if (self.controller.presentingViewController == nil) [self finish];
}

- (void)playerViewController:(AVPlayerViewController *)playerViewController failedToStartPictureInPictureWithError:(NSError *)error {
  self.inPip = NO;
}

/// Al tocar "volver" en la ventanita: se muestra otra vez el reproductor a pantalla completa.
- (void)playerViewController:(AVPlayerViewController *)playerViewController
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:(void (^)(BOOL restored))completionHandler {
  UIViewController *top = TopController();
  if (top == nil || playerViewController.presentingViewController != nil) {
    completionHandler(YES);
    return;
  }
  [top presentViewController:playerViewController animated:YES completion:^{
    completionHandler(YES);
  }];
}

@end
