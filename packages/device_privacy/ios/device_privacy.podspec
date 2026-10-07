# Privacy screen and sensitive clipboard for iOS (P3-06).
Pod::Spec.new do |s|
  s.name             = 'device_privacy'
  s.version          = '0.1.0'
  s.summary          = 'DevVault: app switcher cover and sensitive clipboard.'
  s.homepage         = 'https://github.com/kmrifat/devvault'
  s.license          = { :type => 'Proprietary' }
  s.author           = 'Binary Castle'
  s.source           = { :path => '.' }
  s.source_files     = 'device_privacy/Sources/device_privacy/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
