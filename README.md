# Editor Automático

Aplicativo Flutter Android-first para editar vídeos com processamento local.

## Estado atual — versão 0.4.0

- Importação de vídeo e cópia para armazenamento privado.
- Lista de projetos persistida localmente.
- Reprodução, pausa e navegação pela duração do vídeo.
- Extração de áudio para WAV mono 16 kHz usando FFmpeg.
- Transcrição automática em português com Whisper.cpp no próprio aparelho.
- Detecção Silero VAD de regiões de fala e geração de um plano de cortes não destrutivo com margens de segurança.
- Revisão do plano de cortes: pausas detectadas podem ser restauradas antes da renderização.
- Geração de legendas SRT sincronizadas pelos timestamps do Whisper.
- Download sob demanda do modelo multilíngue Whisper Tiny (aproximadamente 75 MB); depois do download, a inferência funciona offline.
- Exportação e compartilhamento do SRT.
- Aplicação dos cortes planejados, concatenação de vídeo/áudio e queima das legendas no MP4.
- Recalculo dos timestamps SRT para a timeline resultante.
- Salvamento local do estado da edição e recuperação do último resultado concluído.
- Cancelamento de inferência Whisper e de operações FFmpeg.
- Revisão/adição manual de legendas como recurso opcional.

Os arquivos de vídeo e áudio são processados localmente. O aplicativo não envia mídia para servidores. A primeira execução da transcrição precisa de internet apenas para baixar o modelo.

## Ainda precisa ser validado / evoluído

- Compilação Android e execução em aparelho físico; o CI deve validar dependências, análise estática, testes e APK.
- Pré-visualização dentro do app do MP4 já renderizado.
- Retomada de uma inferência interrompida no meio; o app recupera o último estado completo salvo, não o estado interno de uma inferência nativa interrompida.
- Ajustes finos de VAD e margens com base em vídeos reais em português.

**Importante:** o pipeline de cortes, sincronização e renderização foi adicionado ao código. Ainda precisa passar pelo build Android e por testes em aparelho físico; não considere o APK pronto antes dessas verificações. Não considere a versão pronta até o GitHub Actions concluir análise, testes e APK com sucesso.

## Motores

- [whisper_cpp_flutter_plus](https://pub.dev/packages/whisper_cpp_flutter_plus): Whisper.cpp offline, timestamps e suporte VAD. O modelo não vem embutido no APK.
- [ffmpeg_kit_flutter_new_video](https://pub.dev/packages/ffmpeg_kit_flutter_new_video): extração e processamento de mídia; variante com suporte a bibliotecas de legendas.

O plugin Whisper exige Android API 24 ou superior. O workflow configura esse mínimo após gerar o projeto Android.

## Testes automatizados

A suíte `test/edit_timeline_test.dart` cobre a preservação das margens de fala, o comportamento sem fala detectada, o mapeamento de tempos após cortes, a serialização do plano de edição e a leitura/escrita/retimização de SRT.

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

O GitHub Actions executa análise, testes e build de APK debug em cada push para `main` e em pull requests. O APK fica disponível como artefato quando a execução termina com sucesso.

## Armazenamento

Os vídeos importados e os arquivos temporários ficam no armazenamento privado do aplicativo. Apagar os dados ou desinstalar o aplicativo remove os arquivos locais. Mantenha os originais em outro local.
