import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;
void registerNativeLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['llama.cpp / GGML / szablony MiniCPM'],
      await rootBundle.loadString('assets/native_notices.txt'),
    );
  });
}
