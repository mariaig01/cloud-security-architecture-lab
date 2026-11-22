# Cloud Security Architecture Lab

Laboratorio de portfolio para puestos junior de Cloud Security y Security
Engineering: aprender AWS y Terraform relacionando amenazas, controles y pruebas.

Repositorio: [mariaig01/cloud-security-architecture-lab](https://github.com/mariaig01/cloud-security-architecture-lab).
Ejecuciones de CI: [Local security contracts](https://github.com/mariaig01/cloud-security-architecture-lab/actions/workflows/validate.yml).

**Estado: entrega local terminada y verificable. No desplegado en AWS.** La aplicación podrá leer y
sobrescribir documentos de `app/documents/`, pero no borrar, listar el bucket,
acceder a otros prefijos, modificar IAM o administrar la auditoría.
Los resultados locales están en [validaciones](docs/validation.md); no prueban
los permisos efectivos ni la conectividad de AWS.

## Inicio local

Requisitos: Terraform `>= 1.7, < 2.0`, Python 3.9+ y conectividad a HashiCorp para
la primera inicialización. Versión utilizada: Terraform 1.14.9, AWS provider
6.66.0. No necesitas AWS CLI, cuenta ni credenciales para las comprobaciones
locales. Instala Terraform desde su [distribución oficial](https://developer.hashicorp.com/terraform/install)
y verifica el checksum del archivo descargado.

Desde la raíz:

```bash
python3 scripts/validate.py
```

Este comando comprueba formato, inicialización con lockfile de solo lectura,
validación, contratos Terraform con mocks, pruebas Python y enlaces locales.
Guarda logs y un informe con hashes de las fuentes en `artifacts/local/`.
También se puede ejecutar cada paso:

```bash
terraform fmt -check -recursive
terraform init -backend=false -input=false -lockfile=readonly
terraform validate
terraform test
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

La versión fijada en `.terraform-version` es 1.14.9. Si el binario no está en
PATH, utiliza `python3 scripts/validate.py --terraform /ruta/al/terraform`.
En este entorno se ha usado `/tmp/cloud-security-tools/terraform` con checksum
oficial verificado, anteponiendo `rtk proxy` según las instrucciones locales.
El binario temporal no forma parte de la entrega. El workflow
`.github/workflows/validate.yml` ejecuta las mismas comprobaciones sin secretos
en GitHub; sus resultados se consultan en el enlace de CI anterior.

`terraform test` utiliza exclusivamente `mock_provider "aws"`. Su ejecución
`command = apply` aplica al proveedor **simulado**, sin crear recursos de AWS.
Las políticas probadas son los JSON generados por esta configuración, no textos
simulados. No añadas un proveedor real a esas pruebas. `init -backend=false`
solo omite inicializar un backend: **no convierte `plan` o `apply` en offline**.

El archivo `.terraform.lock.hcl` fija el proveedor resuelto y sus hashes; debe
versionarse. No ejecutes `init -upgrade` sin revisar el cambio y repetir las
pruebas. El estado futuro será local: mantenlo fuera de Git, respaldado y en un
disco cifrado. Este laboratorio no crea backend remoto.

## Qué contiene

| Componente | Función |
| --- | --- |
| Terraform en la raíz | VPC, rutas, endpoint, SG, buckets, IAM, CloudTrail y EC2 opcionales |
| `tests/` | Contratos de seguridad con mocks y pruebas del guion de la sonda |
| `scripts/private_probe.py` / `public_probe.py` | Sondas para ambas ubicaciones; requieren `--execute` en EC2 |
| `scripts/read_console.py` | Comprueba informes de consola sin conectar a AWS; no certifica toda la matriz |
| `scripts/validate.py` | Comprobador local reproducible y usado por CI |
| [PLAN.md](PLAN.md) | Tres hitos con criterios de aceptación y estado |
| [Explicación del proyecto](docs/explicacion-proyecto.md) | Objetivo, arquitectura e implementación explicados paso a paso |
| [Arquitectura](docs/architecture.md) | Diagrama Mermaid y decisiones |
| [Amenazas](docs/threat-model.md) | Límites del atacante y riesgo residual |
| [Matriz](docs/test-matrix.md) | Operación, identidad, recurso, expectativa y evidencia pendiente |
| [Sondas](docs/probe.md) | Carga mínima y dependencias para el segundo hito |
| [Operación](docs/deployment.md) | Preparación, revisión, despliegue y desmontaje |
| [Costes](docs/costs.md) | Recursos facturables y supuestos para estimar |

## Configuración futura

Copia `terraform.tfvars.example` a `terraform.tfvars` y cambia la cuenta y los
dos nombres globalmente únicos. El ejemplo es ficticio. `document_prefix` termina
en `/` y no acepta comodines. La VPC usa un `/16`; se derivan dos `/24` distintos.
La región por defecto es `eu-west-1`, con AZ `<region>a` modificable. Este diseño
usa la partición comercial `aws`, no GovCloud ni China. AWS verifica además la
disponibilidad de la región/AZ y las restricciones reservadas de nombres de S3.

Los outputs agrupan `network`, `storage`, `application` y `audit`. `allowed_account_ids`
impide usar accidentalmente otra cuenta en operaciones reales. El proveedor
usará la cadena estándar de credenciales, por ejemplo `AWS_PROFILE` con AWS IAM
Identity Center. No incluyas claves en variables, código, chat o evidencias.

Las sondas están implementadas y desactivadas por defecto. `enable_probes=true`
requiere AMI regional fijada y `probe_run_id`; `enable_public_probe=true` añade
la comparación pública después del control positivo privado. No actives estos
flags en la entrega local. Los fixtures negativos reservan `restricted/` y
`probe-fixtures/`, que no pueden ser el inicio de `document_prefix`.

Una ejecución futura en AWS necesita CLI v2, un perfil temporal del operador, una
cuenta de laboratorio, revisión del plan y estimación de costes **antes del
despliegue**. No se presupone gratuidad y una alerta de presupuesto no limita el
gasto. Consulta [la guía de operación](docs/deployment.md).

## Qué demuestra el diseño y qué falta demostrar

IAM decide qué acciones puede realizar una identidad. Las rutas y los security
groups deciden qué tráfico tiene camino y autorización de red. La política del
endpoint añade autorización sobre las solicitudes que lo atraviesan; la política
del bucket puede exigir ese origen. **Crear subredes no demuestra aislamiento.**

Se permite sobrescribir, según la decisión del proyecto. Versionado facilita que
el operador recupere una versión anterior; las credenciales comprometidas aún
pueden leer datos permitidos, escribir contenido falso y generar costes. Los logs
están protegidos frente al rol de aplicación, no frente a un administrador de
cuenta comprometido. Las pruebas reales y la recogida de CloudTrail pertenecen a
los hitos 2 y 3; no hay evidencias de AWS publicadas todavía.
