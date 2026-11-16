import 'package:flutter/material.dart';

import 'data/fix_loop_api.dart';
import 'data/http_fix_loop_api.dart';
import 'design/fix_loop_theme.dart';
import 'features/auth/auth_page.dart';
import 'features/home/home_page.dart';
import 'preview/photo_picker.dart';
import 'state/app_controller.dart';

export 'features/auth/auth_page.dart';

void main() {
  runApp(const FixLoopApp());
}

class FixLoopApp extends StatefulWidget {
  const FixLoopApp({
    this.api,
    this.photoPicker = const DevicePhotoPicker(),
    super.key,
  });

  /// Inject a deterministic fake in widget tests; defaults to the live HTTP client.
  final FixLoopApi? api;
  final PreviewPhotoPicker photoPicker;

  @override
  State<FixLoopApp> createState() => _FixLoopAppState();
}

class _FixLoopAppState extends State<FixLoopApp> {
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppController(api: widget.api ?? HttpFixLoopApi());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => MaterialApp(
        title: 'Fix Loop',
        debugShowCheckedModeBanner: false,
        theme: fixLoopTheme(Brightness.light),
        darkTheme: fixLoopTheme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: _controller.isSignedIn
            ? CampusHomePage(
                key: ValueKey<String>(_controller.currentUser!.id),
                controller: _controller,
                photoPicker: widget.photoPicker,
              )
            : AuthPage(controller: _controller),
      ),
    );
  }
}
