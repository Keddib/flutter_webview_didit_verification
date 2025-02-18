import 'dart:convert'; // For JSON and Base64 encoding.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

class VerificationScreen extends StatefulWidget {
  const VerificationScreen({super.key});

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? sessionUrl;

  @override
  void initState() {
    super.initState();
    _createSessionAndLoad();
  }

  /// Authenticates with the Didit API and then creates a verification session.
  Future<void> _createSessionAndLoad() async {
    try {
      await _setupWebView();
      final String clientAccessToken = await getClientAccessToken();

      const String features = "OCR + FACE";
      const String callbackUrl = "https://example.com/verification/callback";
      const String vendorData = "your-vendor-data";

      final sessionData = await createSession(
        features: features,
        callback: callbackUrl,
        vendorData: vendorData,
        accessToken: clientAccessToken,
      );

      sessionUrl = sessionData["url"];

      if (sessionUrl != null) {
        _controller.loadRequest(Uri.parse(sessionUrl!));
      }
    } catch (error) {
      debugPrint("Error creating session: $error");
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Sets up the WebView controller with necessary platform-specific settings.
  Future<void> _setupWebView() async {
    await Permission.camera.request();
    await Permission.microphone.request();
    late final PlatformWebViewControllerCreationParams params;

    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params);

    if (_controller.platform is WebKitWebViewController) {
      final WebKitWebViewController webKitController =
          _controller.platform as WebKitWebViewController;
      webKitController.setAllowsBackForwardNavigationGestures(true);
    }

    // Platform-specific configurations
    if (_controller.platform is AndroidWebViewController) {
      final AndroidWebViewController androidController =
          _controller.platform as AndroidWebViewController;

      androidController
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setGeolocationPermissionsPromptCallbacks(
          onShowPrompt: (GeolocationPermissionsRequestParams params) async {
            return const GeolocationPermissionsResponse(
              allow: true,
              retain: true,
            );
          },
          onHidePrompt: () {},
        );
    }

    // Handle permission requests from the web app
    _controller.platform.setOnPlatformPermissionRequest((request) {
      debugPrint('Permission requested: ${request.types}');
      request.grant();
    });

    await _controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await _controller.setBackgroundColor(Colors.transparent);
    await _controller.setUserAgent(
      'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    );
    await _controller.enableZoom(false);
    await _controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (String url) {
          debugPrint('Page started loading: $url');
        },
        onPageFinished: (String url) {
          debugPrint('Page finished loading: $url');
          setState(() {
            _isLoading = false;
          });
        },
        onWebResourceError: (WebResourceError error) {
          debugPrint('WebView error: ${error.description}');
        },
      ),
    );
  }

  /// Obtains the client access token by authenticating with the Didit API.
  Future<String> getClientAccessToken() async {
    const String clientId = "CLIENT_ID";
    const String clientSecret = "CLIENT_SECRET";

    // Combine and Base64 encode the credentials.
    // Combine and Base64 encode the credentials.
    final String encodedCredentials = base64Encode(
      utf8.encode('$clientId:$clientSecret'),
    );

    final Uri authUri = Uri.parse(
      'https://apx.staging.didit.me/auth/v2/token/',
    );

    final response = await http.post(
      authUri,
      headers: {
        'Authorization': 'Basic $encodedCredentials',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: 'grant_type=client_credentials',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['access_token'];
    } else {
      throw Exception(
        'Failed to obtain client access token: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Creates a new verification session using the Didit API.
  Future<Map<String, dynamic>> createSession({
    required String features,
    required String callback,
    required String vendorData,
    required String accessToken,
  }) async {
    final Uri sessionUri = Uri.parse(
      "https://verification.staging.didit.me/v1/session/",
    );
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $accessToken",
    };

    final body = jsonEncode({
      "callback": callback,
      "features": features,
      "vendor_data": vendorData,
    });

    final response = await http.post(sessionUri, headers: headers, body: body);

    if (response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        "Failed to create session: ${response.statusCode} ${response.body}",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(controller: _controller),
    );
  }
}
