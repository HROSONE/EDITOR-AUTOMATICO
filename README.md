# Editor Automático

Aplicativo Flutter Android-first para preparar vídeos localmente.

## Estado atual — versão 0.2.0

- Importação de um vídeo pelo seletor nativo do Android.
- Cópia do vídeo para o armazenamento privado do aplicativo.
- Lista de projetos persistida localmente.
- Reprodução, pausa e navegação pela duração do vídeo.
- Criação manual de legendas com marcação de tempo.
- Exportação e compartilhamento de arquivo SRT.
- Exclusão de projeto e respectivo arquivo local.

Os vídeos não são enviados para servidores pelo aplicativo.

## Ainda não implementado

- Detecção automática de fala/silêncio (VAD).
- Transcrição automática em português com Whisper.
- Timeline não destrutiva e plano de cortes.
- Remoção automática de pausas.
- Renderização/exportação MP4 com cortes e legendas queimadas.

Esses recursos exigem integração e validação de motores nativos. A integração deve usar processamento por blocos e limites de memória para dispositivos móveis.

## Desenvolvimento

Requer Flutter stable e Android SDK.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

O GitHub Actions executa análise, testes e build de APK debug em cada push para `main`. O APK fica disponível como artefato quando a execução termina com sucesso.

## Armazenamento

Os arquivos importados são copiados para o diretório privado do aplicativo. Apagar os dados ou desinstalar o aplicativo remove os arquivos locais. Mantenha os originais em outro local.
