import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() => runApp(const MaterialApp(
  debugShowCheckedModeBanner: false,
  themeMode: ThemeMode.dark,
  home: RikaHome(),
));
const orange = Color(0xFFFF792B);
const stoveId = '46342494';

class RikaHome extends StatefulWidget {
  const RikaHome({super.key});
  @override
  State<RikaHome> createState() => _RikaHomeState();
}

class _RikaHomeState extends State<RikaHome> {
  late final WebViewController web;
  Timer? timer;
  bool login = true;
  bool busy = false;
  String info = 'Connexion FIRENET requise';
  Map<String, dynamic>? data;
  double preview = 20.1;
  bool previewEdited = false;

  @override
  void initState() {
    super.initState();
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('RikaBridge', onMessageReceived: (event) {
        try {
          final result = jsonDecode(event.message);
          if (result is! Map || result['controls'] is! Map) {
            throw const FormatException('Réponse inattendue');
          }
          if (mounted) {
            setState(() {
            data = Map<String, dynamic>.from(result);
            busy = false;
            info = 'API FIRENET connectée';
            final t = result['controls']['targetTemperature'];
            final parsed = num.tryParse(t?.toString() ?? '');
            if (parsed != null && !previewEdited) { preview = parsed.toDouble(); }
          });
          }
        } catch (_) {
          if (mounted) {
            setState(() {
            busy = false;
            info = 'Lecture impossible : vérifier la session FIRENET';
          });
          }
        }
      })
      ..setNavigationDelegate(NavigationDelegate(onPageFinished: (_) {
        if (!login) { refresh(); }
      }))
      ..loadRequest(Uri.parse('https://www.rika-firenet.com/web/stove/$stoveId'));
    timer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!login && !busy) { refresh(); }
    });
  }

  Future<void> refresh() async {
    if (login || busy) { return; }
    setState(() { busy = true; info = 'Actualisation…'; });
    try {
      await web.runJavaScript(r'''
        (async function() {
          try {
            const r = await fetch('/api/client/46342494/status', {
              credentials: 'same-origin', headers: {'Accept':'application/json'}
            });
            if (!r.ok) throw new Error('HTTP ' + r.status);
            RikaBridge.postMessage(JSON.stringify(await r.json()));
          } catch(e) {
            RikaBridge.postMessage(JSON.stringify({error: String(e)}));
          }
        })();
      ''');
    } catch (_) {
      if (mounted) {
            setState(() {
        busy = false;
        info = 'Session non disponible : reconnecte-toi';
      });
      }
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Widget metric(String label, String value, IconData icon) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF202124),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: orange),
      const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final controls = data?['controls'] is Map
      ? data!['controls'] as Map : <String, dynamic>{};
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B0C0E),
        colorScheme: ColorScheme.fromSeed(seedColor: orange, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Row(children: [
            Icon(Icons.local_fire_department, color: orange),
            SizedBox(width: 8), Text('RIKA Control'),
          ]),
          actions: [
            IconButton(onPressed: () => setState(() => login = true),
              tooltip: 'Compte FIRENET', icon: const Icon(Icons.login)),
            IconButton(onPressed: login ? null : refresh,
              tooltip: 'Actualiser', icon: const Icon(Icons.refresh)),
          ],
        ),
        body: IndexedStack(index: login ? 1 : 0, children: [
          ListView(padding: const EdgeInsets.all(20), children: [
            const Text('DOMO MultiAir', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(info, style: const TextStyle(color: orange)),
            const SizedBox(height: 6),
            const Text('LECTURE SEULE — commandes non activées',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
            const SizedBox(height: 26),
            Center(child: Container(
              width: 240, height: 240,
              decoration: BoxDecoration(shape: BoxShape.circle,
                border: Border.all(color: orange, width: 9),
                color: const Color(0xFF202124)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('TEMPÉRATURE CIBLE'),
                Text('${preview.toStringAsFixed(1)}°',
                  style: const TextStyle(fontSize: 58, fontWeight: FontWeight.bold)),
                const Text('Consigne / aperçu local', style: TextStyle(color: orange)),
              ]),
            )),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton.filledTonal(onPressed: () => setState(() {
                previewEdited = true;
                preview = ((preview - 0.1) * 10).round().clamp(50, 350) / 10;
              }),
                icon: const Icon(Icons.remove)),
              const SizedBox(width: 28),
              Text('${preview.toStringAsFixed(1)} °C', style: const TextStyle(fontSize: 23)),
              const SizedBox(width: 28),
              IconButton.filled(onPressed: () => setState(() {
                previewEdited = true;
                preview = ((preview + 0.1) * 10).round().clamp(50, 350) / 10;
              }),
                icon: const Icon(Icons.add)),
            ]),
            const Center(child: Text('Boutons de démonstration : aucun envoi',
              style: TextStyle(color: Colors.white54, fontSize: 12))),
            const SizedBox(height: 24),
            GridView.count(crossAxisCount: 2, shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.4,
              children: [
                metric('Puissance demandée', '${controls['heatingPower'] ?? '—'} %', Icons.local_fire_department),
                metric('Mode (valeur API)', (controls['operatingMode'] ?? '—').toString(), Icons.tune),
                metric('Température poêle (°C)', (() { final raw = num.tryParse(controls['bakeTemperature']?.toString() ?? ''); return raw == null ? '—' : (raw / 10).toStringAsFixed(1); })(), Icons.thermostat),
                metric('API', data == null ? 'Non lue' : 'OK', Icons.wifi),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Diagnostic JSON FIRENET (développement)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SelectableText(data == null ? 'Aucune donnée reçue' :
              const JsonEncoder.withIndent('  ').convert(data),
              style: const TextStyle(fontSize: 11, color: Colors.white60)),
            const SizedBox(height: 20),
            const Text('La précision de commande à 0,1 °C reste à vérifier.',
              style: TextStyle(color: Colors.white60)),
          ]),
          Column(children: [
            const Padding(padding: EdgeInsets.all(12),
              child: Text('Connecte-toi sur FIRENET, puis appuie sur Terminer. Aucun mot de passe n’est stocké dans le code.')),
            Expanded(child: WebViewWidget(controller: web)),
            SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: () { setState(() => login = false); refresh(); },
                icon: const Icon(Icons.check),
                label: const Text('Terminer et lire les données'),
              ),
            )),
          ]),
        ]),
      ),
    );
  }
}
