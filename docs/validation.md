# Validación de la entrega local

**Alcance: local, sin despliegue ni pruebas reales en AWS.**

La entrega incluye Terraform de infraestructura y sondas opcionales, políticas
con contratos de seguridad, pruebas de las sondas y lector de consola,
automatización local/CI y documentación de operación, coste y desmontaje.

## Reproducir

Requisitos: Terraform 1.14.9 (fijado en `.terraform-version`), Python 3.9+,
proveedor AWS 6.66.0 según `.terraform.lock.hcl` y red para descargar Terraform
y el proveedor la primera vez. No hacen falta AWS CLI ni credenciales.

```bash
python3 scripts/validate.py
```

Si Terraform está instalado en otra ruta:

```bash
python3 scripts/validate.py --terraform /ruta/al/terraform
```

El comprobador elimina la selección de credenciales AWS de su entorno hijo,
deshabilita IMDS y comprueba que los archivos Terraform de pruebas declaran un
proveedor AWS simulado. No ejecuta un plan o apply real. La inicialización usa
`-backend=false -lockfile=readonly`; no cambia versiones del lockfile.

## Resultados

La comprobación de cierre se registra en `artifacts/local/report.json` y logs
adyacentes (excluidos de Git). Contiene UTC, comandos por nombre, códigos de
salida y SHA-256 de las fuentes comprobadas. La versión y plataforma exactas
figuran en `version.log`.

| Comprobación | Resultado de cierre |
| --- | --- |
| Terraform fmt recursivo | Satisfactorio |
| Inicialización con lockfile de solo lectura | Satisfactoria; proveedor AWS 6.66.0 |
| Terraform validate | Satisfactorio |
| Contratos Terraform con mocks | 14 escenarios aprobados, 0 fallidos |
| Pruebas Python sin red | 20 pruebas aprobadas, 0 fallidas |
| Enlaces Markdown locales | Todos resuelven |
| Bootstrap generado con mocks | Sintaxis Bash correcta y tres módulos idénticos a las fuentes |

La tabla se actualiza con la ejecución final del comprobador, sin inferir
resultados a partir del código. Los artefactos describen las fuentes de esa
ejecución; si cambian, repetir la comprobación.

Comprobado el 13 de noviembre de 2026 con Terraform 1.14.9 y Python 3.12.3. La inicialización
necesitó acceso al registro de HashiCorp fuera del sandbox de red, autorizado
por la usuaria. No se utilizaron credenciales ni se desplegaron recursos AWS.

También se inspeccionó el user data real generado por los dos escenarios de
sondas con mocks: 8 016 bytes comprimidos para la privada y 8 072 para la pública,
por debajo de 16 KiB. Se decodificó/descomprimió, se verificó con `bash -n` y
se compararon los tres módulos empaquetados byte a byte con las fuentes.
Este control inspecciona el transporte del bootstrap; no ejecuta su arranque.

## Qué cubren los contratos

Terraform comprueba permisos exactos del rol y confianza EC2, límites del
endpoint, políticas de ambos buckets, bloqueo público, versionado, SSE-S3,
CloudTrail y selección de eventos. Comprueba subredes/rutas/SG y las sondas
desactivadas por defecto. Los escenarios de sondas revisan perfil compartido,
IMDSv2, EBS cifrado y desechable, salida pública acotada y configuraciones inválidas.

Python ejecuta las sondas con CLI, IMDS y red simulados. Prueba contenido
corrupto, falta de VersionId, permisos inesperados, timeouts, JSON inválido,
selección de credenciales y fallo DNS. El lector rechaza consola truncada,
identidades mezcladas, resumen contradictorio e informes sin subpruebas.

## Límites y resultados pendientes

- Un mock verifica la configuración generada; no evalúa el motor de autorización
  de AWS ni detecta todas las restricciones regionales/de cuenta.
- Las sondas se han probado con simulación. Su arranque real, AMI, entrega de
  consola, conectividad y permisos efectivos siguen pendientes.
- No hay pruebas P01–P23 reales, logs/digests de AWS, factura, despliegue o
  desmontaje que presentar como evidencia.
- El lector solo comprueba estructura y completitud de la consola; no autentica
  al emisor ni sanea los datos para publicación. La matriz exige controles
  independientes del operador y correlación CloudTrail.
- El workflow CI ejecuta el mismo comprobador en
  [GitHub Actions](https://github.com/mariaig01/cloud-security-architecture-lab/actions/workflows/validate.yml).
  Sus resultados se consultan por commit y se distinguen de la comprobación local
  histórica documentada aquí. El repositorio remoto es
  [mariaig01/cloud-security-architecture-lab](https://github.com/mariaig01/cloud-security-architecture-lab).

El resultado cerrado es una entrega local reproducible. Los hitos AWS del
[plan](../PLAN.md) quedan fuera del cierre elegido por la usuaria.
