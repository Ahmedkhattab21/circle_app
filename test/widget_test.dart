import 'package:circle_app/payment_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('payment WebView URL is secure', () {
    final uri = Uri.parse(paymentWebViewUrl);

    expect(uri.scheme, 'https');
    expect(uri.host, 'cirgm.com');
  });
}
