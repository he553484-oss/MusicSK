# MusicSK 1.7 — estado de desarrollo

Estado: **incompleto; candidata en verificación**. No se ha reproducido ni diagnosticado el cierre de Biblioteca con la cuenta real en un iPhone; no se declara resuelto. La rama parte de `1db723e`, que conserva el código de 1.6 compilado en `5d05337`.

## Cambios y evidencias

- **Biblioteca autenticada — pendiente de verificar en dispositivo.** Se valida el JSON del puente antes de presentarlo, se omiten registros sin identidad utilizable y se agrupan identificadores repetidos. La respuesta completamente malformada produce error; los diagnósticos guardan solo recuentos de registros inválidos o repetidos, sin contenido de cuenta. La vista no presenta estanterías de una generación de sesión anterior. La prueba Swift cubre datos sintéticos incompletos, duplicados, respuesta vacía, cambio de generación y 10.000 entradas; pasó en Linux. Se preparó además una captura de simulador con 1.000 registros sintéticos y un duplicado, sin cuenta real. Esto no identifica la causa del cierre real y no reemplaza una prueba autenticada.
- **Pantalla de bloqueo — sin verificación en dispositivo.** Se conservó la publicación existente de imágenes estáticas y animadas y se añadieron opciones para permitir animación y restringirla a Wi‑Fi. La política sigue respetando ahorro de energía, movimiento reducido, datos restringidos, reproducción automática del sistema y temperatura. Las pruebas locales de política y del coordinador de Now Playing pasaron. iOS decide si amplía o anima la portada; no se han validado estas opciones en un iPhone.
- Apple documenta las [variantes animadas y sus condiciones de presentación](https://developer.apple.com/documentation/mediaplayer/providing-animated-artwork-for-media-items) y los métodos públicos para [personalizar `MPVolumeView`](https://developer.apple.com/documentation/mediaplayer/mpvolumeview).
- **Álbum inmersivo — sin verificación en dispositivo.** Se conservó la cabecera existente de borde a borde, la extracción de color y la gestión de visibilidad de la animación; se centró el título y artista en pantallas compactas. Hay una captura de álbum sintético preparada para el simulador. No se afirma paridad visual con Apple Music ni se han validado todos los tamaños y gestos.
- **Regresiones locales.** Pasaron los verificadores disponibles de letras, apariencia, controles de volumen, reproducción y política de cola, 27 comprobaciones de presentación de vídeo y 10 pruebas aisladas de filtros Rust. La prueba del coordinador de cuentas pasó en Linux usando un adaptador temporal de SHA-256 de OpenSSL en lugar de CryptoKit; incluye aislamiento de cuentas, error sin conexión, cancelación y respuestas tardías. No se modificaron archivos internos de letras ni se usó un iPhone.
- **JioSaavn — pendiente.** Los resultados simulados anteriores no demuestran audio real. No se ha identificado una vía pública autorizada de audio; los [términos oficiales](https://corporate.saavn.com/terms/) requieren un acuerdo para interfaces no oficiales. No se ha eludido ningún control de acceso.
- **Volumen — sin verificación en dispositivo.** El control sigue siendo el `MPVolumeView` visible y accesible; se personalizaron sus imágenes públicas de pista y cursor, sin usar ganancia interna. El verificador estático pasó. Falta comprobar arrastre, botones físicos y rutas reales en iPhone.
- **Alcance restante.** Faltan opciones adicionales de pantalla bloqueada y animación, una revisión visual más amplia, pruebas de volumen real, biblioteca autenticada, vídeo a pantalla completa, Bluetooth, segundo plano y bloqueo. El control de volumen del sistema y el motor DSP existentes no se sustituyeron.

## Compilación

La compilación y las capturas iOS se ejecutan en GitHub Actions sobre la rama de trabajo. Consultar los resultados y validar la IPA arm64 antes de atribuir éxito. La versión configurada es 1.7.0 build 12. No se afirma que se haya generado una IPA hasta verificar el artefacto.

## Registro de crash en iPhone

Reproducir el cierre y abrir Ajustes → Privacidad y seguridad → Análisis y mejoras → Datos del análisis. Seleccionar el archivo de MusicSK correspondiente a la hora del cierre y compartir el tipo de excepción, `Triggered by Thread` y la sección `Thread … Crashed`. No compartir cookies, tokens ni credenciales.
