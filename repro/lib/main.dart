import 'package:flutter/material.dart';
import 'package:rive/rive.dart';

/// The wasm host given at build time, if any, so a capture records which
/// rive_native web build it ran.
const wasmHost = String.fromEnvironment('RIVE_NATIVE_WASM_HOST');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RiveNative.init();
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: ReproPage()),
  );
}

/// Shows `assets/image_view.riv`: one image asset drawn twice. The left square
/// is drawn by the vector renderer, the right one by a GPU canvas that samples
/// the same image through `Image:view()`. Both should show the checker.
class ReproPage extends StatefulWidget {
  const ReproPage({super.key});

  @override
  State<ReproPage> createState() => _ReproPageState();
}

class _ReproPageState extends State<ReproPage> {
  late final FileLoader _fileLoader = FileLoader.fromAsset(
    'assets/image_view.riv',
    riveFactory: Factory.rive,
  );

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[repro] wasm host: ${wasmHost.isEmpty ? 'rive_native default' : wasmHost}',
    );
  }

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10151B),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Left: renderer:drawImage. Right: GPU canvas through '
              'Image:view(). Both should show the same checker.',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          Expanded(
            child: RiveWidgetBuilder(
              fileLoader: _fileLoader,
              onLoaded: (_) => debugPrint('[repro] loaded'),
              onFailed: (error, _) => debugPrint('[repro] failed: $error'),
              builder: (context, state) => switch (state) {
                RiveLoading() => const Center(
                  child: CircularProgressIndicator(),
                ),
                RiveFailed() => Center(
                  child: Text(
                    '${state.error}',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                RiveLoaded() => RiveWidget(
                  controller: state.controller,
                  fit: Fit.contain,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}
