import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'firenet_bridge.dart';
import 'firenet_command.dart';

const orange = Color(0xFFFF792B);
const background = Color(0xFF0B0C0E);
const panel = Color(0xFF1B1C20);
const appVersion = '0.5.0';
void main() => runApp(const RikaControlApp());

class RikaControlApp extends StatelessWidget {
  const RikaControlApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'RIKA Control',
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(seedColor: orange, brightness: Brightness.dark)
          .copyWith(primary: orange, onPrimary: Colors.black, surface: panel),
      appBarTheme: const AppBarTheme(backgroundColor: background, surfaceTintColor: Colors.transparent),
    ),
    home: const RikaHome(),
  );
}

class RikaHome extends StatefulWidget {
  const RikaHome({super.key});
  @override
  State<RikaHome> createState() => _RikaHomeState();
}

class _RikaHomeState extends State<RikaHome> with WidgetsBindingObserver {
  late final FirenetBridge _bridge;
  FirenetClient? _client;
  StoveSnapshot? _state;
  CommandReceipt? _receipt;
  Timer? _poll;
  DateTime? _lastRead;
  DateTime? _lastAttempt;
  bool _foreground = true;
  bool _login = true;
  bool _busy = false;
  bool _waiting = false;
  bool _expired = false;
  bool _diagnostics = false;
  bool _edited = false;
  String? _selectedStove;
  String _info = 'Connecte-toi puis sélectionne ton poêle.';
  String _feedback = 'Aucune commande envoyée.';
  int _targetTenths = 220;
  double _power = 40;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bridge = FirenetBridge(onStoveSelected: (id) {
      if (mounted && _login) { setState(() { _selectedStove = id; }); }
    });
    _poll = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_foreground && !_login && !_busy) { _sync(); }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && !_login && !_busy) { _sync(); }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _bridge.dispose();
    super.dispose();
  }

  String _degrees(num? value) => value == null ? '—' : '${value.toStringAsFixed(1)} °C';
  double get _target => _targetTenths / 10;
  String _modeName(int mode) => ['Manuel', 'Automatique', 'Confort'][mode];

  void _acceptState(StoveSnapshot state) {
    _state = state;
    if (!_edited && state.target != null) {
      _targetTenths = (state.target! * 10).round().clamp(140, 280).toInt();
    }
  }

  Future<void> _finishLogin() async {
    if (_busy) { return; }
    setState(() { _busy = true; _info = 'Vérification de la session…'; });
    try {
      final id = await _bridge.discoverStove() ?? _selectedStove;
      if (id == null) {
        throw const FirenetException('Dans le site ci-dessous, ouvre ton poêle puis appuie sur Terminer.');
      }
      final client = FirenetClient(_bridge.request, id);
      final state = await client.read();
      if (!mounted) { return; }
      setState(() {
        _client = client;
        _selectedStove = id;
        _edited = false;
        _acceptState(state);
        _power = (number(state.controls['heatingPower'])?.toDouble() ?? 40).clamp(30, 100).toDouble();
        _lastRead = DateTime.now();
        _receipt = null;
        _waiting = false;
        _expired = false;
        _feedback = 'Session active. Aucune commande envoyée par cette version.';
        _login = false;
        _info = 'Lecture FIRENET réussie';
      });
    } catch (error) {
      if (mounted) { setState(() { _info = error.toString(); }); }
    } finally {
      if (mounted) { setState(() { _busy = false; }); }
    }
  }

  void _checkReceipt(StoveSnapshot state) {
    final receipt = _receipt;
    if (receipt == null || _expired) { return; }
    final result = receipt.inspect(state);
    final targetReport = receipt.patch.containsKey('targetTemperature')
        ? ' Demandée : ${receipt.patch['targetTemperature']} °C ; retour : ${_degrees(state.target)}.' : '';
    switch (result) {
      case Confirmation.confirmed:
        _waiting = false;
        _feedback = 'Valeurs relues identiques et révision acquittée par le poêle.$targetReport';
      case Confirmation.unchanged:
        _waiting = false;
        _feedback = 'Le réglage était déjà appliqué. Aucun POST envoyé.$targetReport';
      case Confirmation.different:
        _waiting = false;
        _feedback = 'Révision acquittée, mais retour différent de la demande.$targetReport Vérifie l’écran du poêle.';
      case Confirmation.stored:
        _feedback = 'Valeur visible sur FIRENET ; acquittement du poêle en attente.$targetReport';
      case Confirmation.waiting:
        _feedback = 'Commande envoyée ; application par le poêle non confirmée.$targetReport';
    }
    if (_waiting && DateTime.now().difference(receipt.sentAt) >= const Duration(minutes: 5)) {
      _waiting = false;
      _expired = true;
      _feedback = 'Délai de confirmation dépassé. Aucun renvoi automatique.$targetReport Vérifie le poêle.';
    }
  }

  Future<void> _sync({bool manual = false}) async {
    if (_busy || _login || _client == null) { return; }
    final elapsed = _lastRead == null ? 60 : DateTime.now().difference(_lastRead!).inSeconds;
    if (elapsed < 60) {
      if (manual) { setState(() { _info = 'Prochaine lecture dans ${60 - elapsed} s (limitation réseau).'; }); }
      return;
    }
    setState(() { _busy = true; _info = 'Lecture de FIRENET…'; });
    try {
      final state = await _client!.read();
      if (!mounted) { return; }
      setState(() {
        _acceptState(state);
        _lastRead = DateTime.now();
        _info = 'Lecture FIRENET réussie';
        _checkReceipt(state);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _info = error.toString();
          if (_receipt != null && DateTime.now().difference(_receipt!.sentAt) >= const Duration(minutes: 5)) {
            _waiting = false;
            _expired = true;
            _feedback = 'Confirmation indisponible. Aucun renvoi automatique. Vérifie le poêle.';
          }
        });
      }
    } finally {
      if (mounted) { setState(() { _busy = false; }); }
    }
  }

  Future<void> _send(Map<String, Object> patch, String title, String explanation) async {
    if (_busy || _login || _client == null) { return; }
    final stop = patch.length == 1 && patch['onOff'] == false;
    if (_waiting && !stop) {
      setState(() { _feedback = 'La commande précédente attend sa confirmation. L’arrêt normal reste disponible.'; });
      return;
    }
    final elapsed = _lastAttempt == null ? 60 : DateTime.now().difference(_lastAttempt!).inSeconds;
    final delay = stop ? 5 : 60;
    if (elapsed < delay) {
      setState(() { _feedback = 'Encore ${delay - elapsed} s avant une nouvelle commande. Aucun envoi effectué.'; });
      return;
    }
    setState(() { _busy = true; });
    try {
      final approved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text('$explanation\n\nCette action peut modifier réellement le chauffage. Vérifie que le poêle est prêt et sans alarme. Les sécurités du poêle restent actives.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
        ],
      ));
      if (approved != true || !mounted) { return; }
      setState(() {
        _lastAttempt = DateTime.now();
        _feedback = 'Lecture de la dernière révision, puis envoi unique…';
      });
      final receipt = await _client!.send(patch);
      if (!mounted) { return; }
      setState(() {
        _acceptState(receipt.before);
        _lastRead = DateTime.now();
        _receipt = receipt;
        _expired = false;
        _waiting = !receipt.noChange;
        _feedback = receipt.noChange
            ? 'Réglage déjà appliqué. Aucune commande envoyée.'
            : '${receipt.accepted ? 'FIRENET a répondu OK' : 'Réponse HTTP reçue, contenu non confirmé'}. '
              'Vérification à la prochaine lecture (60 s). Ce n’est pas encore un acquittement du poêle.';
      });
    } catch (error) {
      if (mounted) { setState(() { _feedback = error.toString(); }); }
    } finally {
      if (mounted) { setState(() { _busy = false; }); }
    }
  }

  Future<void> _sendTarget() async {
    final switchMode = _state?.mode != 2;
    await _send(FirenetCommand.temperature(_target, comfort: switchMode),
      'Envoyer ${_degrees(_target)} ?',
      '${switchMode ? 'Passer en mode Confort et envoyer' : 'Envoyer'} la consigne exacte ${_target.toStringAsFixed(1)} °C, sans arrondi dans l’application. '
      'Le poêle peut la refuser ou la convertir. Cette commande ne change pas marche/arrêt.');
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(22)),
    child: child,
  );
  Widget _stat(String name, String value, IconData icon) => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [Icon(icon, color: orange), const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4), Text(name, style: const TextStyle(color: Colors.white60, fontSize: 12))],
  ));

  Widget _dashboard() {
    final state = _state;
    final controls = state?.controls ?? <String, dynamic>{};
    final seen = state?.lastSeen;
    final old = state == null || DateTime.now().difference(state.receivedAt).inMinutes > 2;
    final online = !old && seen != null && seen <= 2;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text(state?.raw['stoveType']?.toString() ?? 'Poêle RIKA',
        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
      const Text('v$appVersion · PILOTAGE FIRENET', style: TextStyle(color: orange, fontSize: 12)),
      const SizedBox(height: 10),
      Text(_info, style: const TextStyle(color: Colors.white70)),
      Text(online ? 'Dernier contact poêle : $seen min' : 'État ancien ou poêle hors ligne — lecture à vérifier',
        style: TextStyle(color: online ? Colors.greenAccent : orange, fontSize: 12)),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
      const SizedBox(height: 24),
      Center(child: Container(width: 260, height: 260,
        decoration: BoxDecoration(shape: BoxShape.circle, color: panel,
          border: Border.all(color: orange, width: 8)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('CONSIGNE À ENVOYER', style: TextStyle(fontSize: 12, color: Colors.white60)),
          Text('${_target.toStringAsFixed(1)}°', style: const TextStyle(fontSize: 58, fontWeight: FontWeight.bold)),
          Text('Pièce : ${_degrees(state?.room)}', style: const TextStyle(fontSize: 20, color: orange)),
          const SizedBox(height: 4),
          Text('Retour FIRENET : ${_degrees(state?.target)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]))),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton.filledTonal(tooltip: 'Moins 0,1 °C', onPressed: _busy ? null : () => setState(() {
          _edited = true; _targetTenths = (_targetTenths - 1).clamp(140, 280).toInt();
        }), icon: const Icon(Icons.remove)),
        const SizedBox(width: 25), Text(_degrees(_target), style: const TextStyle(fontSize: 25)),
        const SizedBox(width: 25),
        IconButton.filled(tooltip: 'Plus 0,1 °C', onPressed: _busy ? null : () => setState(() {
          _edited = true; _targetTenths = (_targetTenths + 1).clamp(140, 280).toInt();
        }), icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: 10),
      FilledButton.icon(onPressed: _busy ? null : _sendTarget, icon: const Icon(Icons.send),
        label: Text(state?.mode == 2 ? 'Envoyer ${_degrees(_target)}' : 'Confort + envoyer ${_degrees(_target)}')),
      const Text('Le passage à Confort est proposé dans la confirmation si nécessaire.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.white60)),
      const SizedBox(height: 18),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Retour de commande', style: TextStyle(fontWeight: FontWeight.bold, color: orange)),
        const SizedBox(height: 8), Text(_feedback),
        if (_receipt != null) Text('Demandé : ${jsonEncode(_receipt!.patch)}',
          style: const TextStyle(color: Colors.white60, fontSize: 11)),
        Text('Révision : ${state?.revision ?? '—'} / acquittée : ${state?.acknowledged ?? '—'}',
          style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ])),
      const SizedBox(height: 20),
      const Text('Marche / arrêt', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      Text('État mesuré : ${state?.physicalState ?? 'Inconnu'} · Demande : ${state?.requestedOn == null ? 'inconnue' : state!.requestedOn! ? 'ON' : 'OFF'}',
        style: const TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: FilledButton.icon(onPressed: _busy ? null : () => _send({'onOff': true},
          'Allumer le poêle ?', 'Demander la marche avec le mode et la consigne actuellement enregistrés sur FIRENET. La consigne préparée n’est pas envoyée par ce bouton.'),
          icon: const Icon(Icons.power_settings_new), label: const Text('Allumer'))),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(onPressed: _busy ? null : () => _send({'onOff': false},
          'Demander l’arrêt ?', 'Demander l’arrêt normal du poêle. Le refroidissement peut continuer. Ne pas couper son alimentation.'),
          icon: const Icon(Icons.stop_circle_outlined), label: const Text('Arrêter'))),
      ]),
      const SizedBox(height: 20),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Mode actuel : ${state?.modeName ?? 'Inconnu'}', style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < 3; i++)
          ChoiceChip(label: Text(_modeName(i)), selected: state?.mode == i,
            onSelected: _busy ? null : (_) => _send({'operatingMode': i},
              'Passer en ${_modeName(i)} ?', i == 1
                ? 'Le mode Automatique suit les plages horaires enregistrées. Il ne correspond pas à une régulation par température.'
                : 'Changer uniquement le mode. Marche/arrêt et la consigne restent inchangés.')),
        ]),
      ])),
      const SizedBox(height: 18),
      LayoutBuilder(builder: (context, size) => Wrap(spacing: 12, runSpacing: 12, children: [
        SizedBox(width: (size.maxWidth - 12) / 2,
          child: _stat('Température ambiante mesurée', _degrees(state?.room), Icons.thermostat)),
        SizedBox(width: (size.maxWidth - 12) / 2,
          child: _stat('Puissance demandée', '${controls['heatingPower'] ?? '—'} %', Icons.local_fire_department)),
      ])),
      const SizedBox(height: 18),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Puissance préparée : ${_power.round()} %', style: const TextStyle(fontWeight: FontWeight.bold)),
        Slider(value: _power, min: 30, max: 100, divisions: 70, label: '${_power.round()} %',
          onChanged: _busy ? null : (v) => setState(() { _power = v; })),
        OutlinedButton(onPressed: _busy ? null : () => _send({'heatingPower': _power.round()},
          'Envoyer ${_power.round()} % ?', 'Modifier uniquement la puissance demandée. Le mode Confort peut réguler la chauffe lui-même.'),
          child: const Text('Envoyer la puissance')),
      ])),
      const SizedBox(height: 20),
      const Text('MultiAir', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      for (final i in [1, 2]) if (state?.features['multiAir$i'] == true)
        Card(color: panel, child: SwitchListTile(
          title: Text('MultiAir $i'),
          subtitle: Text('Activation demandée · Niveau ${controls['convectionFan${i}Level'] ?? '—'}'),
          value: controls['convectionFan${i}Active'] == true,
          onChanged: _busy ? null : (enabled) => _send({'convectionFan${i}Active': enabled},
            '${enabled ? 'Activer' : 'Désactiver'} MultiAir $i ?', 'Modifier l’activation demandée du circuit $i. Son fonctionnement effectif dépend de l’état du poêle.'),
        )),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: () => setState(() { _diagnostics = !_diagnostics; }),
        icon: const Icon(Icons.bug_report_outlined), label: Text(_diagnostics ? 'Masquer le diagnostic' : 'Diagnostic')),
      if (_diagnostics) SelectableText(const JsonEncoder.withIndent('  ').convert(state?.raw),
        style: const TextStyle(fontSize: 11, color: Colors.white60)),
      const SizedBox(height: 12),
      const Text('Les dixièmes sont envoyés sans arrondi. Leur acceptation réelle dépend de FIRENET et du poêle. '
        'Une température affichée à 0,1 °C ne garantit pas une régulation aussi précise. '
        'Projet indépendant de RIKA. Aucun don ni paiement dans l’application.',
        style: TextStyle(fontSize: 11, color: Colors.white54)),
      const SizedBox(height: 18),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Row(children: [
      Icon(Icons.local_fire_department, color: orange), SizedBox(width: 8),
      Text('RIKA Control', style: TextStyle(fontWeight: FontWeight.bold)),
    ]), actions: [
      IconButton(tooltip: 'Compte FIRENET', onPressed: _busy ? null : () => setState(() {
        _login = true; _selectedStove = null;
      }), icon: const Icon(Icons.account_circle_outlined)),
      IconButton(tooltip: 'Actualiser', onPressed: _login || _busy ? null : () => _sync(manual: true),
        icon: const Icon(Icons.refresh)),
    ]),
    body: SafeArea(child: IndexedStack(index: _login ? 1 : 0, children: [
      _dashboard(),
      Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Text('v$appVersion — Connecte-toi au site officiel et ouvre ton poêle.\n$_info',
          style: const TextStyle(fontSize: 12))),
        Expanded(child: WebViewWidget(controller: _bridge.controller)),
        Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(
          onPressed: _busy ? null : _finishLogin, icon: const Icon(Icons.check),
          label: Text(_busy ? 'Vérification…' : 'Terminer et ouvrir le pilotage'),
        )),
      ]),
    ])),
  );
}
