import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'src/viewer_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Android needs the WebView provider resolved before the first InAppWebView is built; the other
  // platforms use whatever engine ships with the OS.
  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }
  runApp(const MolApp());
}

class MolApp extends StatelessWidget {
  const MolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MolApp',
      debugShowCheckedModeBanner: false,
      // The viewport is a dark WebGL canvas; a light chrome around it would be jarring, so the
      // whole app is dark on every platform, matching the iOS and Android originals.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0072B2),
          brightness: Brightness.dark,
        ),
      ),
      home: const MoleculeViewerPage(),
    );
  }
}
