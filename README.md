# MapScout

> *[Versión en español más abajo](#espanol)*

## English

**MapScout** is a light, fast search bar built into the world map. Type a place, a service, a flight path, a quest or coordinates, and MapScout shows you where it is and sets a waypoint.

Any other addon can add its own results and actions to the search through the public API, `MapScoutAPI`.

> MapScout is in development. Bugs and ideas: [GitHub Issues](https://github.com/calderon/mapscout/issues).

### Helping improve MapScout's data

MapScout can help improve its own data while you play. It is **off** until you turn it on, in the options (*Help improve MapScout's data*) or with `/ms contribute on`.

While it is on, MapScout saves on your computer only what its data is still missing, or has in the wrong place:

- where service NPCs are (bank, auction house, innkeeper, stable master, vendors and quartermasters, repairs, barber, guild master, battlemaster, transmogrifier) and trainers, with the skill they teach;
- the places city guards mark on the map when you ask them for directions;
- mailboxes, dungeon and raid entrances, and graveyards;
- your game client's language and a random ID, so the same contribution is not counted twice.

It never saves your character's, account's, realm's or guild's name, your chat, nor when you played. It does nothing while you are in combat, and keeps a limited amount: once MapScout's data includes what you found, it is forgotten.

Nothing leaves your computer unless you send it yourself. To stop: `/ms contribute off` (what was saved is kept). To forget everything saved: `/ms contribute clear`. To see how much is saved: `/ms contribute status`.

To send what you saved: `/ms contribute`, the *Share what you saved* button in the options, or the link in the chat when you log in. A window shows what is new and a text: copy it and paste it in the form the window shows ([in English](https://forms.gle/LZ7aBC4aH2Yb7Kgj8) or [in Spanish](https://forms.gle/SG6tvwH6ovp8QLpD8)), in your browser. Then press *I sent it*, so the same locations are not sent again.

The form is a Google Form: you don't need an account or to sign in, and it asks only for that text. What you send goes to a spreadsheet that only MapScout's author can see; nothing reaches MapScout's data until several players agree on it and it has been reviewed.

While it is on, the chat says when you log in how many new locations you have, with a link to share them, and says each time a new location is saved. To hide those and keep contributing: `/ms contribute messages off`, or the checkbox under it in the options.

### For developers

Any addon can add its own results and actions to MapScout through `MapScoutAPI`. How MapScout is built: [ARCHITECTURE.md](ARCHITECTURE.md).

### Credits

- Dungeon entrances: [DungeonJournal](https://www.curseforge.com/wow/addons/dungeonjournal) by **Exehn**, used with permission. Thank you!

---

<a name="espanol"></a>

## Español

**MapScout** es un buscador ligero y rápido integrado en el mapa del mundo. Escribe un lugar, un servicio, un maestro de vuelo, una misión o unas coordenadas, y MapScout te enseña dónde está y te marca el destino.

Cualquier otro addon puede añadir sus propios resultados y acciones al buscador con la API pública, `MapScoutAPI`.

> MapScout está en desarrollo. Errores e ideas: [GitHub Issues](https://github.com/calderon/mapscout/issues).

### Ayudar a mejorar los datos de MapScout

MapScout puede ayudar a mejorar sus propios datos mientras juegas. Está **apagado** hasta que lo enciendas, en las opciones (*Ayudar a mejorar los datos de MapScout*) o con `/ms contribute on`.

Mientras está encendido, MapScout guarda en tu ordenador solo lo que a sus datos todavía les falta, o tienen en un sitio equivocado:

- dónde están los PNJ de servicio (banco, casa de subastas, tabernero, maestro de establos, vendedores e intendentes, reparaciones, peluquería, maestro de hermandad, maestro de batalla, transfigurador) y los instructores, con la habilidad que enseñan;
- los sitios que marcan en el mapa los guardias de las ciudades cuando les preguntas por algo;
- buzones, entradas de mazmorras y bandas, y cementerios;
- el idioma de tu juego y un identificador al azar, para no contar dos veces la misma contribución.

Nunca guarda el nombre de tu personaje, tu cuenta, tu reino ni tu hermandad, tu chat ni cuándo jugaste. No hace nada mientras estás en combate y guarda una cantidad limitada: cuando los datos de MapScout ya incluyen lo que encontraste, se olvida.

Nada sale de tu ordenador si no lo envías tú. Para parar: `/ms contribute off` (lo guardado se conserva). Para olvidar todo lo guardado: `/ms contribute clear`. Para ver cuánto hay guardado: `/ms contribute status`.

Para enviar lo guardado: `/ms contribute`, el botón *Compartir lo guardado* de las opciones o el enlace del chat al entrar en el juego. Una ventana te enseña lo nuevo y un texto: cópialo y pégalo en el formulario que indica la ventana ([en español](https://forms.gle/SG6tvwH6ovp8QLpD8) o [en inglés](https://forms.gle/LZ7aBC4aH2Yb7Kgj8)), en tu navegador. Después pulsa *Ya lo he enviado*, para no enviar dos veces las mismas ubicaciones.

El formulario es de Google Forms: no necesitas cuenta ni iniciar sesión, y solo te pide ese texto. Lo que envías va a una hoja de cálculo que solo ve el autor de MapScout; nada llega a los datos de MapScout hasta que varios jugadores coinciden y se ha revisado.

Mientras está encendido, el chat te dice al entrar en el juego cuántas ubicaciones nuevas tienes, con un enlace para compartirlas y avisa cada vez que se guarda una ubicación nueva. Para no ver esos avisos y seguir contribuyendo: `/ms contribute messages off`, o la casilla de debajo en las opciones.

### Para desarrolladores

Cualquier addon puede añadir sus propios resultados y acciones a MapScout con `MapScoutAPI`. Cómo está hecho MapScout: [ARCHITECTURE.md](ARCHITECTURE.md) (en inglés).

### Créditos

- Entradas de las mazmorras: [DungeonJournal](https://www.curseforge.com/wow/addons/dungeonjournal), de **Exehn**, con su permiso. ¡Gracias!
