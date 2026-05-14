import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebViewPaymentScreen extends StatefulWidget {

  const WebViewPaymentScreen({super.key});

  @override
  State<WebViewPaymentScreen> createState() => _WebViewPaymentScreenState();
}

class _WebViewPaymentScreenState extends State<WebViewPaymentScreen> {
  late WebViewController controller;
  bool _showLoading = false;



  // Fallback: poll every 200 ms checking URL and body content

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..addJavaScriptChannel(
        'PaymentCallback',
        onMessageReceived: (JavaScriptMessage message) {
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onHttpError: (HttpResponseError error) {},
          onWebResourceError: (WebResourceError error) {},
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse('https://cirgm.com/'));
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 20),
            child: WebViewWidget(controller: controller),
          ),
          if (_showLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: CircularProgressIndicator(color: Colors.yellow),
              ),
            ),
        ],
      ))
    );
  }
}