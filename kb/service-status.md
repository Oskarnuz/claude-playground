---
id: service-status
title: Incidencias y estado del servicio
category: incidencias
sensitive: false
tags: [caído, down, error 500, no carga, lento, incidencia, outage, status]
---

Estado en tiempo real: https://status.example.com publica incidencias activas,
componentes afectados y la hora estimada de resolución.

Si hay una incidencia abierta que coincide con lo que reporta el usuario: no
hace falta ninguna acción por su parte; puede suscribirse a las actualizaciones
en la página de estado. El servicio se restablece automáticamente.

Si NO hay incidencia publicada y el usuario reporta un fallo reproducible
(pasos concretos, mensaje de error, cuándo empezó), se recoge esa información y
se escala a Ingeniería. Un "no funciona" sin detalles no es accionable: pedir
pasos concretos.
