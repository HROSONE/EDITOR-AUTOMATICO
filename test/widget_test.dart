import 'package:editor_automatico/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders editor home and import action', (tester) async {
    await tester.pumpWidget(const EditorAutomaticoApp());
    expect(find.text('Editor Automático'), findsOneWidget);
    expect(find.text('Seu vídeo. Seu dispositivo. Seu controle.'), findsOneWidget);
    expect(find.text('Importar vídeo'), findsOneWidget);
    expect(find.text('Seus projetos'), findsOneWidget);
  });
}
