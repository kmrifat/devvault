// Desktop UI spike: sample data shared by the three kit screens. Not
// shipped; see lib/spike/desktop_spike.dart.

class SpikeItem {
  const SpikeItem(
    this.title,
    this.type,
    this.app,
    this.platform,
    this.environment, {
    this.expiry,
    this.file,
  });

  final String title;
  final String type;
  final String app;
  final String platform;
  final String environment;
  final String? expiry;
  final String? file;
}

const spikeItems = [
  SpikeItem(
    'Upload keystore',
    'Android Keystore',
    'Kitchenly',
    'android',
    'production',
    expiry: 'Jan 2051',
    file: 'kitchenly-upload.jks',
  ),
  SpikeItem(
    'APNs auth key',
    'Apple Auth Key',
    'Kitchenly',
    'ios',
    'production',
    file: 'AuthKey_7X2K9QH4LM.p8',
  ),
  SpikeItem(
    'Distribution certificate',
    'Apple Certificate',
    'Kitchenly',
    'ios',
    'production',
    expiry: 'Expired',
    file: 'distribution.p12',
  ),
  SpikeItem(
    'App Store profile',
    'Provisioning Profile',
    'Kitchenly',
    'ios',
    'production',
    expiry: '20 days',
    file: 'Kitchenly_AppStore.mobileprovision',
  ),
  SpikeItem(
    'Firebase config',
    'Firebase Config',
    'Kitchenly',
    'android',
    'staging',
    file: 'google-services.json',
  ),
  SpikeItem(
    'Play publisher',
    'GCP Service Account',
    'Kitchenly',
    'android',
    'production',
    expiry: '12 days',
    file: 'play-publisher.json',
  ),
  SpikeItem(
    'Stripe secret key',
    'Generic Secret',
    'Ledgerly',
    'server',
    'production',
  ),
  SpikeItem(
    'Deploy key',
    'SSH Key',
    'Ledgerly',
    'server',
    'staging',
    file: 'id_ed25519',
  ),
];

const spikePlatforms = ['ios', 'android', 'macos', 'web', 'server'];
const spikeEnvironments = ['production', 'staging', 'development'];
