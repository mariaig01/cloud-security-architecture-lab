# Operación del laboratorio

## Estado y frontera de esta entrega

La entrega local está terminada y se puede validar sin cuenta AWS. Los siguientes
pasos son un procedimiento para una ejecución futura: **no se han ejecutado**.
Las sondas existen en Terraform, están desactivadas y solo usan datos sintéticos.
El CI ejecuta pruebas con mocks; no tiene credenciales ni despliega.

## Preparar la cuenta y revisar un plan

1. Utilizar una cuenta de laboratorio y un perfil temporal del operador. Confirmar
   cuenta y región con `aws sts get-caller-identity`. El rol de aplicación no sirve
   para administrar infraestructura. No guardar credenciales en Terraform.
2. Copiar `terraform.tfvars.example` a `terraform.tfvars`; sustituir cuenta y
   nombres de buckets. Mantener las sondas desactivadas inicialmente.
3. Ejecutar `python3 scripts/validate.py`. Conservar el lockfile del proveedor.
4. Consultar [costes](costs.md), trails ya existentes y restricciones de la cuenta.
   Establecer presupuesto operativo y alertas antes de aplicar.
5. Crear y revisar un plan concreto:

```bash
export AWS_PROFILE=lab-operator
export AWS_REGION=eu-west-1
umask 077
mkdir -p artifacts evidence/raw
terraform plan -out=artifacts/base.tfplan
terraform show -no-color artifacts/base.tfplan
```

Comprobar que solo incluye recursos de este laboratorio y la cuenta prevista,
sin instancias, NAT, claves KMS propias ni endpoints de interfaz. El plan contiene
identificadores y configuración; mantenerlo fuera de Git. Guardar fecha, cuenta,
región y estimación junto a la revisión. Una aprobación de documentación no
autoriza cualquier plan futuro.

Tras revisar y autorizar **ese archivo**, la operación sería:

```bash
terraform apply artifacts/base.tfplan
terraform output -json > evidence/raw/outputs.json
```

El estado es local: protegerlo, respaldarlo fuera de Git y conservarlo hasta
verificar el desmontaje. No añadir claves estáticas para resolver fallos de IAM.
La opción `-backend=false` no impide que un plan real contacte AWS.

## Preparar fixtures y fijar una AMI

Desde los outputs, definir `DOCS`, `LOGS`, `PREFIX`, `ACCOUNT` y `TRAIL_ARN`.
Elegir `RUN_ID` único, con 1–64 caracteres alfanuméricos, guion o guion bajo.
Usar el mismo ID para fixtures y ambas sondas. El prefijo autorizado no puede
empezar por `restricted/` ni `probe-fixtures/`: son controles negativos.

```bash
printf 'synthetic restricted fixture\n' > artifacts/restricted.txt
printf 'synthetic audit canary\n' > artifacts/audit-canary.txt
aws s3api put-object --bucket "$DOCS" --expected-bucket-owner "$ACCOUNT" \
  --key "restricted/$RUN_ID/fixture.txt" --body artifacts/restricted.txt
aws s3api put-object --bucket "$LOGS" --expected-bucket-owner "$ACCOUNT" \
  --key "probe-fixtures/$RUN_ID/audit-canary.txt" --body artifacts/audit-canary.txt
```

Guardar las respuestas y comprobar ambos contenidos como operador. Los fixtures
deben existir antes de una lectura negativa. Registrar el hash y VersionId del
canario; comprobarlos nuevamente después de las pruebas.

Obtener un candidato regional, inspeccionarlo y fijarlo por ID:

```bash
aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query Parameter.Value --output text
aws ec2 describe-images --image-ids "$AMI_ID" --owners amazon
```

Comprobar propietario Amazon, nombre estándar `al2023-ami-2023.*-x86_64`,
arquitectura x86_64, HVM, EBS, estado disponible y raíz de como máximo 8 GiB.
Verificar Python 3, AWS CLI v2, cloud-init y certificados en la imagen elegida
antes de depender del arranque sin internet. Terraform verifica los filtros de
la AMI fijada y la sonda verifica CLI v2; no descarga paquetes.
[Parámetros públicos de AMI](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami-parameter-store.html).

## Ejecutar las sondas por fases

Añadir a la configuración local:

```hcl
enable_probes       = true
enable_public_probe = false
probe_ami_id        = "ami-ID-REGIONAL-VERIFICADO"
probe_run_id        = "ID-UNICO-DE-LA-EJECUCION"
```

Los valores de AMI e ID de arriba se sustituyen antes de planificar. Crear un
nuevo plan guardado, revisar su coste y aplicar solo tras aprobarlo. La privada
debe tener una interfaz sin IP pública, SG app y perfil app; raíz gp3 cifrada,
IMDSv2, créditos standard y ningún SSH/SSM. Recoger su consola:

```bash
terraform output -json probes > evidence/raw/probes.json
aws ec2 get-console-output --instance-id "$PRIVATE_INSTANCE_ID" --latest \
  --output json > evidence/raw/private-console.json
python3 scripts/read_console.py evidence/raw/private-console.json \
  --run-id "$RUN_ID" --location private --instance-id "$PRIVATE_INSTANCE_ID" \
  --output evidence/raw/private-records.json
```

Si falta identidad, resumen o subpruebas, conservar el fallo y diagnosticarlo;
no dar el ensayo por aprobado. La consola es bufferizada: repetir la recogida
si todavía no aparece el resumen. El lector acepta `Output` en texto o base64,
comprueba instancia, ubicación e ID y no hace peticiones de red.

Después del control positivo privado P01/P02, cambiar únicamente
`enable_public_probe = true`, revisar un segundo plan y aplicar. Mantener AMI,
RUN_ID, claves y configuración privada: cambiarlos recrea la sonda y sus datos.
La pública debe añadirse sin reemplazar la privada. Recoger y extraer su consola
igual que la anterior, usando `--location public` y su ID.

Completar el contraste dentro de los 25 minutos del listener privado. La privada
registra un control loopback de TCP 8080, mantiene el listener 25 minutos y conserva
su SG sin entrada. La pública solo puede intentar ese puerto hacia su IP /32.

Un watchdog de arranque programa el apagado a los 30 minutos. **Apagar no elimina
el volumen ni demuestra desmontaje.** Recoger los resultados antes; el operador
debe retirar las sondas con un plan revisado que ponga ambos flags a `false`.
Confirmar instancias terminadas, volúmenes borrados e IP públicas liberadas.
Si Terraform ya no dispone del estado, inventariar por etiquetas antes de actuar.

## Completar lo que no certifica la sonda

Aplicar la [matriz P01–P23](test-matrix.md) y registrar cada resultado real:

- P03/P08/P09: recuperar v1 por VersionId y la versión actual como operador,
  comparar hashes con `synthetic:RUN_ID:v1\n` y `synthetic:RUN_ID:v2\n`.
  Verificar que ambas versiones siguen presentes tras los intentos de borrado.
- P04/P05/P06/P10/P11: verificar existencia previa de fixtures, ausencia de
  escrituras indebidas y canario intacto, incluyendo versiones y delete markers.
- P12/P13: efectuar GET anónimos HTTP/HTTPS sobre claves sintéticas, sin firma ni
  tokens. Guardar códigos HTTP y políticas desplegadas. Un 403 anónimo no aísla
  por sí solo la denegación de transporte.
- P14: contrastar con lectura privada satisfactoria y configuración real de
  rutas/endpoint. Las dos EC2 tienen sesiones diferentes del mismo rol.
- P15: si aparece el rol canario `cslab-denied-<RUN_ID truncado a 51 caracteres>`,
  marcar fallo; el operador lo elimina tras revisar que está vacío.
- P16: con Allow STS del operador comprobado, intentar `sts assume-role` al rol
  app y guardar el rechazo y su confianza EC2. No modificar la confianza.
- P17: guardar `get-trail-status` antes/después y comparar los atributos del
  trail con `describe-trails`. La sonda manda los valores de `audit.tf`;
  si existe drift, corregirlo o suspender esta prueba antes de lanzar la pública.
- P18/P19/P20: cotejar rutas, SG y DNS, control S3 positivo y listener vivo.
  Comparar el destino IPv4 resuelto de P18 con un control externo a esa misma IP;
  `example.com` puede resolver a direcciones distintas. Los timeouts son
  observaciones de conectividad y necesitan esos controles.

`probe_passed=true` solo resume las subpruebas de una sonda. No completa las
verificaciones del operador ni demuestra permisos efectivos de forma aislada.

## Auditoría, exportación y costes

1. Registrar intervalo UTC, RUN_ID, sesiones e IDs de instancias. Mantener el
   trail activo hasta recibir eventos de datos P01–P03 y administración relevante.
2. Consultar `get-trail-status`, revisar errores de entrega y descargar
   `s3://LOGS/AWSLogs/ACCOUNT/` como operador a `evidence/raw/cloudtrail/`.
   El historial de eventos de CloudTrail no contiene los eventos de datos S3.
3. Correlacionar `eventTime`, `eventName`, identidad/sesión, recurso/clave,
   `requestID`, `eventID`, `errorCode` y `vpcEndpointId` cuando exista.
   Los bloqueos de red/endpoint pueden no aparecer en este trail.
4. Esperar digests del intervalo cerrado; ejecutar y guardar la salida real:

```bash
aws cloudtrail validate-logs --trail-arn "$TRAIL_ARN" \
  --start-time "$START_UTC" --end-time "$END_UTC" --verbose \
  > evidence/raw/digest-validation.txt 2>&1
```

Anotar código de salida y mensajes. Falta de digests o eventos es
`inconclusive`, nunca validación satisfactoria. Un manifiesto de hashes no
sustituye la validación criptográfica de CloudTrail.
[Validación oficial](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-log-file-validation-cli.html).

Generar un manifiesto SHA-256 de la exportación y verificarlo después de copiarla
a almacenamiento externo protegido. Revisar manualmente la copia publicable:
sustituir cuenta, buckets, ARNs, IP, nombres de sesión e identificadores, y excluir
tokens, documentos, cabeceras y salidas `--debug`. Conservar originales y su
manifiesto fuera de Git. El lector de consola **no sanea** los informes.

Registrar gasto observado y volver a consultar facturación después de su
actualización; anotar ventana y retraso de datos. Comparar con la estimación.
No publicar un coste cero basándose en que no aparece todavía un cargo.

## Desmontaje deliberado

1. Retirar ambas sondas con plan revisado y comprobar EC2/EBS/IPv4. No esperar
   al watchdog para detener un ensayo que ya ha fallado.
2. Exportar logs/digests, comprobar manifiesto y registrar qué evidencia se conserva.
3. Revisar `terraform plan -destroy -out=artifacts/destroy.tfplan`. No aplicarlo
   todavía: los buckets versionados no están vacíos y `force_destroy=false`.
4. Cuando la auditoría esté exportada y su pérdida local autorizada, detener el
   trail como operador para evitar nuevas entregas durante el vaciado.
5. Enumerar **todas las páginas** de `list-object-versions` y
   `list-multipart-uploads` para cada bucket. Borrar versiones y marcadores con
   su VersionId explícito; abortar cargas multipart por UploadId. Revisar cada
   lote y los errores por objeto. `aws s3 rm --recursive` no vacía versiones.
6. Comprobar listas vacías, generar de nuevo el plan de destrucción para reflejar
   el estado actual, revisarlo y aplicar el archivo aprobado.
7. Confirmar ausencia de buckets, trail, endpoint, perfil/rol/política app,
   SG, subredes, tablas, IGW y VPC. Revisar también el rol canario P15, volúmenes
   huérfanos, IP y cualquier recurso creado fuera de Terraform. Contrastar con
   inventario previo y etiquetas; `terraform state list` vacío no basta.
8. Registrar recursos retenidos, propietario, motivo, fecha de eliminación y
   coste. Conservar estado final y evidencia de desmontaje fuera de Git.

El vaciado y la destrucción de AWS no están automatizados por el comprobador
local y no se han ejecutado en esta entrega.
