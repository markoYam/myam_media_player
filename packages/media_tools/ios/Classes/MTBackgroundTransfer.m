#import "MTBackgroundTransfer.h"

static NSString *const kSessionId = @"com.marcoyam.videodownloader.background";
static NSString *const kLedgerKey = @"mt_bg_ledger";

/// Registro persistente (NSUserDefaults) por id de bloque: destino, estado, HTTP y error.
/// Sobrevive a que iOS cierre la app: al volver, Dart pregunta cómo quedó cada bloque.
@interface MTBackgroundTransfer ()
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, copy, nullable) void (^systemCompletion)(void);
@end

@implementation MTBackgroundTransfer

+ (instancetype)shared {
  static MTBackgroundTransfer *instance;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    instance = [[MTBackgroundTransfer alloc] init];
  });
  return instance;
}

- (instancetype)init {
  if ((self = [super init])) {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:kSessionId];
    config.sessionSendsLaunchEvents = YES;
    config.discretionary = NO;
    config.allowsCellularAccess = YES;
    config.HTTPMaximumConnectionsPerHost = 3;
    config.timeoutIntervalForRequest = 60;
    NSOperationQueue *queue = [[NSOperationQueue alloc] init];
    queue.maxConcurrentOperationCount = 1;
    // Crear la sesión con el mismo id al arrancar reconecta las transferencias que siguieron sin la app.
    _session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:queue];
  }
  return self;
}

#pragma mark - Registro

- (NSMutableDictionary<NSString *, NSDictionary *> *)ledger {
  NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kLedgerKey];
  return saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)updateEntry:(NSString *)transferId with:(NSDictionary *)changes {
  @synchronized(self) {
    NSMutableDictionary *ledger = [self ledger];
    NSMutableDictionary *entry = [ledger[transferId] mutableCopy] ?: [NSMutableDictionary dictionary];
    [entry addEntriesFromDictionary:changes];
    ledger[transferId] = entry;
    [[NSUserDefaults standardUserDefaults] setObject:ledger forKey:kLedgerKey];
  }
}

- (void)removeEntriesWithPrefix:(NSString *)prefix {
  @synchronized(self) {
    NSMutableDictionary *ledger = [self ledger];
    for (NSString *key in ledger.allKeys) {
      if ([key hasPrefix:prefix]) [ledger removeObjectForKey:key];
    }
    [[NSUserDefaults standardUserDefaults] setObject:ledger forKey:kLedgerKey];
  }
}

#pragma mark - Canal

- (BOOL)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *args = [call.arguments isKindOfClass:[NSDictionary class]] ? call.arguments : @{};
  if ([call.method isEqualToString:@"bgEnqueue"]) {
    [self enqueue:args result:result];
    return YES;
  }
  if ([call.method isEqualToString:@"bgStatus"]) {
    [self statusWithPrefix:args[@"prefix"] ?: @"" result:result];
    return YES;
  }
  if ([call.method isEqualToString:@"bgCancel"]) {
    [self cancelWithPrefix:args[@"prefix"] ?: @"" result:result];
    return YES;
  }
  return NO;
}

- (void)enqueue:(NSDictionary *)args result:(FlutterResult)result {
  NSString *transferId = args[@"id"];
  NSURL *url = [NSURL URLWithString:args[@"url"] ?: @""];
  NSString *destination = args[@"destination"];
  if (transferId.length == 0 || url == nil || destination.length == 0) {
    result([FlutterError errorWithCode:@"media_tools" message:@"bgEnqueue: faltan id, url o destino" details:nil]);
    return;
  }
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.HTTPMethod = args[@"method"] ?: @"GET";
  NSDictionary *headers = args[@"headers"];
  if ([headers isKindOfClass:[NSDictionary class]]) {
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
      [request setValue:[value description] forHTTPHeaderField:[key description]];
    }];
  }
  id body = args[@"body"];
  if ([body isKindOfClass:[FlutterStandardTypedData class]]) request.HTTPBody = ((FlutterStandardTypedData *)body).data;

  [self updateEntry:transferId with:@{@"destination" : destination, @"state" : @"running"}];
  NSURLSessionDownloadTask *task = [self.session downloadTaskWithRequest:request];
  task.taskDescription = transferId;
  [task resume];
  result(nil);
}

- (void)statusWithPrefix:(NSString *)prefix result:(FlutterResult)result {
  [self.session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSDictionary *ledger;
    @synchronized(self) {
      ledger = [self ledger];
    }
    for (NSString *key in ledger) {
      if (![key hasPrefix:prefix]) continue;
      NSMutableDictionary *entry = [ledger[key] mutableCopy];
      // "running" en el registro pero sin tarea viva = se perdió (p. ej. la app se cerró a mano).
      if ([entry[@"state"] isEqualToString:@"running"]) entry[@"state"] = @"lost";
      out[key] = entry;
    }
    for (NSURLSessionTask *task in tasks) {
      NSString *key = task.taskDescription;
      if (key == nil || ![key hasPrefix:prefix]) continue;
      if (task.state != NSURLSessionTaskStateRunning && task.state != NSURLSessionTaskStateSuspended) continue;
      NSMutableDictionary *entry = [out[key] mutableCopy] ?: [NSMutableDictionary dictionary];
      entry[@"state"] = @"running";
      entry[@"bytes"] = @(task.countOfBytesReceived);
      out[key] = entry;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      result(out);
    });
  }];
}

- (void)cancelWithPrefix:(NSString *)prefix result:(FlutterResult)result {
  [self.session getAllTasksWithCompletionHandler:^(NSArray<__kindof NSURLSessionTask *> *tasks) {
    for (NSURLSessionTask *task in tasks) {
      if ([task.taskDescription hasPrefix:prefix]) [task cancel];
    }
    [self removeEntriesWithPrefix:prefix];
    dispatch_async(dispatch_get_main_queue(), ^{
      result(nil);
    });
  }];
}

#pragma mark - NSURLSessionDownloadDelegate

- (void)URLSession:(NSURLSession *)session
                 downloadTask:(NSURLSessionDownloadTask *)task
    didFinishDownloadingToURL:(NSURL *)location {
  NSString *transferId = task.taskDescription;
  if (transferId == nil) return;
  NSInteger status = [task.response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)task.response).statusCode : 0;
  NSDictionary *entry;
  @synchronized(self) {
    entry = [self ledger][transferId];
  }
  NSString *destination = entry[@"destination"];
  if (destination == nil) return;  // se canceló
  if (status != 200 && status != 206) {
    [self updateEntry:transferId with:@{@"state" : @"failed", @"http" : @(status)}];
    return;
  }
  // El archivo temporal se borra al salir de este método: hay que moverlo ya.
  NSFileManager *fm = [NSFileManager defaultManager];
  NSURL *target = [NSURL fileURLWithPath:destination];
  [fm createDirectoryAtURL:target.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
  [fm removeItemAtURL:target error:nil];
  NSError *error = nil;
  if ([fm moveItemAtURL:location toURL:target error:&error]) {
    [self updateEntry:transferId with:@{@"state" : @"done", @"http" : @(status)}];
  } else {
    [self updateEntry:transferId with:@{@"state" : @"failed", @"error" : error.localizedDescription ?: @"no se pudo guardar"}];
  }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  NSString *transferId = task.taskDescription;
  if (transferId == nil || error == nil) return;
  if (error.code == NSURLErrorCancelled) return;  // cancelado por la app
  [self updateEntry:transferId with:@{@"state" : @"failed", @"error" : error.localizedDescription ?: @"error de red"}];
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
  dispatch_async(dispatch_get_main_queue(), ^{
    void (^completion)(void) = self.systemCompletion;
    self.systemCompletion = nil;
    if (completion) completion();
  });
}

#pragma mark - FlutterApplicationLifeCycleDelegate

- (BOOL)application:(UIApplication *)application
    handleEventsForBackgroundURLSession:(NSString *)identifier
                      completionHandler:(void (^)(void))completionHandler {
  if (![identifier isEqualToString:kSessionId]) return NO;
  self.systemCompletion = completionHandler;
  [MTBackgroundTransfer shared];  // asegura que la sesión exista para recibir los eventos
  return YES;
}

@end
