# Modelo de amenazas

## Escenario y fronteras

El atacante dispone de una sesión temporal válida del rol `cloud-security-lab-app`
o ejecuta código en su instancia. No dispone de permisos del operador, control de
Terraform ni capacidad para cambiar SCP, políticas, rutas o security groups.
Los documentos son sintéticos; no se cargan datos personales o de producción.

Activos: confidencialidad de documentos, versiones recuperables, separación de
prefijos, integridad de auditoría y presupuesto. Las fronteras separan el rol
app del operador, la red privada de internet y los documentos de los logs.

| Amenaza | Control implementado | Prueba prevista | Riesgo residual |
| --- | --- | --- | --- |
| T01 Lectura/escritura lateral | IAM y endpoint limitados al ARN con prefijo | P04–P07 | Datos del prefijo autorizado siguen expuestos a la app |
| T02 Borrado o destrucción por sobrescritura | Sin permisos de borrado/versiones; versionado | P02–P03, P08–P09 | Puede sobrescribir la versión actual; recuperación requiere operador |
| T03 Uso de credenciales desde otra red | Deny del bucket para app sin el endpoint concreto | P14 | No protege frente a un atacante ya situado en la sonda privada |
| T04 Exposición pública o HTTP | Bloqueo público, ACL deshabilitadas, Deny HTTP | P12–P13 | AWS puede aplicar otros controles; aislar la causa exige comparar respuestas |
| T05 Escalada de privilegios | Allow IAM solo GetObject/PutObject; confianza EC2 | P15–P16 | Operador con PassRole amplio podría asociar el perfil a otra instancia |
| T06 Manipular o leer auditoría | Bucket separado con Deny explícito al rol; sin permisos CloudTrail | P10–P11, P17 | Administrador de cuenta puede alterar políticas/trail |
| T07 Salida a internet o acceso entrante | Sin ruta por defecto privada; SG sin entrada y salida a S3 | P18–P20 | Resolver DNS/IMDS tienen excepciones; no es un sistema anti-exfiltración completo |
| T08 Eludir o perder evidencias | Trail, selector de datos del bucket, digests y copia externa | P21–P22 | Rechazos del endpoint y tráfico bloqueado pueden no generar eventos seleccionados |
| T09 Agotar presupuesto | Diseño sin servicios persistentes innecesarios; sesiones cortas | P23 | Put/Get, versiones y multipart pueden generar gasto; alerta no es límite |

No se añade un permissions boundary ni una SCP. La ausencia de grants es una
denegación implícita dependiente del conjunto de políticas. Una política futura
podría ampliar acciones de la app: habría que repetir la revisión. La denegación
del bucket de logs y la exigencia de endpoint permanecen explícitas.

La evidencia de las sondas la produce código que, en un compromiso real, podría
manipularse. Se contrasta con observaciones del operador y eventos de servicio.
CloudTrail no observa bytes que nunca alcanzan una API. Tampoco se confunde una
sesión del mismo rol con una reproducción literal del robo de la misma sesión.
