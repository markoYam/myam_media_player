#import <Foundation/Foundation.h>

/// Ecualizador para el audio de just_audio en iOS.
///
/// just_audio reproduce con un AVQueuePlayer y mete cada canción con -insertItem:afterItem:.
/// Al instalarlo, ese método se intercepta y a cada canción se le agrega un "audio tap"
/// (MTAudioProcessingTap) que pasa el sonido por los filtros de MTEqualizerDSP. Así funciona igual
/// con streaming, mixtape y descargas, sin modificar just_audio. Apagado, el audio pasa sin cambios.
NS_ASSUME_NONNULL_BEGIN

/// Engancha el ecualizador (una sola vez; llamarlo de nuevo no hace nada).
void MTEqualizerInstall(void);

/// Ajuste actual: se aplica en vivo a lo que esté sonando y a lo que venga.
void MTEqualizerSet(BOOL enabled, NSArray<NSNumber *> *frequencies, NSArray<NSNumber *> *gains);

NS_ASSUME_NONNULL_END
