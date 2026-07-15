import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

const paymentWebViewUrl = 'https://cirgm.com/';
const _iphoneSafariUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 '
    'Mobile/15E148 Safari/604.1 CIRGMApp/1';

class WebViewPaymentScreen extends StatefulWidget {
  const WebViewPaymentScreen({super.key});

  @override
  State<WebViewPaymentScreen> createState() =>
      _WebViewPaymentScreenState();
}

class _WebViewPaymentScreenState extends State<WebViewPaymentScreen> {
  late final WebViewController controller;

  var _isLoading = true;
  var _loadingProgress = 0;

  String? _errorMessage;

  Timer? _loadingTimer;
  Timer? _pageFixTimer;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(_iphoneSafariUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (!mounted) return;

            setState(() {
              _loadingProgress = progress;

              if (progress >= 90) {
                _isLoading = false;
              }
            });
          },
          onPageStarted: (_) {
            _startLoading();
          },
          onPageFinished: (_) {
            _stopLoading();
            _applyPageFixes();
          },
          onWebResourceError: (error) {
            if (!mounted || error.isForMainFrame == false) {
              return;
            }

            _loadingTimer?.cancel();

            setState(() {
              _isLoading = false;
              _errorMessage = error.description;
            });
          },
          onNavigationRequest: (_) {
            return NavigationDecision.navigate;
          },
        ),
      );

    _loadInitialPage();
  }

  Future<void> _loadInitialPage() async {
    await controller.clearCache();
    await controller.clearLocalStorage();

    await controller.loadRequest(
      Uri.parse(paymentWebViewUrl),
    );
  }

  void _startLoading() {
    _loadingTimer?.cancel();
    _pageFixTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _loadingProgress = 0;
      _errorMessage = null;
    });

    _pageFixTimer = Timer(
      const Duration(seconds: 4),
      _applyPageFixes,
    );

    _loadingTimer = Timer(
      const Duration(seconds: 6),
          () {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
        });
      },
    );
  }

  void _stopLoading() {
    _loadingTimer?.cancel();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
      _loadingProgress = 100;
    });
  }

  Future<void> _applyPageFixes() async {
    try {
      await controller.runJavaScript(r'''
        (function () {
          document.documentElement.style.background = '#fff';
          document.body.style.background = '#fff';
          document.body.style.opacity = '1';
          document.body.style.visibility = 'visible';

          document.body.classList.add(
            'loaded',
            'woodmart-loaded'
          );

          var style = document.getElementById(
            'circle-webview-fixes'
          );

          if (!style) {
            style = document.createElement('style');
            style.id = 'circle-webview-fixes';

            style.textContent = [
              'body, html { opacity: 1 !important; visibility: visible !important; background: #fff !important; }',
              '.website-wrapper, .wd-page-wrapper, .main-page-wrapper, .wd-page-content { opacity: 1 !important; visibility: visible !important; }',
              '.wd-preloader, .preloader, .page-preloader, .woodmart-preloader, .wd-loader-overlay, .wd-search-loader { display: none !important; opacity: 0 !important; visibility: hidden !important; pointer-events: none !important; }'
            ].join('\n');

            document.head.appendChild(style);
          }

          document.querySelectorAll(
            '.wd-preloader, .preloader, .page-preloader, .woodmart-preloader, .wd-loader-overlay, .wd-search-loader'
          ).forEach(function (el) {
            el.style.display = 'none';
            el.style.opacity = '0';
            el.style.visibility = 'hidden';
            el.setAttribute('aria-hidden', 'true');
          });
        })();
      ''');
    } catch (_) {
      // The document may not be ready yet.
      // The next page-load callback can retry.
    }
  }

  Future<void> _reload() async {
    _startLoading();
    await controller.reload();
  }

  Future<void> _handleBackPressed() async {
    if (await controller.canGoBack()) {
      await controller.goBack();
      return;
    }

    if (!mounted) return;

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  void dispose() {
    _loadingTimer?.cancel();
    _pageFixTimer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        _handleBackPressed();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(
                controller: controller,
              ),

              if (_isLoading)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _loadingProgress == 0
                        ? null
                        : _loadingProgress / 100,
                  ),
                ),

              if (_errorMessage != null)
                ColoredBox(
                  color: Colors.white,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Unable to load the page',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _reload,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}