Pod::Spec.new do |s|
  s.name             = 'dynamic_icon_changer'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for changing app icons dynamically.'
  s.description      = <<-DESC
A Flutter plugin for changing app icons dynamically at runtime on Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/srkstudios/dynamic_icon_changer'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'SRK Studios' => 'dev@srkstudios.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
end
