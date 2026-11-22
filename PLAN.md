# Cloud Security Architecture Lab — cierre local

**Entrega local terminada.** Por decisión de la usuaria, el alcance cerrado es
código, documentación y comprobaciones reproducibles, sin despliegue en AWS.
Los resultados locales están en [validación](docs/validation.md).

## Hito 1 — entrega local

- [x] Terraform de red, almacenamiento, IAM, CloudTrail, variables y outputs.
- [x] Versiones restringidas, lockfile y exclusiones de estado, planes y credenciales.
- [x] Arquitectura Mermaid, amenazas y matriz de pruebas.
- [x] Sondas privada/pública implementadas, opcionales y desactivadas por defecto.
- [x] Bootstrap sin descargas, IMDSv2, raíz cifrada y watchdog de apagado.
- [x] Lector de consola que comprueba identidad, resumen y subpruebas.
- [x] Guía de preparación, despliegue, auditoría, exportación y desmontaje.
- [x] Modelo de costes con fuentes oficiales y supuestos explícitos.
- [x] Contratos Terraform con mocks y pruebas Python sin red.
- [x] Comprobador local único, logs, hashes de fuentes y workflow CI.
- [x] Formato, inicialización, validación, pruebas y enlaces comprobados.
- [x] README y registro de resultados y limitaciones.

Aceptación: comprobaciones locales satisfactorias sobre las fuentes finales.
Esta aceptación no atribuye al proyecto permisos o conectividad demostrados en AWS.

## Hito 2 — ejecución AWS futura, fuera del cierre local

Preparación técnica realizada: Terraform de ambas sondas y guiones ejecutables.

- [ ] Seleccionar cuenta de laboratorio, perfil temporal, región y nombres únicos.
- [ ] Verificar y fijar AMI regional y preparar fixtures con RUN_ID único.
- [ ] Estimar gasto y revisar/autorizar planes guardados antes de cada apply.
- [ ] Ejecutar las sondas por fases y completar controles del operador P01–P20.
- [ ] Recoger consolas completas y distinguir autorización de conectividad.
- [ ] Retirar sondas y verificar eliminación de volúmenes e IPv4.

Aceptación futura: operaciones permitidas/denegadas con evidencias reales;
ausencias, fallos y pruebas no concluyentes identificados.

## Hito 3 — auditoría y cierre AWS futuro, fuera del cierre local

- [ ] Correlacionar eventos CloudTrail y verificar digests del intervalo.
- [ ] Exportar, verificar y sanear evidencias publicables.
- [ ] Contrastar coste observado con estimación y retraso de facturación.
- [ ] Vaciar versiones, marcadores y multipart; destruir infraestructura.
- [ ] Comprobar inventario final y documentar toda retención y coste.
- [ ] Publicar resultados reales y aprendizajes sin sustituirlos por expectativas.

Aceptación futura: amenaza → control → prueba → evidencia trazable y desmontaje
verificado, o retención deliberada inventariada. P01–P23 permanecen pendientes.
