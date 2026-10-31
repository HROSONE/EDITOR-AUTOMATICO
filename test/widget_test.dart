import 'package:flutter_test/flutter_test.dart';
import 'package:editor_automatico/main.dart';

void main() {
  testWidgets('renders the editor home screen', (tester) async {
    await tester.pumpWidget(const EditorAutomaticoApp());

    expect(find.text('Editor Automático'), findsOneWidget);
    expect(
      find.text('Seu vídeo. Seu dispositivo. Seu controle.'),
      findsOneWidget,
    );
    expect(find.text('Importar vídeo'), findsOneWidget);
  });
}
