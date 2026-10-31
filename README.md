# Editor Automático

Aplicativo Flutter Android-first para editar vídeos com processamento local.

## Estado atual — versão 0.3.0

- Importação de vídeo e cópia para armazenamento privado.
- Lista de projetos persistida localmente.
- Reprodução, pausa e navegação pela duração do vídeo.
- Extração de áudio para WAV mono 16 kHz usando FFmpeg.
- Transcrição automática em português com Whisper.cpp no próprio aparelho.
- Geração de legendas SRT sincronizadas pelos timestamps do Whisper.
- Download sob demanda do modelo multilíngue Whisper Tiny (aproximadamente 75 MB); depois do download, a inferência funciona offline.
- Exportação e compartilhamento do SRT.
- Revisão/adição manual de legendas como recurso opcional.

Os arquivos de vídeo e áudio são processados localmente. O aplicativo não envia mídia para servidores. A primeira execução da transcrição precisa de internet apenas para baixar o modelo.

## Ainda não implementado

- VAD Silero independente para mapear fala e silêncio com maior precisão.
- Timeline não destrutiva e plano de cortes seguros.
- Remoção automática de pausas sem cortar palavras.
- Renderização/exportação MP4 com cortes e legendas queimadas.
- Retomada de tarefas interrompidas e cancelamento completo do processamento.

**Importante:** a integração do Whisper e do FFmpeg foi adicionada ao código, mas ainda precisa passar pelo build Android e por testes em aparelho físico. Não considere a versão pronta até o GitHub Actions concluir análise, testes e APK com sucesso.

## Motores

- [whisper_cpp_flutter_plus](https://pub.dev/packages/whisper_cpp_flutter_plus): Whisper.cpp offline, timestamps e suporte VAD. O modelo não vem embutido no APK.
- [ffmpeg_kit_flutter_new_video](https://pub.dev/packages/ffmpeg_kit_flutter_new_video): extração e processamento de mídia; variante com suporte a bibliotecas de legendas.

O plugin Whisper exige Android API 24 ou superior. O workflow configura esse mínimo após gerar o projeto Android.

## Desenvolvimento

Requer Flutter stable e Android SDK:

```bash
flutter create . --platforms=android --project-name editor_automatico
# Defina minSdk = 24 em android/app/build.gradle(.kts)
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

O GitHub Actions executa análise, testes e build de APK debug em cada push para `main`. O APK fica disponível como artefato quando a execução termina com sucesso.

## Armazenamento

Os vídeos importados e os arquivos temporários ficam no armazenamento privado do aplicativo. Apagar os dados ou desinstalar o aplicativo remove os arquivos locais. Mantenha os originais em outro local.
