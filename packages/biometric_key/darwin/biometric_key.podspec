# The device-bound vault key (SPEC §9.1) for iOS and macOS. One Swift source
# for both (`sharedDarwinSource`).
Pod::Spec.new do |s|
  s.name             = 'biometric_key'
  s.version          = '0.1.0'
  s.summary          = 'DevVault: a vault key behind Face ID / Touch ID.'
  s.homepage         = 'https://github.com/kmrifat/devvault'
  s.license          = { :type => 'Proprietary' }
  s.author           = 'Binary Castle'
  s.source           = { :path => '.' }
  s.source_files     = 'biometric_key/Sources/biometric_key/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.frameworks = 'LocalAuthentication', 'Security'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
