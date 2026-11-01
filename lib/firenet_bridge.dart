import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:webview_flutter/webview_flutter.dart';
import 'firenet_command.dart';

/// The WebView keeps FIRENET cookies. Credentials never enter Dart or logs.
class FirenetBridge {
  FirenetBridge({required this.onStoveSelected}) {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('RikaBridgeV5', onMessageReceived: _receive)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) => trusted(request.url)
            ? NavigationDecision.navigate : NavigationDecision.prevent,
        onPageFinished: (url) {
          if (trusted(url)) {
            final match = RegExp(r'/web/stove/([0-9]+)').firstMatch(url);
            if (match != null) { onStoveSelected(match.group(1)!); }
          }
        },
      ))
      ..loadRequest(Uri.parse('https://www.rika-firenet.com/web/summary'));
  }
  final void Function(String) onStoveSelected;
  late final WebViewController controller;
  final Map<String, Completer<ApiReply>> _pending = {};
  final Random _random = Random.secure();

  static bool trusted(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' &&
        (uri.host == 'www.rika-firenet.com' || uri.host == 'rika-firenet.com');
  }
  void _receive(JavaScriptMessage message) {
    try {
      final value = objectMap(jsonDecode(message.message));
      final completer = _pending.remove(value['id']);
      if (completer == null || completer.isCompleted) { return; }
      if (value['error'] != null) {
        completer.completeError(const FirenetException(
          'Connexion interrompue ou délai dépassé. Envoi incertain : actualiser, ne pas renvoyer automatiquement.'));
      } else {
        completer.complete(ApiReply(number(value['status'])?.toInt() ?? 0, value['body']?.toString() ?? '', retryAfter: number(value['retryAfter'])?.toInt()));
      }
    } catch (_) { /* Invalid or unrelated messages do not complete an RPC. */ }
  }
  Future<String?> discoverStove() async {
    final url = await controller.currentUrl();
    if (url == null || !trusted(url)) { return null; }
    final result = await controller.runJavaScriptReturningResult(r'''
      JSON.stringify((() => {
        const here = location.pathname.match(/^\/web\/stove\/([0-9]+)/);
        if (here) return here[1];
        const ids = [...new Set([...document.querySelectorAll('a[href]')]
          .map(a => { const m = a.pathname.match(/^\/web\/stove\/([0-9]+)/); return m ? m[1] : null; })
          .filter(Boolean))];
        return ids.length === 1 ? ids[0] : null;
      })())
    ''');
    dynamic decoded = result;
    for (var i = 0; i < 2 && decoded is String; i++) {
      if (!decoded.startsWith('"')) { break; }
      try { decoded = jsonDecode(decoded); } catch (_) { break; }
    }
    final id = decoded?.toString();
    return id != null && RegExp(r'^[0-9]+$').hasMatch(id) ? id : null;
  }
  Future<ApiReply> request(String path, String method, Map<String, dynamic>? body) async {
    if (!RegExp(r'^/api/client/[0-9]+/(status|controls)(\?nocache=[0-9]+)?$').hasMatch(path) || !['GET', 'POST'].contains(method)) {
      throw const FirenetException('Requête non autorisée.');
    }
    final current = await controller.currentUrl();
    if (current == null || !trusted(current)) { throw const FirenetException('Ouvrir une session sur le site officiel FIRENET.'); }
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 30)}';
    final completion = Completer<ApiReply>();
    _pending[id] = completion;
    final future = completion.future.timeout(const Duration(seconds: 24), onTimeout: () {
      throw const FirenetException('Pas de réponse FIRENET. Résultat de l’envoi inconnu : actualiser avant tout nouvel essai.');
    });
    final config = jsonEncode({'id': id, 'path': path, 'method': method, 'body': body});
    try {
      unawaited(controller.runJavaScript('''
        (async () => {
          const cfg = $config;
          const abort = new AbortController();
          const timeout = setTimeout(() => abort.abort(), 18000);
          try {
            if (location.protocol !== 'https:' || !['www.rika-firenet.com','rika-firenet.com'].includes(location.hostname)) {
              throw new Error('Invalid origin');
            }
            const options = {method: cfg.method, credentials: 'same-origin',
              cache: 'no-store', signal: abort.signal, headers: {'Accept': 'application/json'}};
            if (cfg.method === 'POST') {
              options.headers['Content-Type'] = 'application/json';
              options.body = JSON.stringify(cfg.body);
            }
            const response = await fetch(cfg.path, options);
            const text = await response.text();
            RikaBridgeV5.postMessage(JSON.stringify({id: cfg.id, status: response.status, body: text, retryAfter: response.headers.get('Retry-After')}));
          } catch (_) {
            RikaBridgeV5.postMessage(JSON.stringify({id: cfg.id, error: 'network'}));
          } finally { clearTimeout(timeout); }
        })();
      ''').catchError((Object error) {
        final waiting = _pending.remove(id);
        if (waiting != null && !waiting.isCompleted) { waiting.completeError(error); }
      }));
      return await future;
    } finally { _pending.remove(id); }
  }
  void dispose() {
    for (final pending in _pending.values) {
      if (!pending.isCompleted) { pending.completeError(const FirenetException('Session fermée.')); }
    }
    _pending.clear();
  }
}
