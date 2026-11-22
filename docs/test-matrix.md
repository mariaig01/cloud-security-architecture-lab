# Matriz de pruebas

**Todas las pruebas AWS de esta tabla están pendientes.** Hito 1 comprueba la
configuración con mocks y el clasificador local; eso no equivale a ejecutar estas
operaciones. Identidades: `app-private` y `app-public` son dos sesiones del mismo
rol EC2; `operator` es el perfil temporal del propietario del laboratorio.

Variables de lectura: `DOCS` y `LOGS` son los buckets; `PREFIX=app/documents/`;
`RUN_ID` es único; `KEY=PREFIX/probe/RUN_ID/document.txt`. El operador prepara
objetos sintéticos fuera del prefijo y un canario en logs antes de probar lecturas
denegadas. No se ensayan borrados sobre logs auténticos.

| ID / amenaza | Acción | Identidad / origen | Recurso | Resultado esperado | Evidencia a recoger |
| --- | --- | --- | --- | --- | --- |
| P01 / control positivo | `PutObject` | app-private | DOCS/KEY | Permitido, VersionId presente | JSON de sonda, versión, evento de datos |
| P02 / T01 | `GetObject` y comparación | app-private | DOCS/KEY | Permitido, hash coincide | Hash SHA-256 y evento de datos |
| P03 / T02 | Segundo `PutObject`; lectura actual y recuperación anterior | app-private; operator para recuperar | DOCS/KEY | Sobrescritura permitida, VersionId distinto; operador recupera v1 y confirma v2 actual | Versiones y hashes; la lectura posterior la completa operator |
| P04 / T01 | `GetObject` existente | app-private | DOCS/restricted/RUN_ID/fixture.txt | `AccessDenied` | Preparación del fixture, respuesta cliente; evento si se entrega |
| P05 / T01 | `PutObject` | app-private | DOCS/restricted/RUN_ID/unexpected.txt | `AccessDenied` | Respuesta cliente y ausencia comprobada por operator |
| P06 / T01 | `PutObject` en prefijo parecido | app-private | DOCS/app/documents-other/RUN_ID/unexpected.txt | `AccessDenied` | Clave exacta y respuesta cliente |
| P07 / T01 | `ListObjectsV2` incluso con prefijo autorizado | app-private | DOCS | `AccessDenied` | Respuesta cliente; no se necesita listado para la aplicación |
| P08 / T02 | `DeleteObject` | app-private | DOCS/KEY sintético | `AccessDenied` | Respuesta y objeto todavía presente |
| P09 / T02 | `DeleteObject` con VersionId; `GetObject` de esa versión | app-private | DOCS/KEY versión v1 | Ambas denegadas | Respuestas; operator comprueba versión intacta |
| P10 / T06 | `GetObject` | app-private y app-public | LOGS/probe-fixtures/RUN_ID/audit-canary.txt | `AccessDenied` | Ambas respuestas; la pública no atraviesa la política del endpoint |
| P11 / T06 | `PutObject`, `DeleteObject` | app-private y app-public | Mismo canario de LOGS | `AccessDenied` | Respuestas; operator verifica canario intacto. Sin datos de LOGS en este trail |
| P12 / T04 | `GetObject` sin firma por HTTPS | Anónimo / equipo local | DOCS/KEY y canario LOGS | HTTP 403 | Respuesta y configuración de bloqueo público; no usar documentos reales |
| P13 / T04 | `GetObject` sin firma por HTTP; inspección de política | Anónimo / equipo local; operator | DOCS/KEY y canario LOGS | HTTP rechazado; Deny TLS presente | Respuesta HTTP más política desplegada. La respuesta anónima NO aísla TLS del bloqueo público |
| P14 / T03 | `GetObject` de clave conocida por HTTPS | app-public | DOCS/KEY creado por privada | `AccessDenied` pese al Allow IAM | STS de la sonda pública, respuesta y ausencia de ruta al endpoint; contraste P02 |
| P15 / T05 | `CreateRole` con confianza EC2, sin políticas | app-public | Rol canario cslab-denied-RUN_ID | `AccessDenied` | Respuesta y evento de administración; si se crea inesperadamente, fallo y limpieza por operator |
| P16 / T05 | `AssumeRole` al rol app | operator sin capacidad de editar confianza durante la prueba | ARN del rol app | Denegado por confianza de servicio EC2 | Respuesta STS y política de confianza. Requiere Allow STS del operador para aislar la confianza |
| P17 / T06 | `UpdateTrail` conservando todos los valores existentes | app-public | ARN del trail | `AccessDenied` | Respuesta, evento de administración y `get-trail-status` antes/después. No invocar StopLogging/DeleteTrail |
| P18 / T07 | Conexión TCP IPv4 a example.com:443 | app-private | IP resuelta y puerto 443 | Timeout o sin ruta | JSON de sonda, DNS resuelto, inspección de SG/rutas; control externo al mismo destino |
| P19 / T07 | Conexión HTTPS a APIs IAM/CloudTrail | app-private | Endpoints públicos de servicios | Sin conectividad | Errores/timeout, **no** prueba IAM; contraparte pública llega a la API en P15/P17 |
| P20 / T07 | Intento TCP 8080 a listener temporal privado | app-public; control loopback en app-private | IP privada de la sonda | Bloqueado pese a ruta local | Listener comprobado localmente, timeout desde pública y reglas efectivas; breve solapamiento de sondas |
| P21 / T08 | Recogida y correlación | operator | Trail y logs AWSLogs/ | P01–P03 observados; administración relevante correlacionada | `eventTime`, `eventName`, `userIdentity`, `resources`, `errorCode`, `requestID`, `eventID`, `vpcEndpointId` si existe |
| P22 / T08 | `cloudtrail validate-logs` | operator | Logs y digests de intervalo cerrado | Validación satisfactoria, o limitación documentada | Comando, salida, intervalo UTC y manifiesto SHA-256 de exportación |
| P23 / T09 | Costes y recursos finales | operator | Inventario de laboratorio / facturación | Recursos eliminados o retención inventariada | Inventario antes/después y gasto observado tras actualizar facturación |

## Interpretación y límites

- Un `AccessDenied` acredita un rechazo de autorización, pero puede provenir de
  varias políticas. Los rechazos privados sobre otros prefijos/buckets combinan
  IAM y endpoint. La sonda pública ayuda a evaluar controles sin ese endpoint.
- P13 es una comprobación conjunta de rechazo público/HTTP y de política desplegada,
  no una demostración aislada de TLS. No enviamos tokens de sesión por HTTP para
  probarlo. El contrato local comprueba explícitamente `aws:SecureTransport`.
- Un timeout puede resultar de SG, rutas o problemas del destino. P18 necesita
  DNS correcto, S3 positivo y un control externo al mismo destino. Una IP privada
  sin listener no sirve de control para P20.
- Los resultados de la sonda privada contienen `VersionId`, ETag y código de
  salida. AWS CLI no expone siempre `requestID`; se obtiene del evento y se
  correlaciona por sesión, clave única y ventana UTC. No usar `--debug` para
  publicar trazas con material de autenticación.
- Las operaciones bloqueadas por red no llegan al servicio. Los rechazos por
  política de endpoint pueden requerir eventos de **actividad de red**, no
  habilitados aquí. No interpretar su ausencia como fallo de CloudTrail ni como
  acceso permitido. [Eventos de red de CloudTrail](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/logging-network-events-with-cloudtrail.html).
- El historial de eventos no muestra los eventos de datos S3. Para P21 se leen
  los archivos entregados al bucket. [Eventos S3 y CloudTrail](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudtrail-logging-s3-info.html).

Formato del registro final: ID, estado (`passed`, `failed`, `inconclusive` o
`not_run`), UTC, identidad, ubicación, recurso, salida real, evidencia enlazada y
explicación de la causa demostrada. No rellenar `passed` con expectativas.
