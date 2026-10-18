/// Możliwości aktualnego adaptera Scalającej, nie wszystkich modeli dostawcy.
class ProviderDescriptor {
  const ProviderDescriptor({
    required this.id,
    required this.authentication,
    required this.processing,
    required this.status,
    required this.documentationUrl,
    this.supportsText = true,
    this.supportsStreaming = true,
  });
  final String id;
  final String authentication;
  final String processing;
  final String status;
  final String documentationUrl;
  final bool supportsText;
  final bool supportsStreaming;
  bool get supportsImages => false;
  bool get supportsFiles => false;
  bool get supportsTools => false;
  String get additionalCapabilities =>
      'Zaplanowane; nieobsługiwane przez obecny adapter';
  String get limits => 'Zależne od modelu i konta; niezweryfikowane na koncie';
  String get prices => 'Nieznane; sprawdź cennik i rozliczenia dostawcy';
  String get verifiedOn => '2026-10-17';
}

const providerDescriptors = <String, ProviderDescriptor>{
  'minicpm_local': ProviderDescriptor(
    id: 'minicpm_local',
    authentication: 'Bez konta i klucza API; import GGUF',
    processing:
        'Wyłącznie na tym telefonie, CPU llama.cpp, bez sieci i fallbacku',
    status: 'eksperymentalna — wymaga zgodnego GGUF i zasobów urządzenia',
    documentationUrl: 'https://github.com/OpenBMB/MiniCPM',
  ),
  'minicpm': ProviderDescriptor(
    id: 'minicpm',
    authentication: 'Własny serwer HTTPS; opcjonalny klucz jego API',
    processing: 'Na wskazanym serwerze; inferencja wbudowana w APK zaplanowana',
    status: 'eksperymentalna — wymaga konfiguracji własnego serwera',
    documentationUrl: 'https://github.com/OpenBMB/MiniCPM',
  ),
  'demo': ProviderDescriptor(
    id: 'demo',
    authentication: 'Brak — lokalna atrapa',
    processing: 'Wyłącznie na urządzeniu; bez modelu AI',
    status: 'działa — demo lokalne',
    documentationUrl: '',
  ),
  'openai': ProviderDescriptor(
    id: 'openai',
    authentication: 'Własny klucz API; SSO zaplanowane',
    processing: 'Chmura OpenAI; brak gwarancji regionu w obecnym adapterze',
    status: 'wymaga konfiguracji',
    documentationUrl:
        'https://developers.openai.com/api/docs/guides/streaming-responses',
  ),
  'anthropic': ProviderDescriptor(
    id: 'anthropic',
    authentication: 'Własny klucz API ograniczony do workspace',
    processing: 'Chmura Anthropic; warunki retencji zależą od modelu i konta',
    status: 'wymaga konfiguracji',
    documentationUrl:
        'https://platform.claude.com/docs/en/manage-claude/authentication',
  ),
  'gemini': ProviderDescriptor(
    id: 'gemini',
    authentication: 'Własny klucz projektu; OAuth zaplanowane',
    processing: 'Chmura Google; warunki Paid/Unpaid i regionu wymagają oceny',
    status: 'wymaga konfiguracji i oceny zgodności warunków',
    documentationUrl: 'https://ai.google.dev/gemini-api/terms',
  ),
  'xai': ProviderDescriptor(
    id: 'xai',
    authentication: 'Własny klucz API xAI Console',
    processing: 'Chmura xAI; globalny endpoint nie gwarantuje regionu',
    status: 'wymaga konfiguracji',
    documentationUrl: 'https://docs.x.ai/developers/faq/security',
  ),
};
