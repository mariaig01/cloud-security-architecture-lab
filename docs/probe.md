# Sondas opcionales de comprobación

El código está implementado en `probes.tf`, `scripts/private_probe.py`,
`scripts/public_probe.py` y `scripts/probe_common.py`. **Solo se ha ejecutado
con mocks locales.** Las dos sondas están desactivadas por defecto.

## Configuración y arranque

La primera fase activa `enable_probes` y exige `probe_ami_id` y `probe_run_id`.
La segunda añade `enable_public_probe`, manteniendo los demás valores. La AMI se
fija por ID y se filtra por propietario Amazon, nombre AL2023 estándar,
arquitectura x86_64, HVM y EBS. El operador comprueba disponibilidad y dependencias.

Ambas EC2 son t3.micro con créditos standard y raíz gp3 de 8 GiB cifrada,
`delete_on_termination=true`, IMDSv2 obligatorio y hop limit 1. Comparten el
perfil app. No hay SSH, key pair, permisos SSM ni instalación de paquetes.

La privada usa únicamente su SG app y no tiene IP pública. La pública se añade
con IP pública explícita y SG sin entrada: salida TCP 443 a internet y TCP 8080
solo a la IP privada /32 de su contraparte. La tabla pública no usa el endpoint S3.
La privada mantiene únicamente salida HTTPS a S3 regional.

`probe_bootstrap.sh.tftpl` integra los tres módulos como base64, se comprime
con gzip y se entrega mediante `user_data_base64`. Una precondición impide
superar 16 KiB comprimidos antes de codificar (límite conservador de 21 844
caracteres base64). No se descarga el código de S3 ni de internet.
[User data EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html),
[formatos cloud-init](https://cloudinit.readthedocs.io/topics/format.html).

La imagen necesita Python 3, AWS CLI v2, cloud-init y certificados ya instalados.
La sonda verifica la versión de CLI y aborta si no es v2. Antes de correr exige
`--execute`, RUN_ID y prefijo seguros; confirma cuenta, región y nombre de rol
mediante IMDSv2, sin leer ni imprimir el contenido de las credenciales.

El entorno hijo de CLI elimina variables AWS, perfiles, proxies y endpoints
alternativos y obtiene la sesión del perfil EC2. Cada llamada S3 exige el
propietario esperado y fija el endpoint HTTPS regional; hay límites de tiempo
y un solo intento. No se imprimen contenidos ni stderr arbitrario: solo códigos
de error reconocidos, hashes e identificadores necesarios para correlación.

## Qué ejecuta cada sonda

| Ubicación | Subpruebas implementadas |
| --- | --- |
| Privada | P01–P11, hash P02, versiones P03, salida P18/P19 y listener P20 |
| Pública | Identidad STS, P10/P11, P14/P15/P17, control externo P18 y conexión P20 |
| Operador | Fixtures, recuperación/comprobaciones finales, P12/P13/P16, correlación y P21–P23 |

Las claves son `PREFIX/probe/RUN_ID/document.txt`,
`restricted/RUN_ID/fixture.txt` y
`probe-fixtures/RUN_ID/audit-canary.txt`. `PREFIX` ya termina en `/`;
no insertar otra barra. Los prefijos de fixtures quedan reservados.

P01 requiere una versión no nula. Si falla, se emite resumen fallido y se
omiten las dependencias. P02 compara bytes y hash; P03 exige una segunda versión
distinta. Recuperar v1, confirmar v2 y comprobar integridad tras los intentos
de borrado sigue siendo trabajo del operador.

La pública valida `sts get-caller-identity` contra cuenta y rol. P15 intenta
crear un rol canario sin políticas; éxito inesperado significa fallo y exige
limpieza del operador. P17 solicita `UpdateTrail` con los valores de `audit.tf`;
no llama a StopLogging ni DeleteTrail. El operador comprueba drift antes y estado
después. Ningún token se transporta al equipo local.

El listener privado de 8080 tiene un control loopback y permanece vivo 25 minutos.
No se abre entrada en su SG. La pública se lanza después de recoger el control
positivo privado y dentro de esa ventana. Si el listener caduca, P20 es
inconcluso aunque la conexión exterior expire.

## Salida y recogida

Cada línea es un JSON con `kind`, `run_id`, `location`, `instance_id` y UTC.
Las operaciones incluyen ID de subprueba, acción, expectativa, resultado,
código de salida y VersionId/ETag cuando existen. El resumen contiene
`passed` y `failed_tests`. No representa el estado completo de la matriz.

El bootstrap usa Python sin buffer y redirige a `/dev/console`. El operador
recoge con `ec2 get-console-output --latest`; no se requiere entrada de red ni
permisos de auditoría para la app. La consola está bufferizada y puede truncarse;
exigir identidad inicial y resumen final, además de todas las subpruebas.

`scripts/read_console.py` es offline: acepta consola plana o JSON de la API,
incluido base64, exige instancia/RUN_ID/ubicación y rechaza mezcla de identidades
y resúmenes contradictorios. Identifica informes incompletos; no marca toda la
matriz como aprobada ni sanea datos para publicación.
[Referencia de consola](https://docs.aws.amazon.com/cli/latest/reference/ec2/get-console-output.html).

`allowed` requiere código cero; `denied` exige error explícito de autorización.
Token caducado, JSON inválido, DNS y timeout son errores, no AccessDenied.
Los bloqueos de red requieren los controles descritos en la
[matriz](test-matrix.md) y en [operación](deployment.md).

## Duración y desmontaje

Al arrancar, el bootstrap programa apagado a los 30 minutos, incluso si el guion
falla. El comportamiento EC2 es `stop`, para permitir recoger evidencias antes
de terminar. Esto limita actividad, **no elimina EBS ni todo el gasto**.

Retirar las sondas mediante plan revisado con ambos flags desactivados y
confirmar instancias terminadas, volúmenes eliminados e IP liberada. No añadir
NAT ni permisos nuevos para resolver un ensayo fallido: revisar AMI, perfil,
DNS, SG, tabla y endpoint. Los costes de solicitudes, versiones, multipart y
logs son independientes de la duración de EC2.
