#import "MediaToolsPlugin.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <JavaScriptCore/JavaScriptCore.h>

#include "../../src/lame/lame.h"
#import "MTEqualizer.h"
#import "MTBackgroundTransfer.h"
#import "MTPip.h"
#import "MTShare.h"

/// Canal "com.marcoyam/media_tools":
/// - mergeAudioVideo: AVMutableComposition + AVAssetExportSession (passthrough, sin recodificar).
/// - transcodeToMp3: AVAssetReader (PCM 16 bits) + LAME.
@interface MediaToolsPlugin ()
/// Motores JavaScript (JavaScriptCore) por id. Se usan en una cola propia, en serie.
@property(nonatomic, strong) NSMutableDictionary<NSString *, JSContext *> *jsContexts;
@property(nonatomic, strong) dispatch_queue_t jsQueue;
@end

@implementation MediaToolsPlugin

- (instancetype)init {
  if ((self = [super init])) {
    _jsContexts = [NSMutableDictionary dictionary];
    _jsQueue = dispatch_queue_create("com.marcoyam.media_tools.js", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel = [FlutterMethodChannel methodChannelWithName:@"com.marcoyam/media_tools"
                                                              binaryMessenger:[registrar messenger]];
  MediaToolsPlugin *instance = [[MediaToolsPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
  // Ecualizador: se engancha a las canciones de just_audio desde el arranque (apagado no cambia nada).
  MTEqualizerInstall();
  // Descargas en segundo plano: la sesión se crea al arrancar para recibir lo que terminó sin la app.
  [registrar addApplicationDelegate:[MTBackgroundTransfer shared]];
  // Enlaces compartidos (esquema videodownloader://) e imagen en imagen: canales propios.
  [MTShare registerWithRegistrar:registrar];
  [MTPip registerWithRegistrar:registrar];
}

static FlutterError *Fail(NSString *message) {
  return [FlutterError errorWithCode:@"media_tools" message:message details:nil];
}

static void Reply(FlutterResult result, FlutterError *error) {
  dispatch_async(dispatch_get_main_queue(), ^{
    result(error);
  });
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  if ([[MTBackgroundTransfer shared] handleMethodCall:call result:result]) return;
  NSDictionary *args = call.arguments;
  if ([call.method isEqualToString:@"mergeAudioVideo"]) {
    [self mergeVideo:args[@"video"] audio:args[@"audio"] output:args[@"output"] result:result];
  } else if ([call.method isEqualToString:@"transcodeToMp3"]) {
    NSNumber *kbps = args[@"bitrateKbps"];
    NSString *input = args[@"input"];
    NSString *output = args[@"output"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      Reply(result, [MediaToolsPlugin transcode:input output:output kbps:kbps ? kbps.intValue : 192]);
    });
  } else if ([call.method isEqualToString:@"jsCreate"]) {
    dispatch_async(self.jsQueue, ^{
      NSString *engineId = [[NSUUID UUID] UUIDString];
      JSContext *context = [[JSContext alloc] init];
      self.jsContexts[engineId] = context;
      dispatch_async(dispatch_get_main_queue(), ^{ result(engineId); });
    });
  } else if ([call.method isEqualToString:@"jsEval"]) {
    NSString *engineId = args[@"id"];
    NSString *code = args[@"code"];
    dispatch_async(self.jsQueue, ^{
      JSContext *context = self.jsContexts[engineId];
      if (!context) { Reply(result, Fail(@"el motor JavaScript ya no existe")); return; }
      context.exception = nil;
      JSValue *value = [context evaluateScript:code];
      if (context.exception) {
        NSString *message = [context.exception toString] ?: @"error de JavaScript";
        context.exception = nil;
        Reply(result, Fail(message));
        return;
      }
      NSString *text = (value == nil || value.isUndefined || value.isNull) ? nil : [value toString];
      dispatch_async(dispatch_get_main_queue(), ^{ result(text); });
    });
  } else if ([call.method isEqualToString:@"setEqualizer"]) {
    NSArray<NSNumber *> *frequencies = args[@"frequencies"];
    NSArray<NSNumber *> *gains = args[@"gains"];
    MTEqualizerSet([args[@"enabled"] boolValue], [frequencies isKindOfClass:[NSArray class]] ? frequencies : @[],
                   [gains isKindOfClass:[NSArray class]] ? gains : @[]);
    result(nil);
  } else if ([call.method isEqualToString:@"jsDispose"]) {
    NSString *engineId = args[@"id"];
    dispatch_async(self.jsQueue, ^{
      [self.jsContexts removeObjectForKey:engineId];
      dispatch_async(dispatch_get_main_queue(), ^{ result(nil); });
    });
  } else {
    result(FlutterMethodNotImplemented);
  }
}

#pragma mark - Unir video y audio

- (void)mergeVideo:(NSString *)videoPath audio:(NSString *)audioPath output:(NSString *)outputPath result:(FlutterResult)result {
  AVURLAsset *video = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:videoPath] options:nil];
  AVURLAsset *audio = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:audioPath] options:nil];
  AVAssetTrack *videoTrack = [[video tracksWithMediaType:AVMediaTypeVideo] firstObject];
  AVAssetTrack *audioTrack = [[audio tracksWithMediaType:AVMediaTypeAudio] firstObject];
  if (!videoTrack) { result(Fail(@"el archivo de video no contiene pista de video")); return; }
  if (!audioTrack) { result(Fail(@"el archivo de audio no contiene pista de audio")); return; }

  AVMutableComposition *composition = [AVMutableComposition composition];
  NSError *error = nil;
  AVMutableCompositionTrack *v = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                          preferredTrackID:kCMPersistentTrackID_Invalid];
  [v insertTimeRange:CMTimeRangeMake(kCMTimeZero, video.duration) ofTrack:videoTrack atTime:kCMTimeZero error:&error];
  if (error) { result(Fail(error.localizedDescription)); return; }
  v.preferredTransform = videoTrack.preferredTransform;

  AVMutableCompositionTrack *a = [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                                          preferredTrackID:kCMPersistentTrackID_Invalid];
  CMTime audioLength = CMTimeMinimum(audio.duration, video.duration);
  [a insertTimeRange:CMTimeRangeMake(kCMTimeZero, audioLength) ofTrack:audioTrack atTime:kCMTimeZero error:&error];
  if (error) { result(Fail(error.localizedDescription)); return; }

  NSURL *outURL = [NSURL fileURLWithPath:outputPath];
  [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
  AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:composition
                                                                  presetName:AVAssetExportPresetPassthrough];
  if (!export) { result(Fail(@"no se pudo preparar la exportación")); return; }
  export.outputURL = outURL;
  export.outputFileType = AVFileTypeMPEG4;
  export.shouldOptimizeForNetworkUse = YES;
  [export exportAsynchronouslyWithCompletionHandler:^{
    if (export.status == AVAssetExportSessionStatusCompleted) {
      Reply(result, nil);
    } else {
      [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
      NSString *why = export.error.localizedDescription ?: @"la exportación falló";
      Reply(result, Fail(why));
    }
  }];
}

#pragma mark - MP3

+ (FlutterError *)transcode:(NSString *)inputPath output:(NSString *)outputPath kbps:(int)kbps {
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:inputPath] options:nil];
  AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
  if (!track) return Fail(@"el archivo no contiene pista de audio");

  double sampleRate = 44100;
  int channels = 2;
  CMFormatDescriptionRef description = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
  if (description) {
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description);
    if (asbd && asbd->mSampleRate > 0) sampleRate = asbd->mSampleRate;
    if (asbd && asbd->mChannelsPerFrame == 1) channels = 1;
  }

  NSError *error = nil;
  AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&error];
  if (!reader) return Fail(error.localizedDescription ?: @"no se pudo leer el audio");
  NSDictionary *settings = @{
    AVFormatIDKey : @(kAudioFormatLinearPCM),
    AVLinearPCMBitDepthKey : @16,
    AVLinearPCMIsFloatKey : @NO,
    AVLinearPCMIsBigEndianKey : @NO,
    AVLinearPCMIsNonInterleaved : @NO,
    AVSampleRateKey : @(sampleRate),
    AVNumberOfChannelsKey : @(channels),
  };
  AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:settings];
  output.alwaysCopiesSampleData = NO;
  if (![reader canAddOutput:output]) return Fail(@"no se puede decodificar este audio");
  [reader addOutput:output];
  if (![reader startReading]) return Fail(reader.error.localizedDescription ?: @"no se pudo leer el audio");

  lame_t gf = lame_init();
  lame_set_num_channels(gf, channels);
  lame_set_in_samplerate(gf, (int)sampleRate);
  lame_set_brate(gf, kbps);
  lame_set_mode(gf, channels == 2 ? JOINT_STEREO : MONO);
  lame_set_VBR(gf, vbr_off);
  lame_set_quality(gf, 3);
  lame_set_bWriteVbrTag(gf, 0);
  lame_set_write_id3tag_automatic(gf, 0); // la etiqueta ID3 la agrega la app (UTF-16)
  if (lame_init_params(gf) < 0) {
    lame_close(gf);
    [reader cancelReading];
    return Fail(@"LAME no aceptó los parámetros de audio");
  }

  FILE *file = fopen(outputPath.fileSystemRepresentation, "wb");
  if (!file) {
    lame_close(gf);
    [reader cancelReading];
    return Fail(@"no se pudo crear el archivo MP3");
  }

  size_t pcmCapacity = 0;
  short *pcm = NULL;
  size_t mp3Capacity = 0;
  unsigned char *mp3 = NULL;
  FlutterError *failure = nil;

  CMSampleBufferRef sample = NULL;
  while (!failure && (sample = [output copyNextSampleBuffer])) {
    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
    size_t length = block ? CMBlockBufferGetDataLength(block) : 0;
    if (length > 0) {
      if (length > pcmCapacity) {
        pcmCapacity = length;
        pcm = realloc(pcm, pcmCapacity);
      }
      CMBlockBufferCopyDataBytes(block, 0, length, pcm);
      int frames = (int)(length / (sizeof(short) * channels));
      size_t needed = (size_t)frames * 5 / 4 + 7200;
      if (needed > mp3Capacity) {
        mp3Capacity = needed;
        mp3 = realloc(mp3, mp3Capacity);
      }
      int written = channels == 2
          ? lame_encode_buffer_interleaved(gf, pcm, frames, mp3, (int)mp3Capacity)
          : lame_encode_buffer(gf, pcm, pcm, frames, mp3, (int)mp3Capacity);
      if (written < 0) {
        failure = Fail([NSString stringWithFormat:@"error de LAME al codificar (%d)", written]);
      } else if (written > 0) {
        fwrite(mp3, 1, (size_t)written, file);
      }
    }
    CFRelease(sample);
  }

  if (!failure && reader.status == AVAssetReaderStatusFailed) {
    failure = Fail(reader.error.localizedDescription ?: @"falló la lectura del audio");
  }
  if (!failure) {
    unsigned char tail[7200 + 16384];
    int written = lame_encode_flush(gf, tail, sizeof(tail));
    if (written > 0) fwrite(tail, 1, (size_t)written, file);
  } else {
    [reader cancelReading];
  }

  fclose(file);
  lame_close(gf);
  free(pcm);
  free(mp3);
  if (failure) [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
  return failure;
}

@end
