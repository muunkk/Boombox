import SwiftUI
import WebKit

/// WebView for YouTube Music login.
struct LoginWebView: NSViewRepresentable {
    @Environment(WebKitManager.self) private var webKitManager

    /// Callback when navigation completes to YouTube Music.
    var onNavigationToYouTubeMusic: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigationToYouTubeMusic: self.onNavigationToYouTubeMusic)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = self.webKitManager.createLoginWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = WebKitManager.userAgent

        // Load YouTube Music directly so Google controls any sign-in redirect.
        if let url = URL(string: WebKitManager.origin) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_: WKWebView, context _: Context) {
        // No updates needed
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigationToYouTubeMusic: (() -> Void)?

        init(onNavigationToYouTubeMusic: (() -> Void)?) {
            self.onNavigationToYouTubeMusic = onNavigationToYouTubeMusic
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            // Check if we've navigated to YouTube Music
            if let url = webView.url,
               url.host?.contains("music.youtube.com") == true
            {
                self.onNavigationToYouTubeMusic?()
            }
        }
    }
}

#Preview {
    LoginWebView()
        .environment(WebKitManager.shared)
        .frame(width: 500, height: 600)
}
