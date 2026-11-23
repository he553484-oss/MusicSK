# MusicSK 1.5 — auditoría preliminar (incompleta)

Base local: `musicsk/1.4-development` en `2e8e8a9`, rama de trabajo `musicsk/1.5-project-stability`. `main` es antecesor de esta base. 1.4-development sucede a 1.3 e incluye `b6575d6`, corrección previa de apertura de Biblioteca ante historial duplicado. La rama 1.4-auden-port tiene commits posteriores de port Auden, excluidos por la instrucción del proyecto; no se ha establecido que la base elegida conserve todas las funciones de esa rama. Ninguna rama remota se modificó.

## Arquitectura y puntos de inspección

- Interfaz Apple: `AppleApp/Sources/UI`, Biblioteca en `UI/Library`, estado y persistencia relacionados en `PlaybackSession/ListeningStore.swift`, `LocalLibrary.swift` y `PlaybackController+Library.swift`.
- Motor: `native-core` en Rust, puente UniFFI, decodificación Symphonia y adaptador libopus, salida CPAL/CoreAudio, libsoxr, mezclador y protección en `src/sound.rs`; sesión y rutas Apple en `AudioSessionManager.swift` y `AudioRouteState.swift`. Existe una ruta Dolby separada en `AppleDolbyRenderer.swift`.
- Proveedores: implementación Apple de JioSaavn en `PlaybackSession/JioSaavn.swift`, implementación compartida en `shared/.../sources/JioSaavnSource.kt`; existen pruebas compartidas de transporte y selección de fuentes. La implementación Apple consulta una API no oficial, descifra el campo de URL y deriva una variante 320 mediante sustitución de texto. No se ha verificado que el servicio siga aceptando estas solicitudes ni que las URLs resultantes sean válidas o autorizadas.
- Ecualizador: `AppleApp/Sources/UI/EqualizerView.swift` y `native-core/src/eq`. Diagnóstico: `AudioPipelineSheet.swift`, `PlaybackController+Diagnostics.swift` y registros del motor.
- Workflow existente: `.github/workflows/release.yml`, modo `build-ios`, runner `xcode-27`; construye y verifica IPA sin firmar. Pruebas Kotlin en `shared/src/commonTest`, pruebas Rust junto al código y verificadores bajo `scripts`.

## Hallazgos comprobados en código

`Protector::process` incrementa `interventions` para muestras no finitas, para cada trama estéreo cuyo pico detectado excede el techo y para cada muestra de salida recortada. Es una suma de unidades heterogéneas, no un recuento de episodios independientes. La cifra reportada no demuestra por sí sola un fallo ni permite inferir el número de eventos audibles.

El campo `claimed_kbps` del motor se describe como tasa declarada por el resolvedor, con cero para desconocido; la pantalla presenta `nerd.kbps` como bitrate sin aclarar procedencia. No se ha trazado aún toda la cadena para explicar el 1 kbps concreto ni medido ningún archivo. PCM Float32 de salida no demuestra que el origen sea lossless.

## Pendiente de auditoría

Reproducir el fallo actual con datos reales y símbolos; verificar migración y corrupción de datos, ciclos de vida y concurrencia; trazar cálculos de tasa y rutas de caché, selección de fuentes y reconstrucción de salida; comprobar respuestas de proveedores sin eludir restricciones; probar respuesta de frecuencia, presets y persistencia; revisar todos los workflows y rutas de almacenamiento. No se ha hecho la auditoría completa requerida y estos indicios no constituyen diagnósticos concluyentes.
