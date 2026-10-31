import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EditorAutomaticoApp());
}

class EditorAutomaticoApp extends StatelessWidget {
  const EditorAutomaticoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Editor Automático',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const EditorHomePage(),
    );
  }
}

class EditorHomePage extends StatelessWidget {
  const EditorHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editor Automático')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.movie_creation_outlined, size: 76),
                  const SizedBox(height: 24),
                  Text(
                    'Seu vídeo. Seu dispositivo. Seu controle.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Prepare seus vídeos para cortes automáticos e legendas, '
                    'com processamento local.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  const FilledButton.icon(
                    onPressed: null,
                    icon: Icon(Icons.add),
                    label: Text('Importar vídeo'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Importação de mídia será implementada na próxima etapa.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
