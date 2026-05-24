import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PrivateShieldApp());
}

class PrivateShieldApp extends StatelessWidget {
  const PrivateShieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PrivateShield Ultimate',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20E3B2),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF07111F),
        cardTheme: CardThemeData(
          color: const Color(0xFF101C2D),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

enum Severity { info, low, medium, high, critical }

extension SeverityLabel on Severity {
  String get label {
    switch (this) {
      case Severity.info:
        return 'Info';
      case Severity.low:
        return 'Faible';
      case Severity.medium:
        return 'Moyen';
      case Severity.high:
        return 'Élevé';
      case Severity.critical:
        return 'Critique';
    }
  }

  int get penalty {
    switch (this) {
      case Severity.info:
        return 0;
      case Severity.low:
        return 3;
      case Severity.medium:
        return 7;
      case Severity.high:
        return 14;
      case Severity.critical:
        return 25;
    }
  }

  Color get color {
    switch (this) {
      case Severity.info:
        return Colors.blueAccent;
      case Severity.low:
        return Colors.lightGreenAccent;
      case Severity.medium:
        return Colors.orangeAccent;
      case Severity.high:
        return Colors.deepOrangeAccent;
      case Severity.critical:
        return Colors.redAccent;
    }
  }
}

class RiskItem {
  RiskItem({
    required this.title,
    required this.description,
    required this.recommendation,
    required this.severity,
    required this.category,
    this.settingsAction,
  });

  final String title;
  final String description;
  final String recommendation;
  final Severity severity;
  final String category;
  final String? settingsAction;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'recommendation': recommendation,
        'severity': severity.label,
        'category': category,
        'settingsAction': settingsAction,
      };
}

class ScanState {
  int score = 100;
  int systemScore = 100;
  int networkScore = 100;
  int privacyScore = 100;
  int radioScore = 100;
  int permissionsScore = 100;
  int behaviorScore = 100;
  List<RiskItem> risks = [];
  Map<String, dynamic> network = {};
  Map<String, dynamic> device = {};
  List<Map<String, dynamic>> bleDevices = [];
  List<Map<String, dynamic>> wifiNetworks = [];
  DateTime? lastScan;

  Map<String, dynamic> toJson() => {
        'app': 'PrivateShield Ultimate',
        'generatedAt': DateTime.now().toIso8601String(),
        'lastScan': lastScan?.toIso8601String(),
        'score': score,
        'subScores': {
          'system': systemScore,
          'network': networkScore,
          'privacy': privacyScore,
          'radio': radioScore,
          'permissions': permissionsScore,
          'behavior': behaviorScore,
        },
        'device': device,
        'network': network,
        'wifiNetworks': wifiNetworks,
        'bleDevices': bleDevices,
        'risks': risks.map((risk) => risk.toJson()).toList(),
      };
}

class SecurityStore {
  static const _checklistKey = 'hardening_checklist_v1';
  static const _historyKey = 'scan_history_v1';

  Future<Map<String, bool>> loadChecklist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_checklistKey);
    if (raw == null) return defaultChecklist();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((key, value) => MapEntry(key, value == true));
  }

  Future<void> saveChecklist(Map<String, bool> checklist) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_checklistKey, jsonEncode(checklist));
  }

  Future<void> saveScan(ScanState scan) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await loadHistory();
    history.insert(0, scan.toJson());
    final limited = history.take(20).toList();
    await prefs.setString(_historyKey, jsonEncode(limited));
  }

  Future<List<Map<String, dynamic>>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  Map<String, bool> defaultChecklist() => {
        'Verrouillage écran fort vérifié': false,
        'Délai de verrouillage court': false,
        'Notifications sensibles masquées': false,
        'Mises à jour Android vérifiées': false,
        'Play Protect vérifié': false,
        'Sources inconnues contrôlées': false,
        'Débogage USB désactivé': false,
        'Options développeur contrôlées': false,
        'Permissions localisation vérifiées': false,
        'Permissions micro vérifiées': false,
        'Permissions caméra vérifiées': false,
        'Apps inutilisées supprimées': false,
        'Bluetooth désactivé si inutile': false,
        'NFC désactivé si inutile': false,
        'VPN prévu pour Wi-Fi public': false,
        'Historique localisation contrôlé': false,
        'Partage position contrôlé': false,
        'Accessibilité apps contrôlée': false,
        'Superposition écran contrôlée': false,
        'Accès utilisation contrôlé': false,
      };
}

class SecurityEngine {
  ScanState compute({required ScanState scan, required Map<String, bool> checklist}) {
    final risks = <RiskItem>[];

    final checkedCount = checklist.values.where((done) => done).length;
    final checklistRatio = checkedCount / checklist.length;

    if (checklistRatio < 0.35) {
      risks.add(RiskItem(
        title: 'Durcissement incomplet',
        description: 'La checklist de sécurité est peu avancée. Les réglages critiques n’ont pas encore été vérifiés.',
        recommendation: 'Va dans “Sécuriser” et valide les contrôles un par un.',
        severity: Severity.high,
        category: 'Comportement',
      ));
    } else if (checklistRatio < 0.7) {
      risks.add(RiskItem(
        title: 'Durcissement partiel',
        description: 'Plusieurs réglages sensibles restent à vérifier.',
        recommendation: 'Termine les contrôles restants pour améliorer le score.',
        severity: Severity.medium,
        category: 'Comportement',
      ));
    }

    for (final entry in checklist.entries) {
      if (!entry.value && _criticalChecklistLabels.contains(entry.key)) {
        risks.add(RiskItem(
          title: entry.key,
          description: 'Ce point fait partie des contrôles prioritaires de sécurité Android.',
          recommendation: 'Ouvre le réglage associé, vérifie la configuration, puis coche ce point.',
          severity: Severity.high,
          category: 'Système',
          settingsAction: _settingsActionFor(entry.key),
        ));
      }
    }

    final bluetoothOn = scan.network['bluetoothState'] == 'on';
    if (bluetoothOn && checklist['Bluetooth désactivé si inutile'] != true) {
      risks.add(RiskItem(
        title: 'Bluetooth actif',
        description: 'Bluetooth peut exposer une présence radio et permettre la détection d’accessoires proches.',
        recommendation: 'Désactive Bluetooth quand tu ne l’utilises pas, surtout en déplacement.',
        severity: Severity.medium,
        category: 'Radio',
        settingsAction: 'android.settings.BLUETOOTH_SETTINGS',
      ));
    }

    final connection = scan.network['connectionType']?.toString().toLowerCase() ?? 'inconnu';
    if (connection.contains('wifi') && checklist['VPN prévu pour Wi-Fi public'] != true) {
      risks.add(RiskItem(
        title: 'VPN non validé pour Wi-Fi public',
        description: 'Sur un Wi-Fi public ou inconnu, le risque d’exposition réseau augmente.',
        recommendation: 'Prévois un VPN fiable ou utilise les données mobiles pour les usages sensibles.',
        severity: Severity.medium,
        category: 'Réseau',
      ));
    }

    final openWifi = scan.wifiNetworks.where((ap) {
      final caps = (ap['security'] ?? '').toString().toLowerCase();
      return caps.isEmpty || caps == 'open' || caps.contains('ess');
    }).length;
    if (openWifi > 0) {
      risks.add(RiskItem(
        title: '$openWifi réseau(x) Wi-Fi ouvert(s) détecté(s)',
        description: 'Des réseaux sans chiffrement peuvent exposer les utilisateurs à des risques réseau.',
        recommendation: 'Évite les Wi-Fi ouverts pour les comptes importants et privilégie données mobiles ou VPN.',
        severity: Severity.medium,
        category: 'Wi-Fi',
      ));
    }

    final suspiciousWifi = _detectSuspiciousWifi(scan.wifiNetworks);
    risks.addAll(suspiciousWifi);

    final recurrentBle = scan.bleDevices.where((d) => (d['rssi'] ?? -100) > -55).length;
    if (recurrentBle >= 3) {
      risks.add(RiskItem(
        title: 'Forte densité Bluetooth proche',
        description: 'Plusieurs appareils BLE avec signal fort sont détectés à proximité.',
        recommendation: 'En environnement sensible, vérifie les accessoires inconnus et désactive Bluetooth si inutile.',
        severity: Severity.low,
        category: 'Anti-tracking',
      ));
    }

    scan.risks = risks;
    scan.systemScore = _bounded(100 - risks.where((r) => r.category == 'Système').fold<int>(0, (sum, r) => sum + r.severity.penalty));
    scan.networkScore = _bounded(100 - risks.where((r) => r.category == 'Réseau' || r.category == 'Wi-Fi').fold<int>(0, (sum, r) => sum + r.severity.penalty));
    scan.radioScore = _bounded(100 - risks.where((r) => r.category == 'Radio' || r.category == 'Anti-tracking').fold<int>(0, (sum, r) => sum + r.severity.penalty));
    scan.permissionsScore = _bounded(100 - risks.where((r) => r.category == 'Permissions').fold<int>(0, (sum, r) => sum + r.severity.penalty));
    scan.privacyScore = _bounded(100 - risks.where((r) => r.category == 'Vie privée').fold<int>(0, (sum, r) => sum + r.severity.penalty));
    scan.behaviorScore = _bounded((checklistRatio * 100).round());

    scan.score = _bounded(((scan.systemScore * 0.25) +
            (scan.networkScore * 0.15) +
            (scan.radioScore * 0.15) +
            (scan.permissionsScore * 0.15) +
            (scan.privacyScore * 0.10) +
            (scan.behaviorScore * 0.20))
        .round());
    return scan;
  }

  static int _bounded(int value) => value.clamp(0, 100).toInt();

  static final _criticalChecklistLabels = <String>{
    'Verrouillage écran fort vérifié',
    'Sources inconnues contrôlées',
    'Débogage USB désactivé',
    'Play Protect vérifié',
    'Permissions localisation vérifiées',
    'Accessibilité apps contrôlée',
    'Superposition écran contrôlée',
  };

  static String? _settingsActionFor(String label) {
    if (label.contains('Sources inconnues')) return 'android.settings.MANAGE_UNKNOWN_APP_SOURCES';
    if (label.contains('Débogage') || label.contains('Options développeur')) return 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS';
    if (label.contains('Play Protect')) return 'android.settings.SECURITY_SETTINGS';
    if (label.contains('Permissions')) return 'android.settings.PRIVACY_SETTINGS';
    if (label.contains('Accessibilité')) return 'android.settings.ACCESSIBILITY_SETTINGS';
    if (label.contains('Superposition')) return 'android.settings.MANAGE_OVERLAY_PERMISSION';
    if (label.contains('Verrouillage')) return 'android.settings.SECURITY_SETTINGS';
    return null;
  }

  static List<RiskItem> _detectSuspiciousWifi(List<Map<String, dynamic>> wifi) {
    final risks = <RiskItem>[];
    final ssids = wifi.map((ap) => (ap['ssid'] ?? '').toString()).where((s) => s.trim().isNotEmpty).toList();
    for (final ssid in ssids) {
      for (final other in ssids) {
        if (ssid == other) continue;
        final normalizedA = ssid.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        final normalizedB = other.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (normalizedA.length >= 5 && normalizedB.length >= 5 && normalizedA != normalizedB) {
          final distance = _levenshtein(normalizedA, normalizedB);
          if (distance <= 2) {
            risks.add(RiskItem(
              title: 'SSID ressemblant détecté',
              description: 'Deux réseaux proches existent autour de toi : “$ssid” et “$other”. Cela peut être normal ou indiquer un faux point d’accès.',
              recommendation: 'Vérifie le BSSID autorisé de ton réseau avant de t’y connecter.',
              severity: Severity.medium,
              category: 'Wi-Fi',
            ));
            return risks;
          }
        }
      }
    }
    return risks;
  }

  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;
    final v0 = List<int>.generate(t.length + 1, (i) => i);
    final v1 = List<int>.filled(t.length + 1, 0);
    for (var i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (var j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost].reduce((a, b) => a < b ? a : b);
      }
      for (var j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }
}

class DiagnosticService {
  Future<ScanState> runScan({required bool scanBluetooth, required bool scanWifi}) async {
    final state = ScanState();
    state.lastScan = DateTime.now();
    state.device = await _deviceInfo();
    state.network = await _networkInfo();
    state.network['bluetoothState'] = await _bluetoothState();

    if (scanBluetooth) {
      state.bleDevices = await _scanBle();
    }
    if (scanWifi) {
      state.wifiNetworks = await _scanWifi();
    }
    return state;
  }

  Future<Map<String, dynamic>> _deviceInfo() async {
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return {
        'manufacturer': info.manufacturer,
        'model': info.model,
        'brand': info.brand,
        'androidVersion': info.version.release,
        'sdkInt': info.version.sdkInt,
        'securityPatch': info.version.securityPatch,
        'isPhysicalDevice': info.isPhysicalDevice,
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> _networkInfo() async {
    final result = <String, dynamic>{};
    try {
      final connectivity = await Connectivity().checkConnectivity();
      result['connectionType'] = connectivity.map((e) => e.name).join(', ');
    } catch (e) {
      result['connectionType'] = 'inconnu';
    }

    final info = NetworkInfo();
    try {
      result['wifiName'] = await info.getWifiName();
      result['wifiBSSID'] = await info.getWifiBSSID();
      result['wifiIP'] = await info.getWifiIP();
      result['wifiIPv6'] = await info.getWifiIPv6();
      result['wifiGatewayIP'] = await info.getWifiGatewayIP();
      result['wifiBroadcast'] = await info.getWifiBroadcast();
      result['wifiSubmask'] = await info.getWifiSubmask();
    } catch (e) {
      result['networkInfoError'] = e.toString();
    }
    return result;
  }

  Future<String> _bluetoothState() async {
    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(const Duration(seconds: 2));
      if (state == BluetoothAdapterState.on) return 'on';
      return state.name;
    } catch (_) {
      return 'unknown';
    }
  }

  Future<List<Map<String, dynamic>>> _scanBle() async {
    final devices = <Map<String, dynamic>>[];
    try {
      await Permission.bluetoothScan.request();
      await Permission.bluetoothConnect.request();
      await Permission.locationWhenInUse.request();

      final adapter = await FlutterBluePlus.adapterState.first.timeout(const Duration(seconds: 3));
      if (adapter != BluetoothAdapterState.on) return devices;

      final subscription = FlutterBluePlus.scanResults.listen((results) {
        devices
          ..clear()
          ..addAll(results.take(50).map((r) {
            final name = r.device.platformName.isNotEmpty ? r.device.platformName : 'Sans nom';
            return {
              'name': name,
              'id': r.device.remoteId.str,
              'rssi': r.rssi,
              'advertisementName': r.advertisementData.advName,
              'connectable': r.advertisementData.connectable,
              'serviceUuids': r.advertisementData.serviceUuids.map((e) => e.toString()).toList(),
            };
          }));
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await Future<void>.delayed(const Duration(seconds: 9));
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    } catch (e) {
      devices.add({'error': e.toString()});
    }
    return devices;
  }

  Future<List<Map<String, dynamic>>> _scanWifi() async {
    try {
      await Permission.locationWhenInUse.request();
      final canStart = await WiFiScan.instance.canStartScan(askPermissions: true);
      if (canStart == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      final canGet = await WiFiScan.instance.canGetScannedResults(askPermissions: true);
      if (canGet != CanGetScannedResults.yes) {
        return [
          {'error': 'Scan Wi-Fi non autorisé par Android : $canGet'}
        ];
      }
      final results = await WiFiScan.instance.getScannedResults();
      return results.take(80).map((ap) {
        return {
          'ssid': ap.ssid,
          'bssid': ap.bssid,
          'level': ap.level,
          'frequency': ap.frequency,
          'security': ap.capabilities,
        };
      }).toList();
    } catch (e) {
      return [
        {'error': e.toString()}
      ];
    }
  }
}

class SettingsLauncher {
  static Future<void> open(String action) async {
    if (!Platform.isAndroid) return;
    try {
      await AndroidIntent(action: action).launch();
    } catch (_) {
      await openAppSettings();
    }
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final store = SecurityStore();
  final engine = SecurityEngine();
  final diagnostic = DiagnosticService();

  ScanState scan = ScanState();
  Map<String, bool> checklist = {};
  bool loading = true;
  int index = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    checklist = await store.loadChecklist();
    scan = engine.compute(scan: scan, checklist: checklist);
    if (mounted) setState(() => loading = false);
  }

  Future<void> _runFullScan() async {
    setState(() => loading = true);
    final rawScan = await diagnostic.runScan(scanBluetooth: true, scanWifi: true);
    final computed = engine.compute(scan: rawScan, checklist: checklist);
    await store.saveScan(computed);
    if (mounted) {
      setState(() {
        scan = computed;
        loading = false;
        index = 0;
      });
    }
  }

  Future<void> _toggleChecklist(String key, bool value) async {
    setState(() => checklist[key] = value);
    await store.saveChecklist(checklist);
    setState(() => scan = engine.compute(scan: scan, checklist: checklist));
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(scan: scan, loading: loading, onScan: _runFullScan),
      RisksScreen(risks: scan.risks),
      HardeningScreen(checklist: checklist, onChanged: _toggleChecklist),
      RadioScreen(scan: scan),
      TravelScreen(checklist: checklist, onChanged: _toggleChecklist),
      ReportScreen(scan: scan, store: store),
    ];

    return Scaffold(
      body: SafeArea(child: loading && scan.lastScan == null ? const LoadingScreen() : screens[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shield), label: 'Score'),
          NavigationDestination(icon: Icon(Icons.warning_amber), label: 'Risques'),
          NavigationDestination(icon: Icon(Icons.lock), label: 'Sécuriser'),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Radio'),
          NavigationDestination(icon: Icon(Icons.flight_takeoff), label: 'Voyage'),
          NavigationDestination(icon: Icon(Icons.description), label: 'Rapport'),
        ],
      ),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Initialisation PrivateShield Ultimate...'),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.scan, required this.loading, required this.onScan});

  final ScanState scan;
  final bool loading;
  final Future<void> Function() onScan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('PrivateShield Ultimate', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Diagnostic sécurité, vie privée et durcissement Android', style: TextStyle(color: Colors.grey.shade300)),
        const SizedBox(height: 16),
        ScoreCard(score: scan.score),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: loading ? null : onScan,
          icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
          label: Text(loading ? 'Scan en cours...' : 'Lancer le scan Ultimate'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            MiniScore(label: 'Système', score: scan.systemScore),
            MiniScore(label: 'Réseau', score: scan.networkScore),
            MiniScore(label: 'Radio', score: scan.radioScore),
            MiniScore(label: 'Permissions', score: scan.permissionsScore),
            MiniScore(label: 'Vie privée', score: scan.privacyScore),
            MiniScore(label: 'Comportement', score: scan.behaviorScore),
          ],
        ),
        const SizedBox(height: 16),
        SectionTitle('Priorités'),
        ...scan.risks.take(5).map((risk) => RiskCard(risk: risk)),
        if (scan.risks.isEmpty)
          const InfoCard(title: 'Aucun risque calculé', body: 'Lance un scan et complète la checklist pour obtenir une analyse précise.'),
        const SizedBox(height: 16),
        SectionTitle('État rapide'),
        InfoGrid(data: {
          'Dernier scan': scan.lastScan == null ? 'Jamais' : DateFormat('dd/MM/yyyy HH:mm').format(scan.lastScan!),
          'Connexion': scan.network['connectionType']?.toString() ?? 'inconnue',
          'IP locale': scan.network['wifiIP']?.toString() ?? 'inconnue',
          'Bluetooth': scan.network['bluetoothState']?.toString() ?? 'inconnu',
          'Wi-Fi visibles': scan.wifiNetworks.length.toString(),
          'BLE visibles': scan.bleDevices.length.toString(),
        }),
      ],
    );
  }
}

class RisksScreen extends StatelessWidget {
  const RisksScreen({super.key, required this.risks});
  final List<RiskItem> risks;

  @override
  Widget build(BuildContext context) {
    final sorted = [...risks]..sort((a, b) => b.severity.penalty.compareTo(a.severity.penalty));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Risques détectés', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Les risques sont classés par priorité de correction.', style: TextStyle(color: Colors.grey.shade300)),
        const SizedBox(height: 16),
        if (sorted.isEmpty) const InfoCard(title: 'Aucun risque affiché', body: 'Lance un scan ou complète la checklist pour générer des recommandations.'),
        ...sorted.map((risk) => RiskCard(risk: risk, showAction: true)),
      ],
    );
  }
}

class HardeningScreen extends StatelessWidget {
  const HardeningScreen({super.key, required this.checklist, required this.onChanged});
  final Map<String, bool> checklist;
  final Future<void> Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Sécuriser maintenant', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Checklist de durcissement. Ouvre les réglages, vérifie, puis coche uniquement ce que tu as validé.', style: TextStyle(color: Colors.grey.shade300)),
        const SizedBox(height: 16),
        SettingsButtons(),
        const SizedBox(height: 16),
        ...checklist.entries.map((entry) {
          return Card(
            child: CheckboxListTile(
              value: entry.value,
              onChanged: (value) => onChanged(entry.key, value ?? false),
              title: Text(entry.key),
              subtitle: Text(_hintForChecklist(entry.key), style: TextStyle(color: Colors.grey.shade400)),
            ),
          );
        }),
      ],
    );
  }

  String _hintForChecklist(String label) {
    if (label.contains('Sources inconnues')) return 'Vérifie quelles apps peuvent installer des APK.';
    if (label.contains('Accessibilité')) return 'Contrôle les apps capables de lire ou contrôler l’écran.';
    if (label.contains('Superposition')) return 'Contrôle les apps capables de s’afficher par-dessus les autres.';
    if (label.contains('localisation')) return 'Réduis la localisation permanente aux apps indispensables.';
    if (label.contains('Bluetooth')) return 'Désactive-le si aucun accessoire n’est utilisé.';
    if (label.contains('VPN')) return 'Prépare un VPN fiable avant Wi-Fi public.';
    return 'Contrôle ce réglage dans Android.';
  }
}

class RadioScreen extends StatelessWidget {
  const RadioScreen({super.key, required this.scan});
  final ScanState scan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Radio & exposition', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Wi-Fi et Bluetooth visibles par le téléphone selon les permissions Android accordées.', style: TextStyle(color: Colors.grey.shade300)),
        const SizedBox(height: 16),
        SectionTitle('Réseau local'),
        InfoGrid(data: scan.network.map((key, value) => MapEntry(key, value?.toString() ?? 'null'))),
        const SizedBox(height: 16),
        SectionTitle('Wi-Fi visibles'),
        if (scan.wifiNetworks.isEmpty) const InfoCard(title: 'Aucun scan Wi-Fi', body: 'Lance un scan Ultimate depuis l’accueil.'),
        ...scan.wifiNetworks.take(50).map((ap) => InfoCard(
              title: ap['ssid']?.toString().isNotEmpty == true ? ap['ssid'].toString() : 'SSID masqué / inconnu',
              body: 'BSSID: ${ap['bssid'] ?? '-'}\nSignal: ${ap['level'] ?? '-'} dBm\nFréquence: ${ap['frequency'] ?? '-'} MHz\nSécurité: ${ap['security'] ?? '-'}',
            )),
        const SizedBox(height: 16),
        SectionTitle('Bluetooth BLE visibles'),
        if (scan.bleDevices.isEmpty) const InfoCard(title: 'Aucun scan BLE', body: 'Active Bluetooth, accorde les permissions, puis relance le scan.'),
        ...scan.bleDevices.take(50).map((d) => InfoCard(
              title: d['name']?.toString() ?? 'Appareil BLE',
              body: 'ID: ${d['id'] ?? '-'}\nRSSI: ${d['rssi'] ?? '-'}\nConnectable: ${d['connectable'] ?? '-'}',
            )),
      ],
    );
  }
}

class TravelScreen extends StatelessWidget {
  const TravelScreen({super.key, required this.checklist, required this.onChanged});
  final Map<String, bool> checklist;
  final Future<void> Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final items = [
      'Mises à jour Android vérifiées',
      'Apps inutilisées supprimées',
      'Sources inconnues contrôlées',
      'Verrouillage écran fort vérifié',
      'Notifications sensibles masquées',
      'Bluetooth désactivé si inutile',
      'NFC désactivé si inutile',
      'VPN prévu pour Wi-Fi public',
      'Permissions localisation vérifiées',
      'Partage position contrôlé',
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Mode voyage sécurisé', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Profil conseillé avant hôtel, aéroport, salon, déplacement professionnel ou intervention client.', style: TextStyle(color: Colors.grey.shade300)),
        const SizedBox(height: 16),
        const InfoCard(
          title: 'Objectif',
          body: 'Réduire l’exposition radio, réseau, applicative et visuelle pendant les déplacements.',
        ),
        const SizedBox(height: 16),
        ...items.map((key) => Card(
              child: CheckboxListTile(
                value: checklist[key] ?? false,
                onChanged: (value) => onChanged(key, value ?? false),
                title: Text(key),
              ),
            )),
      ],
    );
  }
}

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.scan, required this.store});
  final ScanState scan;
  final SecurityStore store;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  List<Map<String, dynamic>> history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    history = await widget.store.loadHistory();
    if (mounted) setState(() {});
  }

  Future<void> _exportJson() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/privateshield_report_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(widget.scan.toJson()));
    await Share.shareXFiles([XFile(file.path)], text: 'Rapport PrivateShield Ultimate');
  }

  @override
  Widget build(BuildContext context) {
    final pretty = const JsonEncoder.withIndent('  ').convert(widget.scan.toJson());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Rapport local', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text('Rapport JSON local. Aucune donnée n’est envoyée vers un serveur.', style: TextStyle(color: Colors.grey.shade300)),
        const SizedBox(height: 16),
        ElevatedButton.icon(onPressed: _exportJson, icon: const Icon(Icons.ios_share), label: const Text('Exporter / partager JSON')),
        const SizedBox(height: 16),
        SectionTitle('Historique'),
        if (history.isEmpty) const InfoCard(title: 'Aucun historique', body: 'Lance un scan pour créer un premier rapport.'),
        ...history.take(5).map((h) => InfoCard(
              title: 'Score ${h['score'] ?? '-'} / 100',
              body: 'Date: ${h['generatedAt'] ?? '-'}\nRisques: ${(h['risks'] as List?)?.length ?? 0}',
            )),
        const SizedBox(height: 16),
        SectionTitle('Aperçu JSON'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(pretty, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ),
      ],
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({super.key, required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final color = score >= 85
        ? Colors.greenAccent
        : score >= 70
            ? Colors.lightGreenAccent
            : score >= 50
                ? Colors.orangeAccent
                : Colors.redAccent;
    final label = score >= 90
        ? 'Excellent'
        : score >= 75
            ? 'Bon'
            : score >= 60
                ? 'Moyen'
                : score >= 40
                    ? 'Risqué'
                    : 'Critique';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(value: score / 100, strokeWidth: 10, color: color, backgroundColor: Colors.white12),
                  Center(child: Text('$score', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score sécurité', style: TextStyle(color: Colors.grey.shade300)),
                  Text(label, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 8),
                  const Text('Score calculé depuis les risques détectés, le réseau, la radio et la checklist de durcissement.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniScore extends StatelessWidget {
  const MiniScore({super.key, required this.label, required this.score});
  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 155,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: Colors.grey.shade300)),
              const SizedBox(height: 8),
              Text('$score / 100', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
            ],
          ),
        ),
      ),
    );
  }
}

class RiskCard extends StatelessWidget {
  const RiskCard({super.key, required this.risk, this.showAction = false});
  final RiskItem risk;
  final bool showAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: risk.severity.color.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
                  child: Text(risk.severity.label, style: TextStyle(color: risk.severity.color, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text(risk.category, style: TextStyle(color: Colors.grey.shade400)),
              ],
            ),
            const SizedBox(height: 10),
            Text(risk.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 6),
            Text(risk.description),
            const SizedBox(height: 8),
            Text('Action : ${risk.recommendation}', style: TextStyle(color: Colors.grey.shade200)),
            if (showAction && risk.settingsAction != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => SettingsLauncher.open(risk.settingsAction!),
                icon: const Icon(Icons.settings),
                label: const Text('Ouvrir le réglage Android'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key, required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 6),
          Text(body),
        ]),
      ),
    );
  }
}

class InfoGrid extends StatelessWidget {
  const InfoGrid({super.key, required this.data});
  final Map<String, String> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const InfoCard(title: 'Aucune donnée', body: 'Lance un scan pour obtenir les informations.');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: data.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: Text(entry.key, style: TextStyle(color: Colors.grey.shade400))),
                  Expanded(flex: 3, child: SelectableText(entry.value)),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class SettingsButtons extends StatelessWidget {
  SettingsButtons({super.key});

  final buttons = const [
    ('Sécurité', 'android.settings.SECURITY_SETTINGS'),
    ('Confidentialité', 'android.settings.PRIVACY_SETTINGS'),
    ('Applications', 'android.settings.APPLICATION_SETTINGS'),
    ('Sources inconnues', 'android.settings.MANAGE_UNKNOWN_APP_SOURCES'),
    ('Accessibilité', 'android.settings.ACCESSIBILITY_SETTINGS'),
    ('Superposition', 'android.settings.MANAGE_OVERLAY_PERMISSION'),
    ('Bluetooth', 'android.settings.BLUETOOTH_SETTINGS'),
    ('Wi-Fi', 'android.settings.WIFI_SETTINGS'),
    ('Développeur', 'android.settings.APPLICATION_DEVELOPMENT_SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: buttons
          .map((b) => OutlinedButton.icon(
                onPressed: () => SettingsLauncher.open(b.$2),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(b.$1),
              ))
          .toList(),
    );
  }
}

class SectionTitle extends StatelessWidget {
  SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
    );
  }
}
