import 'dart:convert';
import 'package:http/http.dart' as http;

class FCMService {
  static const String _serverKey = 'd83d5149d169823271275050a1eb2df0ab04c96c'; // ⚠️ Replace this with your Firebase server key

   static Future<void> sendNotification({
    required String title,
    required String body,
    required String token,
    Map<String, dynamic>? data,
  }) async {
    try {
      final url = Uri.parse('https://fcm.googleapis.com/fcm/send');
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'key=$_serverKey',
      };

      final payload = {
        'to': token,
        'notification': {
          'title': title,
          'body': body,
          'sound': 'default',
        },
        'data': data ?? {'click_action': 'FLUTTER_NOTIFICATION_CLICK'},
      };

      final response = await http.post(url, headers: headers, body: jsonEncode(payload));

      if (response.statusCode == 200) {
      } else {
      }
    } catch (e) {
    }
  }
}