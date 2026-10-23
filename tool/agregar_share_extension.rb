#!/usr/bin/env ruby
# Agrega la extensión "Compartir" (target ShareExtension) al proyecto de iOS.
#
# Uso, desde la carpeta del proyecto, en la Mac (una sola vez; si ya existe no hace nada):
#
#     ruby tool/agregar_share_extension.rb
#
# Usa la gema xcodeproj, que ya viene con CocoaPods. Si no la encuentra:
#     sudo gem install xcodeproj      (o: brew install cocoapods)
#
# Qué hace:
#   1. Copia tool/ios_share_extension/ a ios/ShareExtension/.
#   2. Crea el target ShareExtension (Swift, iOS 14+) con bundle id <id de la app>.ShareExtension,
#      el mismo equipo de firma que Runner y APPLICATION_EXTENSION_API_ONLY = YES (Xcode lo exige
#      en las extensiones; la app se abre por el runtime, ver ShareViewController.swift).
#   3. Lo inserta en Runner (fase "Embed App Extensions", antes de "Thin Binary" para evitar el
#      error de "Cycle inside Runner").
#
# Después, en Xcode (ios/Runner.xcworkspace): target ShareExtension → Signing & Capabilities →
# elige el MISMO equipo que Runner. Con una cuenta gratuita de Apple también funciona (7 días).
# El esquema videodownloader:// lo agrega tool/configurar_plataformas.py al Info.plist de Runner.

require 'fileutils'

begin
  require 'xcodeproj'
rescue LoadError
  abort 'Falta la gema xcodeproj: instala CocoaPods (brew install cocoapods) o ejecuta: sudo gem install xcodeproj'
end

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'ios', 'Runner.xcodeproj')
SOURCES = File.join(ROOT, 'tool', 'ios_share_extension')
DEST = File.join(ROOT, 'ios', 'ShareExtension')
TARGET_NAME = 'ShareExtension'

abort "No existe #{PROJECT_PATH}. Ejecuta antes: flutter create --platforms ios ." unless File.exist?(PROJECT_PATH)

project = Xcodeproj::Project.open(PROJECT_PATH)
if project.targets.any? { |t| t.name == TARGET_NAME }
  puts 'La extensión ShareExtension ya está en el proyecto: no hay nada que hacer.'
  exit 0
end

app = project.targets.find { |t| t.name == 'Runner' } or abort 'No encontré el target Runner.'

# Versión de pubspec.yaml ("1.2.3+4"): la extensión debe tener la misma que la app.
pubspec = File.read(File.join(ROOT, 'pubspec.yaml'))
version_line = pubspec[/^version:\s*(\S+)/, 1] || '1.0.0+1'
marketing, build = version_line.split('+')
build ||= '1'

FileUtils.mkdir_p(DEST)
%w[ShareViewController.swift Info.plist].each { |f| FileUtils.cp(File.join(SOURCES, f), File.join(DEST, f)) }

target = project.new_target(:app_extension, TARGET_NAME, :ios, '14.0', nil, :swift)
group = project.main_group.find_subpath(TARGET_NAME, true)
group.set_source_tree('<group>')
group.set_path(TARGET_NAME)
swift = group.new_reference('ShareViewController.swift')
group.new_reference('Info.plist')
target.add_file_references([swift])

# Flutter usa también la configuración "Profile".
project.build_configurations.map(&:name).each do |name|
  next if target.build_configurations.any? { |c| c.name == name }
  target.add_build_configuration(name, name == 'Debug' ? :debug : :release)
end

app_settings = app.build_configurations.map(&:build_settings)
bundle_id = app_settings.map { |s| s['PRODUCT_BUNDLE_IDENTIFIER'] }.compact.first or abort 'Runner no tiene PRODUCT_BUNDLE_IDENTIFIER.'
team = app_settings.map { |s| s['DEVELOPMENT_TEAM'] }.compact.first

target.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = "#{bundle_id}.#{TARGET_NAME}"
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = "#{TARGET_NAME}/Info.plist"
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '14.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = team if team
  s['MARKETING_VERSION'] = marketing
  s['CURRENT_PROJECT_VERSION'] = build
  s['SKIP_INSTALL'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

# Meter la extensión dentro de la app.
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' || p.name == 'Embed Foundation Extensions' }
embed ||= app.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
file = embed.add_file_reference(target.product_reference, true)
file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
app.add_dependency(target)

# La fase de copiar extensiones va antes de los scripts de Flutter ("Thin Binary").
thin = app.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin
  app.build_phases.delete(embed)
  thin = app.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
  app.build_phases.insert(thin, embed)
end

project.save
puts "Listo: target #{TARGET_NAME} (#{bundle_id}.#{TARGET_NAME}) agregado e insertado en Runner."
puts team ? "Firma: mismo equipo que Runner (#{team})." : 'Abre ios/Runner.xcworkspace y elige tu equipo en ShareExtension → Signing & Capabilities.'
puts 'Después: flutter run'
