import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

const bool useLocalBackend = false;
const bool isEmulator = true;

String getBaseUrl() {
  if (useLocalBackend) {
    if (kIsWeb) {
      return 'http://localhost:5001';
    }
    if (Platform.isAndroid) {
      if (isEmulator) {
        return 'http://10.0.2.2:5001'; 
      } else {
        return 'http://10.139.243.125:5001'; 
      }
    }
    return 'http://localhost:5001';
  }
  return 'https://call-backend-fzhj.onrender.com';
}
