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
    yield LicenseEntryWithLineBreaks(
      ['Colibri (port OLMoE CPU)'],
      await rootBundle.loadString('assets/colibri_notices.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      ['LLVM / OpenMP (Android NDK)'],
      await rootBundle.loadString('assets/llvm_notices.txt'),
    );
  });
}
