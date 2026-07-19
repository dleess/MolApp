# Keep the JavaScript bridge interface methods reachable from WebView JS.
-keepclassmembers class com.donghan.molapp.MolStarBridge {
    @android.webkit.JavascriptInterface <methods>;
}
