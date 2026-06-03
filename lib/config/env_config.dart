class EnvConfig {
  static const mapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static const googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const googleClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');
  static const androidCert = String.fromEnvironment('ANDROID_CERT');
  static const appleServiceId = String.fromEnvironment('APPLE_SERVICE_ID');
  static const appleRedirectUri = String.fromEnvironment('APPLE_REDIRECT_URI');
}
