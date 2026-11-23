# MusicSK 1.5 — resultados parciales

## Estado

Trabajo incompleto. No se modificó código de producción ni se ha generado una compilación. La rama local `musicsk/1.5-project-stability` parte de `2e8e8a9`; los únicos archivos creados son este informe y `MUSICSK_1_5_AUDIT.md`.

- Biblioteca: **NO REPRODUCIBLE en este entorno**. Existe una corrección previa para historial duplicado en `b6575d6`, pero no hay evidencia de que explique el fallo actual del usuario.
- Bitrate, lossless, protección y estabilidad de reproducción: **PENDIENTE**. Se identificó la semántica mixta del contador de protección, sin establecer la causa del caso reportado.
- JioSaavn: **PENDIENTE**. Se identificó la implementación, sin probar conectividad ni reproducción.
- Ecualizador y ruta de audio: **PENDIENTE**. No se verificaron respuesta de frecuencia, interfaz ni métricas en ejecución.
- Regresiones y entrega iOS: **PENDIENTE**. No se ejecutaron pruebas, workflow ni compilación y no existe IPA ni artefacto de esta sesión.

## Limitaciones y riesgos

El entorno es Linux sin Xcode ni dispositivo iOS; `gh auth status` indica credencial inválida, por lo que no se puede publicar la rama ni activar el workflow. La selección de base excluye el port Auden según la instrucción expresa, pero requiere comparar funcionalmente cualquier cambio exclusivo de esa rama. La auditoría es preliminar y no debe usarse como certificación de estabilidad.

Para investigar el crash real: reproducirlo en iPhone anotando versión y pasos; obtener el informe simbolicado desde Xcode > Devices and Simulators > View Device Logs, o desde Ajustes > Privacidad y seguridad > Análisis y mejoras > Datos de análisis; conservar el informe completo y los dSYM de la misma compilación. No borrar datos de la biblioteca antes de obtener una copia y el informe.

## Avance posterior

- `9a81c99`: normaliza histogramas diarios restaurados a 24 valores y añade una regresión. **CORREGIDO SIN VERIFICACIÓN EN DISPOSITIVO** para el acceso fuera de rango identificado; la prueba Swift sigue pendiente y no se ha reproducido el cierre reportado al abrir Biblioteca.
- `616e272`: la ruta iOS de JioSaavn pide URLs al método `song.generateAuthToken`, valida respuesta HTTPS y prueba calidades inferiores; añade verificador de respuestas. **CORREGIDO SIN VERIFICACIÓN EN DISPOSITIVO** como cambio de código; búsqueda, disponibilidad y reproducción reales permanecen **PENDIENTES**. La red del entorno devolvió 403 CONNECT al consultar JioSaavn. La prueba Swift no se ha ejecutado.
- `7d2d549`: dimensiones de sliders y validación de ganancias guardadas del ecualizador. **CORREGIDO SIN VERIFICACIÓN EN DISPOSITIVO**; el rediseño completo y su accesibilidad visual siguen **PENDIENTES**.
- `f1ec92b`: prueba de respuesta de las siete bandas. Se ejecutó el módulo Rust del ecualizador de forma aislada mediante un proyecto Cargo temporal con `serde_json`: **10 pruebas superadas**. No es una prueba de la ruta de reproducción completa.
- Bitrate y diagnóstico: **PENDIENTE**. La verificación del archivo decodifica un cuarto de segundo y estima la tasa por bytes de paquetes y muestras decodificadas; no se ha explicado ni reproducido el valor 1 kbps.

El contenedor Swift sigue descargándose; no se ha compilado la app ni comprobado la IPA. No hay validación en iPhone. Los commits anteriores son locales y no se han publicado.
- `376c1da`: la pantalla identifica los valores de flujo como informados o estimados y no presenta ceros de protección cuando faltan datos. El cálculo y la procedencia exacta del bitrate en cada ruta siguen **PENDIENTES**; cambio visual sin verificar en iOS.
- `9d1877f`: exige coincidencia de identificador en detalles de JioSaavn para evitar asociar la primera respuesta disponible a una canción distinta; sus casos de regresión Swift aún no se han ejecutado.
- `a30cb23`: valida los meses antes de reemplazar historial importado; un archivo sin meses válidos ya no inicia el borrado. Prueba de regresión añadida, **PENDIENTE** de ejecutar con Swift.
- `4945967`: para caché completa con duración disponible, estima kbps a partir del tamaño total y duración; incluye la sobrecarga del contenedor y no es bitrate nominal. Con datos insuficientes conserva la selección previa. Prueba añadida, **PENDIENTE** de ejecutar con Swift. No se reprodujo el caso reportado de 1 kbps.

La descarga de la imagen completa de Swift falló al registrar una capa por falta de espacio; la imagen `swift:6.2-slim` descargada solo contiene el runtime y no incluye `swiftc`. La comprobación `git diff --check` pasó. `rustfmt --check` no se ejecutó porque el componente no está instalado.
- `cabe5c0`: localiza al español los nombres dinámicos de modos y presets y textos del ecualizador sin cambiar sus identificadores persistidos. Catálogo JSON validado; presentación y accesibilidad **PENDIENTES** de verificar en iOS.

## Verificación Swift en Linux

Se obtuvo Swift 6.2.4 mediante extracción selectiva y se ejecutaron `scripts/check-listening.sh`, `scripts/check-jiosaavn-response.sh` y `scripts/check-cached-bitrate.sh`: todas las comprobaciones pasaron. La regresión del histograma se reprodujo con el código anterior `d5754f7`: terminó con `Fatal error: Index out of range`; con el código actual pasó. El crash al abrir Biblioteca comunicado por el usuario sigue **NO REPRODUCIBLE** sin su biblioteca y registro del dispositivo.

El frontend Swift analizó sintácticamente los archivos Swift modificados; `JioSaavn.swift` pasó además una comprobación de tipos en Linux con stubs de los tipos Apple/compartidos. Esto no sustituye una compilación de la aplicación ni verifica la API remota. Las pruebas de historia, respuestas y cálculo se consideran verificadas en Linux; su integración en dispositivo sigue **CORREGIDO SIN VERIFICACIÓN EN DISPOSITIVO**. No se ha generado IPA ni validado reproducción de proveedor real.

`a1b6f0d`: `scripts/check-cached-bitrate-fixture.sh` pasó en Linux con FFmpeg y Swift. En un Opus VBR sintético de seis segundos con un segundo inicial silencioso, los primeros 260 ms dieron 1,20 kbps y el promedio del archivo completo 127 kbps. La prueba demuestra que una ventana inicial puede explicar una cifra cercana a 1 kbps; no identifica por sí sola el origen de la captura del iPhone ni mide ese archivo real.

`0e396e9`: `scripts/check-jiosaavn-stream.sh` pasó en Swift/Linux con respuestas HTTP simuladas. Comprueba solicitud de detalles, fallo de 320 kbps, selección de 160 kbps y fallo de red/servidor controlado. Los servicios y pistas reales siguen **PENDIENTES** de comprobación; la prueba no demuestra disponibilidad regional ni reproducción en dispositivo.

- `6403422`: un historial con identificadores duplicados y contadores de reproducción extremos provocaba un desbordamiento entero. La prueba lo reprodujo antes de la corrección y ahora pasa en Linux; se satura el contador si la suma supera el rango representable. **CORREGIDO Y VERIFICADO** para la operación aislada; integración en iPhone pendiente.
- `1fcbbf3`: una duración corrupta muy grande provocaba un trap al convertir minutos para Replay. La regresión falló antes y pasa con la corrección en Linux; la conversión limita los valores al rango representable. **CORREGIDO Y VERIFICADO** para la operación aislada; integración en iPhone pendiente.
- `4cf4443`: las filas de diagnóstico pueden pasar a dos líneas para valores largos y usan colores adaptables; se añadieron traducciones españolas de títulos y etiquetas. Swift pasó análisis sintáctico y el catálogo pasó validación JSON; presentación real **PENDIENTE** de verificar en iOS.

- `0fed8eb`: corrige una carrera por inspección en la que el arranque podía aplicar una instantánea de EQ anterior a una edición durante la activación. Lee y aplica el ajuste vigente en el actor principal y muestra errores de aplicación. Sintaxis Swift verificada; reproducción de la carrera y prueba de integración iOS **PENDIENTES**. **CORREGIDO SIN VERIFICACIÓN EN DISPOSITIVO**.
- `ade7bbb` y `9ded8f0`: reorganizan los controles del ecualizador en una vista desplazable, con superficies adaptables, siete bandas conservadas y transiciones que respetan reducir movimiento. Sintaxis Swift verificada; diseño, accesibilidad y táctil **PENDIENTES** de inspección en iPhone. Las diez pruebas aisladas de EQ Rust volvieron a pasar.
