Pod::Spec.new do |s|
  s.name             = 'dynamic_app_icon_changer'
  s.version          = '0.0.3'
  s.summary          = 'Flutter plugin for changing app icons dynamically.'
  s.description      = <<-DESC
A Flutter plugin for changing app icons dynamically at runtime.
On macOS this changes the Dock icon using NSApplication.
                       DESC
  s.homepage         = 'https://github.com/srkstudios/dynamic_app_icon_changer'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SRK Studios' => 'dev@srkstudios.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.14'
  s.swift_version    = '5.0'
end
