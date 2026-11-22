# Costes y presupuesto operativo

Esta entrega local no despliega AWS ni necesita una cuenta. No se ha medido
gasto real. Para ejecutar el laboratorio hay que estimar primero en la región
elegida, comprobar precios vigentes y revisar un plan concreto.

## Recursos y duración

| Concepto | Cantidad del diseño | Base de la estimación |
| --- | --- | --- |
| EC2 Linux t3.micro on-demand | Una privada; una pública durante el contraste | Precio regional por hora × horas de cada sonda |
| EBS gp3 cifrado | Dos raíces de 8 GiB mientras existan | GiB-mes × fracción de mes de cada volumen |
| IPv4 pública | Una, solo en la pública | Horas de asignación × tarifa |
| S3 Standard | Documentos sintéticos, versiones, fixtures y logs/digests | GiB-mes, PUT/GET/LIST y transferencia aplicable |
| CloudTrail | Un trail multirregión; datos del bucket de documentos | Eventos de datos y copias de administración aplicables |
| Gateway endpoint S3 | Uno | Sin cargo adicional del endpoint; S3 se factura aparte |
| VPC, subredes, tablas, IGW e IAM | Recursos base | Revisar transferencia; no atribuirles cargos de NAT/PrivateLink |

No hay NAT Gateway, Elastic IP reservada, endpoint de interfaz, RDS, balanceador,
CloudWatch Logs, CloudTrail Lake/Insights ni clave KMS propia. Los créditos CPU
son `standard`, sin modo unlimited. El diseño no depende de créditos Free Tier.

## Cálculo reproducible

Elegir región y registrar fecha, moneda y precio consultado para cada servicio.
Para 30 minutos de privada y 15 minutos de pública:

```text
EC2 = precio_t3_micro_hora × (0.50 + 0.25)
EBS = precio_gp3_GiB_mes × 8 × (0.50 + 0.25) / horas_mes
IPv4 = precio_IPv4_hora × 0.25
S3 = almacenamiento_de_todas_las_versiones + solicitudes + transferencia
Trail = eventos_datos / 100000 × precio_100000_eventos
        + copias_administración_adicionales_aplicables
Total = EC2 + EBS + IPv4 + S3 + Trail + impuestos_aplicables
```

La documentación de VPC publica USD 0.005 por IPv4 pública y hora; con ese
supuesto, 15 minutos son USD 0.00125. No es una estimación del total.
[Precio oficial de IPv4](https://aws.amazon.com/vpc/pricing/).
CloudTrail publica USD 0.10 por 100 000 eventos de datos entregados a S3;
la primera copia de administración tiene condiciones distintas de las copias
adicionales. Comprobar trails existentes antes de duplicar entregas.
[Precio oficial de CloudTrail](https://aws.amazon.com/cloudtrail/pricing/).

No se fija un precio de EC2/EBS/S3 sin una consulta regional. Completar y guardar
la estimación antes de aplicar con la
[calculadora AWS](https://calculator.aws/),
[precios EC2](https://aws.amazon.com/ec2/pricing/on-demand/),
[precios EBS](https://aws.amazon.com/ebs/pricing/) y
[precios S3](https://aws.amazon.com/s3/pricing/).
[Gateway endpoints S3](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html).

## Controles de gasto y cierre

- Fijar un presupuesto y crear alertas; no constituyen un límite de gasto.
- Recoger resultados y retirar EC2 cuanto antes. El watchdog apaga a los 30
  minutos; los volúmenes detenidos siguen facturándose hasta su eliminación.
- Anotar tiempo real de cada instancia, volumen e IP. Revisar etiquetas.
- Una app comprometida puede producir solicitudes, versiones y multipart sin
  límite útil de presupuesto. El guion pequeño no limita a un atacante.
- Versionado y `force_destroy=false` requieren vaciado deliberado de versiones,
  marcadores y multipart. Las evidencias retenidas continúan ocupando espacio.
- Conservar comprobación de desmontaje y revisar facturación cuando se actualice.
  Diferenciar estimación, coste observado provisional y coste final disponible.

Sin ejecución AWS, P23 permanece `not_run`. Los precios anteriores se incluyen
como referencias de cálculo, no como factura, garantía ni coste regional cerrado.
