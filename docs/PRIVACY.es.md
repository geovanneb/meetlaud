# Privacidad

[English](PRIVACY.md) · [日本語](PRIVACY.ja.md) · [Português](PRIVACY.pt-BR.md) · Español

Esta página explica con palabras sencillas lo que hace el código. La propia compilación garantiza la mayor parte: mira `Tools/check-privacy` y `Tools/privacy-allowlist.json`. Si esta traducción y la [versión en inglés](PRIVACY.md) no coinciden, vale la versión en inglés.

## Qué sale de tu dispositivo

Nada de lo que grabas, escribes o preguntas. La grabación, la transcripción, la identificación de quién habla, los resúmenes y las conversaciones funcionan en el dispositivo.

La app hace dos tipos de conexión. La segunda es opcional y está apagada hasta que la configures.

1. **Descargas de modelos de IA que tú inicias.** Vienen de Hugging Face, en versiones fijas y con hash verificado. Ajustes > Actividad de red muestra cada una, con la fecha, el servidor y el tamaño. Puedes borrar esa lista; después, la pantalla indica que el historial se borró, en lugar de decir que nada salió.

iOS puede descargar sus propios modelos de idioma para Apple Speech y para la búsqueda. Eso lo hace iOS, no la app, y no incluye nada de tus reuniones.

2. **Conectores que emparejas.** Si conectas Get Things Done, las nuevas reuniones van a ese único ordenador, en tu propia red, cifradas para él. Por defecto solo se envía el audio. Las transcripciones y las fotos tienen cada una su propio interruptor. Nada pasa por internet, y cada envío aparece en Actividad de red.

## Lo que la app no tiene

Ni cuentas. Ni analítica. Ni servicio de informes de fallos. Ni publicidad. Ni servidor.

## Qué se queda en el dispositivo, y dónde

| Datos | Dónde | ¿En la copia de seguridad de iOS? |
|---|---|---|
| Grabaciones, transcripciones, resúmenes, conversaciones, memoria, huellas de voz | Almacenamiento privado de la app | No, salvo que lo actives en Almacenamiento y copia de seguridad |
| Modelos de IA | Almacenamiento privado de la app | Nunca |
| Próximo evento y nombres de reuniones recientes | Un archivo compartido con el widget de la app | No. Solo se escribe si activas "Mostrar nombres de reuniones en los widgets", y se borra al desactivarlo |

Si activas la copia de seguridad, tus grabaciones siguen los ajustes de copia de tu iPhone, lo que puede incluir iCloud.

## Tus controles

- **Bloquear la app:** pide Face ID o el código, y oculta el contenido en el selector de apps.
- **Exportar la biblioteca:** un único archivo protegido con tu contraseña (AES-256-GCM). Sin la contraseña nadie puede abrirlo, y no se puede recuperar. Las huellas de voz quedan fuera salvo que las incluyas.
- **Borrar una grabación:** elimina su audio, la transcripción, los resúmenes, los datos de búsqueda, las conversaciones sobre ella y cualquier respuesta que la cite.
- **Borrar todo:** elimina todo lo anterior, además de los modelos y los ajustes. Los modelos de idioma de iOS se quedan, porque pertenecen a iOS.

## Huellas de voz

Las huellas de voz son datos biométricos. Son opcionales, necesitan tu consentimiento para cada persona y se pueden borrar en Personas.

## Grabar a otras personas

Grabar a otras personas puede requerir su consentimiento, según dónde estés. Es tu responsabilidad, y la app te lo recuerda antes de tu primera grabación.

## Los límites, con honestidad

- La IA puede equivocarse. Los resúmenes y las respuestas enlazan con sus fuentes para que las compruebes.
- Quien pueda desbloquear tu teléfono puede abrir la app, salvo que actives el bloqueo de la app.
