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
