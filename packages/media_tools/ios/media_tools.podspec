Pod::Spec.new do |s|
  s.name             = 'media_tools'
  s.version          = '1.0.0'
  s.summary          = 'Une video y audio en MP4 (AVFoundation), convierte a MP3 con LAME, ejecuta JavaScript (JavaScriptCore) y ecualiza el audio de just_audio.'
  s.homepage         = 'https://github.com/markoYam'
  s.license          = { :type => 'LGPL (LAME) / propio' }
  s.author           = { 'Marco Yam' => 'marco.yam.catina@gmail.com' }
  s.source           = { :path => '.' }
  # Los .c de Classes/lame solo incluyen las fuentes compartidas de ../src/lame (igual que Android).
  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/MediaToolsPlugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'AVFoundation', 'AVKit', 'CoreMedia', 'JavaScriptCore', 'MediaToolbox', 'UIKit'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) STDC_HEADERS=1 HAVE_STDINT_H=1 HAVE_STRING_H=1 HAVE_STDLIB_H=1 HAVE_LIMITS_H=1 ieee754_float32_t=float',
    'GCC_WARN_INHIBIT_ALL_WARNINGS' => 'YES',
  }
end
