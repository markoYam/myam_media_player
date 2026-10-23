#import "MTEqualizer.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaToolbox/MediaToolbox.h>
#import <objc/runtime.h>
#import <os/lock.h>
#import <stdatomic.h>

#include "MTEqualizerDSP.h"

#pragma mark - Ajuste compartido (hilo principal escribe, hilo de audio lee)

static os_unfair_lock gLock = OS_UNFAIR_LOCK_INIT;
static int gCount = 0;
static double gFreqs[MT_EQ_MAX_BANDS];
static double gGains[MT_EQ_MAX_BANDS];
static atomic_bool gEnabled = false;
/// Sube con cada cambio; cada canción recalcula sus filtros cuando lo ve distinto.
static atomic_int gVersion = 1;

void MTEqualizerSet(BOOL enabled, NSArray<NSNumber *> *frequencies, NSArray<NSNumber *> *gains) {
  os_unfair_lock_lock(&gLock);
  int count = (int)MIN(MIN(frequencies.count, gains.count), (NSUInteger)MT_EQ_MAX_BANDS);
  for (int i = 0; i < count; i++) {
    gFreqs[i] = frequencies[i].doubleValue;
    gGains[i] = gains[i].doubleValue;
  }
  gCount = count;
  os_unfair_lock_unlock(&gLock);
  atomic_store(&gEnabled, (bool)enabled);
  atomic_fetch_add(&gVersion, 1);
}

#pragma mark - Audio tap

typedef struct {
  mt_eq eq;
  double sampleRate;
  int channels;
  bool usable;       // formato float de 32 bits (el habitual de AVFoundation)
  bool interleaved;
  int version;
  bool wasEnabled;
} TapContext;

static void TapInit(MTAudioProcessingTapRef tap, void *clientInfo, void **tapStorageOut) {
  TapContext *ctx = calloc(1, sizeof(TapContext));
  ctx->version = -1;
  *tapStorageOut = ctx;
}

static void TapFinalize(MTAudioProcessingTapRef tap) { free(MTAudioProcessingTapGetStorage(tap)); }

static void TapPrepare(MTAudioProcessingTapRef tap, CMItemCount maxFrames, const AudioStreamBasicDescription *format) {
  TapContext *ctx = MTAudioProcessingTapGetStorage(tap);
  ctx->sampleRate = format->mSampleRate;
  ctx->channels = (int)format->mChannelsPerFrame;
  ctx->usable = (format->mFormatFlags & kAudioFormatFlagIsFloat) && format->mBitsPerChannel == 32 && ctx->sampleRate > 0;
  ctx->interleaved = !(format->mFormatFlags & kAudioFormatFlagIsNonInterleaved);
  ctx->version = -1;  // formato nuevo: recalcular filtros
  mt_eq_reset(&ctx->eq);
}

static void TapUnprepare(MTAudioProcessingTapRef tap) {}

static void TapProcess(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags,
                       AudioBufferList *buffers, CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut) {
  if (MTAudioProcessingTapGetSourceAudio(tap, numberFrames, buffers, flagsOut, NULL, numberFramesOut) != noErr) return;
  TapContext *ctx = MTAudioProcessingTapGetStorage(tap);
  const bool enabled = atomic_load(&gEnabled);
  if (!ctx->usable || !enabled) {
    ctx->wasEnabled = false;
    return;
  }
  const int version = atomic_load(&gVersion);
  // En el hilo de audio no se espera un candado: si está ocupado, se usan los filtros anteriores.
  if (version != ctx->version && os_unfair_lock_trylock(&gLock)) {
    mt_eq_design(&ctx->eq, ctx->sampleRate, gCount, gFreqs, gGains);
    os_unfair_lock_unlock(&gLock);
    ctx->version = version;
  }
  if (ctx->version < 0) return;
  if (!ctx->wasEnabled) {
    mt_eq_reset(&ctx->eq);  // al encender, sin memoria vieja (evita un chasquido)
    ctx->wasEnabled = true;
  }
  const long frames = (long)*numberFramesOut;
  for (UInt32 b = 0; b < buffers->mNumberBuffers; b++) {
    float *data = (float *)buffers->mBuffers[b].mData;
    if (data == NULL) continue;
    const int perBuffer = (int)buffers->mBuffers[b].mNumberChannels;
    if (ctx->interleaved && perBuffer > 1) {
      for (int ch = 0; ch < perBuffer; ch++) mt_eq_process(&ctx->eq, ch, data + ch, frames, perBuffer);
    } else {
      mt_eq_process(&ctx->eq, (int)b, data, frames, 1);
    }
  }
}

#pragma mark - Agregar el tap a cada canción

static const void *kEqualizerAttachedKey = &kEqualizerAttachedKey;

static void MTAttachEqualizer(AVPlayerItem *item) {
  if (item == nil || objc_getAssociatedObject(item, kEqualizerAttachedKey) != nil) return;
  objc_setAssociatedObject(item, kEqualizerAttachedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  AVAsset *asset = item.asset;
  __weak AVPlayerItem *weakItem = item;
  [asset loadValuesAsynchronouslyForKeys:@[ @"tracks" ]
                       completionHandler:^{
                         if ([asset statusOfValueForKey:@"tracks" error:nil] != AVKeyValueStatusLoaded) return;
                         NSArray<AVAssetTrack *> *tracks = [asset tracksWithMediaType:AVMediaTypeAudio];
                         if (tracks.count == 0) return;
                         NSMutableArray<AVAudioMixInputParameters *> *params = [NSMutableArray array];
                         for (AVAssetTrack *track in tracks) {
                           MTAudioProcessingTapCallbacks callbacks = {
                               .version = kMTAudioProcessingTapCallbacksVersion_0,
                               .clientInfo = NULL,
                               .init = TapInit,
                               .finalize = TapFinalize,
                               .prepare = TapPrepare,
                               .unprepare = TapUnprepare,
                               .process = TapProcess,
                           };
                           MTAudioProcessingTapRef tap = NULL;
                           if (MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                                          kMTAudioProcessingTapCreationFlag_PostEffects, &tap) != noErr ||
                               tap == NULL) {
                             continue;
                           }
                           AVMutableAudioMixInputParameters *p =
                               [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
                           p.audioTapProcessor = tap;
                           CFRelease(tap);
                           [params addObject:p];
                         }
                         if (params.count == 0) return;
                         AVMutableAudioMix *mix = [AVMutableAudioMix audioMix];
                         mix.inputParameters = params;
                         dispatch_async(dispatch_get_main_queue(), ^{
                           AVPlayerItem *strongItem = weakItem;
                           if (strongItem != nil && strongItem.audioMix == nil) strongItem.audioMix = mix;
                         });
                       }];
}

@implementation AVQueuePlayer (MTEqualizer)

- (void)mt_insertItem:(AVPlayerItem *)item afterItem:(nullable AVPlayerItem *)afterItem {
  MTAttachEqualizer(item);
  [self mt_insertItem:item afterItem:afterItem];  // implementación original (intercambiada)
}

@end

void MTEqualizerInstall(void) {
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    Method original = class_getInstanceMethod([AVQueuePlayer class], @selector(insertItem:afterItem:));
    Method replacement = class_getInstanceMethod([AVQueuePlayer class], @selector(mt_insertItem:afterItem:));
    if (original != NULL && replacement != NULL) method_exchangeImplementations(original, replacement);
  });
}
