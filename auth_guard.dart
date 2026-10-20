import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class AuthGuard {
  static bool _handling = false;
  static void Function()? onExpired;

  /// নতুন করে সফল লগইনের পর ডাকতে হবে
  static void reset() => _handling = false;

  static void expired() {
    if (_handling) return;
    _handling = true;
    onExpired?.call();
  }
}

/// টোকেনসহ যেকোনো অনুরোধে ৪০১ এলে লগইনে ফেরানোর ক্লায়েন্ট
class AuthClient extends http.BaseClient {
  final http.Client _inner;
  AuthClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    if (response.statusCode == 401 &&
        request.headers.containsKey('Authorization') &&
        !request.url.path.endsWith('/login')) {
      AuthGuard.expired();
    }
    return response;
  }
}