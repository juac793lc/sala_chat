import 'dart:convert';
import 'dart:js_util' as js_util;
import 'dart:html' as html;
import 'package:http/http.dart' as http;

class PushService {
  final String baseUrl;
  PushService(this.baseUrl);

  Future<String?> getVapidPublicKey() async {
    try {
      final resp = await http.get(Uri.parse('$baseUrl/api/push/vapidPublicKey'));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        return body['publicKey'];
      }
    } catch (e) {
      print('❌ Error fetching VAPID key: $e');
    }
    return null;
  }

  Future<bool> registerServiceWorkerAndSubscribe(String? vapidPublicKey, String? userId) async {
    if (vapidPublicKey == null) return false;
    try {
      // Llamar al helper JS que registra el service worker y suscribe
      final jsFunc = js_util.getProperty(html.window, 'registerAndSubscribe');
      if (jsFunc == null) throw Exception('registerAndSubscribe no disponible en window. Asegúrate de incluir web/register_push.js en index.html');
      final jsSub = await js_util.promiseToFuture(js_util.callMethod(html.window, 'registerAndSubscribe', [vapidPublicKey]));
      if (jsSub == null) return false;

      // Convertir LegacyJavaScriptObject a Map serializable en Dart
      final endpoint = js_util.getProperty(jsSub, 'endpoint');
      final keys = js_util.getProperty(jsSub, 'keys');
      final p256dh = keys != null ? js_util.getProperty(keys, 'p256dh') : null;
      final auth = keys != null ? js_util.getProperty(keys, 'auth') : null;
      final subscription = {
        'endpoint': endpoint,
        'keys': {
          'p256dh': p256dh,
          'auth': auth,
        }
      };

      // Enviar subscription al backend
      final resp = await http.post(Uri.parse('$baseUrl/api/push/subscribe'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'subscription': subscription, 'userId': userId})
      );
      return resp.statusCode == 200;
    } catch (e) {
      print('❌ Error subscribing to push: $e');
      return false;
    }
  }

  String base64UrlNormalize(String input) {
    // Normalize base64url to standard base64
    var output = input.replaceAll('-', '+').replaceAll('_', '/');
    while (output.length % 4 != 0) output += '=';
    return output;
  }
}
