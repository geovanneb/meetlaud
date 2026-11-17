# Privacidad

[English](PRIVACY.md) · [日本語](PRIVACY.ja.md) · [Português](PRIVACY.pt-BR.md) · Español

Vigente desde el 17 de noviembre de 2026. Esta política cubre la app Meetlaud para iPhone, iPad y Android, incluida la app de Android en Google Play, publicada allí con el nombre de desarrollador NovaAppsBR.

Esta página explica con palabras sencillas lo que hace el código, en la app de iPhone y en la de Android. La propia compilación garantiza la mayor parte: mira `ios/Tools/check-privacy` y `Tools/check-android`, y las listas `ios/Tools/privacy-allowlist.json` y `android/privacy-allowlist.json`. Si esta traducción y la [versión en inglés](PRIVACY.md) no coinciden, vale la versión en inglés.

## Qué sale de tu dispositivo

Nada de lo que grabas, escribes o preguntas. La grabación, la transcripción, la identificación de quién habla, los resúmenes y las conversaciones funcionan en el dispositivo.

La app hace dos tipos de conexión. La segunda es opcional y está apagada hasta que la configures.

1. **Descargas de modelos de IA que tú inicias.** Vienen de Hugging Face, en versiones fijas y con hash verificado. Ajustes > Actividad de red muestra cada una, con la fecha, el servidor y el tamaño. Puedes borrar esa lista; después, la pantalla indica que el historial se borró, en lugar de decir que nada salió.

En el iPhone, iOS puede descargar sus propios modelos de idioma para Apple Speech y para la búsqueda. Eso lo hace iOS, no la app, y no incluye nada de tus reuniones. Android no tiene esos modelos, así que la app de Android descarga su propio modelo de búsqueda, como los demás.

2. **Conectores que emparejas.** Si conectas Get Things Done, las nuevas reuniones van a ese único ordenador, en tu propia red, cifradas para él. Por defecto solo se envía el audio. Las transcripciones y las fotos tienen cada una su propio interruptor. Nada pasa por internet, y cada envío aparece en Actividad de red.

## Lo que la app no tiene

Ni cuentas. Ni analítica. Ni servicio de informes de fallos. Ni publicidad. Ni servidor.

## Qué se queda en el dispositivo, y dónde

| Datos | Dónde | ¿En la copia de seguridad del dispositivo? |
|---|---|---|
| Grabaciones, transcripciones, resúmenes, conversaciones, memoria, huellas de voz | Almacenamiento privado de la app | No, salvo que lo actives en Almacenamiento y copia de seguridad |
| Modelos de IA | Almacenamiento privado de la app | Nunca |
| Próximo evento y nombres de reuniones recientes | Un archivo compartido con el widget de la app | No. Solo se escribe si activas "Mostrar nombres de reuniones en los widgets", y se borra al desactivarlo |

Si activas la copia de seguridad, tus grabaciones siguen los ajustes de copia de tu teléfono, lo que puede incluir iCloud en el iPhone o la copia de Google en Android.

## Tus controles

- **Bloquear la app:** pide Face ID, la huella o el bloqueo de pantalla, y oculta el contenido en el selector de apps.
- **Exportar la biblioteca:** un único archivo protegido con tu contraseña (AES-256-GCM). Sin la contraseña nadie puede abrirlo, y no se puede recuperar. Las huellas de voz quedan fuera salvo que las incluyas.
- **Borrar una grabación:** elimina su audio, la transcripción, los resúmenes, los datos de búsqueda, las conversaciones sobre ella y cualquier respuesta que la cite.
- **Borrar todo:** elimina todo lo anterior, además de los modelos y los ajustes. En el iPhone, los modelos de idioma de iOS se quedan, porque pertenecen a iOS.

## Huellas de voz

Las huellas de voz son datos biométricos. Son opcionales, necesitan tu consentimiento para cada persona y se pueden borrar en Personas.

## Grabar a otras personas

Grabar a otras personas puede requerir su consentimiento, según dónde estés. Es tu responsabilidad, y la app te lo recuerda antes de tu primera grabación.

## Los límites, con honestidad

- La IA puede equivocarse. Los resúmenes y las respuestas enlazan con sus fuentes para que las compruebes.
- Quien pueda desbloquear tu teléfono puede abrir la app, salvo que actives el bloqueo de la app.

## Descargas de modelos y Hugging Face

Descargar un modelo es una solicitud web común a Hugging Face. Por eso, como con cualquier sitio web, Hugging Face ve tu dirección IP y el archivo solicitado. La app no envía nada más: ninguna cuenta, ningún identificador y nada de tus reuniones. La política de privacidad de Hugging Face cubre lo que hace con los registros de sus servidores.

## Para qué sirve cada permiso en Android

| Permiso | Por qué |
|---|---|
| Micrófono | Para grabar, solo mientras grabas |
| Notificaciones | Los controles de la grabación y, si los activas, recordatorios y transcripciones listas |
| Calendario (lectura) | Opcional. Muestra las próximas reuniones y nombra las grabaciones según ellas, en el dispositivo |
| Biometría | Opcional. El bloqueo de la app |
| Internet y estado de la red | Descargas de modelos y el ordenador que emparejes (ver arriba) |
| Servicios en primer plano | Seguir grabando, transcribiendo y descargando con la pantalla apagada |

## Cuánto tiempo se guardan los datos

Todo se queda en tu dispositivo hasta que lo borres: una grabación, la papelera o todo a la vez con Borrar todo. Desinstalar la app también lo borra, salvo alguna copia en una copia de seguridad del dispositivo que hayas activado. Nadie más tiene una copia, así que nadie puede borrar ni recuperar nada por ti.

## Niños

Meetlaud no está hecha para niños y no recopila nada de nadie a propósito, ya que no recopila nada.

## Cambios y contacto

Cualquier cambio en esta política se hace en este archivo, con todo su historial en el repositorio, y la fecha de arriba cambia con él. Las preguntas son bienvenidas en las [discusiones del repositorio](https://github.com/geovanneb/meetlaud/discussions). Para un problema de privacidad o seguridad, usa el reporte privado descrito en [SECURITY.md](../SECURITY.md).
