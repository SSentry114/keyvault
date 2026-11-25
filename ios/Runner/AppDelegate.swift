import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // WKWebView chỉ phát tiếp khi app xuống nền nếu audio session ở category
    // .playback. Kèm UIBackgroundModes=audio trong Info.plist.
    // Lưu ý: category này cũng bỏ qua nút gạt im lặng của máy.
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      NSLog("AVAudioSession setup failed: \(error)")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
