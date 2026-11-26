-- MapScout: textos en español (esES y esMX).
-- Solo los textos traducidos: lo que falte sale en inglés (Locales/enUS.lua).

local _, ns = ...

local locale = GetLocale()
if locale ~= "esES" and locale ~= "esMX" then
	return
end

local L = ns.L

-- Comandos
L.HELP_TITLE = "comandos (/mapscout o /ms):"
L.HELP_HELP = "esta lista"
L.HELP_VERSION = "muestra la versión"
L.HELP_DEBUG = "comprobaciones para desarrolladores (/ms debug para la lista)"
L.HELP_DIAG = "muestra la versión del juego y lo que puede hacer este cliente"
L.VERSION = "versión %s"
L.DEBUG_TITLE = "comprobaciones:"

-- /ms diag
L.DIAG_HEADER = "versión %s · WoW %s · %s · %s"
L.DIAG_MEMORY = "memoria de %s: %s"
L.DIAG_PACK_NONE = "no hay paquete de datos para este juego"
L.DIAG_PACK_NOT_LOADED = "sin cargar (ninguna categoría lo ha necesitado)"
L.DIAG_PACK_FAILED = "no se ha podido cargar (%s)"
L.DIAG_PACK_BUILT = "datos preparados: %s"
L.YES = "sí"
L.NO = "no"

-- Datos guardados
L.DB_ACCOUNT = "la cuenta"
L.DB_CHARACTER = "el personaje"
L.DB_NEWER = "tus datos guardados de %s vienen de un MapScout más nuevo. No se tocan, y los cambios que hagas ahora no se guardarán."
L.DB_FAILED = "tus datos guardados de %s no se han podido actualizar (%s). No se tocan, y los cambios que hagas ahora no se guardarán."
L.DB_NOT_LOADED = "los datos guardados aún no se han cargado"
L.DB_STATE_new = "nuevos"
L.DB_STATE_current = "al día"
L.DB_STATE_upgraded = "actualizados"
L.DB_STATE_newer = "de una versión más nueva"
L.DB_STATE_failed = "con error"
L.DB_REPORT = "datos guardados: esquema %d (actual %d), cuenta %s, personaje %s"
L.DB_REPORT_ACCOUNT = "  cuenta: %d alias, %d ocultos, %d favoritos, %d en frecuencia, máximo de resultados %d"
L.DB_REPORT_CHARACTER = "  personaje: %d búsquedas recientes, %d rutas de vuelo conocidas"
L.DEBUG_DB = "datos guardados: esquema, estado y tamaños"
L.DEBUG_API = "API pública: versión, estado y funciones"
L.DEBUG_API_RESULT = "MapScoutAPI versión %d, lista: %s, %d llamadas en espera, funciones: %s"
L.DEBUG_PROVIDERS = "proveedores de búsqueda: estado, entradas y errores"
L.DEBUG_PROVIDERS_NONE = "no hay proveedores de búsqueda registrados"
L.DEBUG_PROVIDERS_TITLE = "%d proveedores de búsqueda:"
L.DEBUG_PROVIDERS_LINE = "  %s (%s): %s, %d entradas, %d errores, filtros %s"

-- Barra de búsqueda
L.SEARCH_PLACEHOLDER = "Buscar en el mapa"
L.SETTINGS = "Opciones de MapScout"

-- Resultados
L.RESULTS_IN_ZONE = "En %s"
L.RESULTS_ELSEWHERE = "En el resto del mundo"
L.RESULTS_NO_PLACE = "Lugar desconocido"
L.RESULTS_NONE = "No hay resultados"
L.RESULTS_HINT = "Prueba con @ o con coordenadas (45 67)"
L.RESULTS_WIDENED = "Nada en %s; resultados en todo %s"
L.RESULTS_DISABLED = "%s: desactivado en las opciones (/ms)"

-- Vista previa
L.PREVIEW_DISTANCE = "a %s"

-- Ir a un resultado
L.WAYPOINT_NOT_POSSIBLE = "el juego no permite poner un punto de destino para %s aquí; el mapa te enseña dónde está."

-- Lugares (proveedor de geografía)
L.GEOGRAPHY_NAME = "Lugares"
L.GEOGRAPHY_DESCRIPTION = "Continentes, ciudades, zonas y campos de batalla del mapa del mundo"
L.GEOGRAPHY_CONTINENTS = "Continentes"
L.GEOGRAPHY_CITIES = "Ciudades"
L.GEOGRAPHY_ZONES = "Zonas"
L.GEOGRAPHY_OTHERS = "Campos de batalla y otros"

-- Coordenadas
L.COORDS_GO = "Ir a %s"
L.COORDS_GO_IN = "Ir a %s en %s"
L.COORDS_SUBTITLE = "Coordenadas"

-- Maestros de vuelo
L.DUNGEONS_NAME = "Mazmorras y bandas"
L.DUNGEONS_DESCRIPTION = "Entradas de mazmorras y bandas"
L.DUNGEONS_DUNGEONS = "Mazmorras"
L.DUNGEONS_RAIDS = "Bandas"
L.DUNGEONS_DUNGEON = "Mazmorra"
L.DUNGEONS_RAID = "Banda"
L.DUNGEONS_SUBTITLE = "%s · nivel %d"
L.DUNGEONS_PENDING = "%s · entrada por confirmar"
L.DUNGEONS_NO_ENTRANCE = "MapScout aún no sabe dónde está su entrada: la mostrará cuando se haya comprobado en el juego."
L.DEBUG_DUNGEONS = "entradas de mazmorras y bandas y el mapa donde se coloca cada una"
L.DEBUG_DUNGEONS_RESULT = "%d entradas (paquete de datos: %s):"
L.FLIGHTS_NAME = "Maestros de vuelo"
L.FLIGHTS_DESCRIPTION = "Maestros de vuelo de tu facción y neutrales"
L.FLIGHTS_SUBTITLE = "Maestro de vuelo"
L.FLIGHTS_SUBTITLE_UNKNOWN = "Maestro de vuelo · aún desconocido"
L.FLIGHTS_HOW_TO_LEARN = "Abre una vez el mapa de vuelo de cualquier maestro de vuelo para que MapScout sepa cuáles conoce este personaje."
L.DEBUG_FLIGHTS = "maestros de vuelo y el mapa donde se coloca cada uno"
L.DEBUG_FLIGHTS_RESULT = "%d maestros de vuelo (%d conocidos) para %s:"

-- Misiones
L.QUESTS_NAME = "En tu registro"
L.GROUP_QUESTS = "Misiones"
L.QUESTS_DESCRIPTION = "Las misiones de tu registro, dónde hacerlas o entregarlas"
L.QUESTS_READY = "Lista para entregar"
L.QUESTS_ONGOING = "En curso"
L.QUESTS_SUBTITLE = "Nivel %d · %s"
L.QUESTS_NO_PLACE = "El juego no indica en el mapa dónde está esta misión."

-- Misiones disponibles (QuestieDB)
L.AVAILABLE_NAME = "Disponibles"
L.AVAILABLE_DESCRIPTION = "Misiones que puedes coger ahora, de QuestieDB"
L.AVAILABLE_SUBTITLE = "Disponible · Nivel %d · %s"
L.AVAILABLE_GIVER = "La da: %s"
L.DEBUG_QUESTIE = "misiones disponibles de QuestieDB"
L.DEBUG_QUESTIE_RESULT = "QuestieDB contrato %d: %d misiones, %d disponibles ahora (%d sin sitio conocido), creado en %.0f ms"

-- Servicios (QuestieDB)
L.SERVICES_NAME = "Servicios"
L.SERVICES_DESCRIPTION = "Bancos, posadas, instructores y otros servicios, de QuestieDB"
L.SERVICE_bank = "Banco"
L.SERVICE_auction = "Casa de subastas"
L.SERVICE_inn = "Posada"
L.SERVICE_stable = "Maestro de establos"
L.SERVICE_trainer = "Instructor"
L.SERVICE_repair = "Reparaciones"
L.SERVICE_battle = "Maestro de batalla"
L.SERVICE_guild = "Hermandad"
L.SERVICE_vendor = "Vendedor"
L.DEBUG_SERVICES = "servicios de QuestieDB"
L.DEBUG_SERVICES_RESULT = "QuestieDB: %d PNJ, %d servicios, creado en %.0f ms"

-- Página de opciones
L.OPTIONS_ABOUT = "Un buscador en el mapa del mundo. Escribe un lugar, un servicio, una misión o unas coordenadas; con @ eliges qué buscar (@zona, @banco, @mision...)."
L.OPTIONS_AFTER_COMBAT = "las opciones se abrirán al terminar el combate."
L.OPTIONS_CATEGORIES_TITLE = "Qué buscar"
L.OPTIONS_CATEGORIES_HELP = "Lo que desactives no se carga ni ocupa memoria. Desactivar un tipo (Banco, Posada...) solo lo quita de los resultados."
L.OPTIONS_RESET = "Valores por defecto"

-- Proveedores de búsqueda
L.PROVIDER_FAILED = "la fuente de búsqueda «%s» ha fallado %d veces y queda desactivada hasta que recargues la interfaz."
L.PROVIDER_STATE_ON = "activado"
L.PROVIDER_STATE_OFF = "desactivado"
L.PROVIDER_STATE_FAILED = "desactivado por errores"
L.DEBUG_QUERY = "cómo se lee una búsqueda: /ms debug query <texto>"
L.DEBUG_QUERY_RESULT = "filtros: %s · coordenadas: %s · zona: %s · texto: «%s»"
L.DEBUG_SEARCH = "buscar sin el mapa: /ms debug search <texto>"
L.DEBUG_SEARCH_TITLE = "«%s»: %d resultados"
L.DEBUG_BENCH = "medir una búsqueda: /ms debug bench <texto>"
L.DEBUG_BENCH_RESULT = "«%s»: %.2f ms, %d candidatos, %d resultados, erratas: %s · escrito letra a letra (%d búsquedas): %.2f ms, la más lenta %.2f ms · índice: %d proveedores, %d entradas, creado en %.2f ms"
L.DEBUG_MAP = "la capa del mapa del mundo: /ms debug map [outline]"
L.DEBUG_MAP_NOT_READY = "la capa del mapa del mundo aún no está lista"
L.DEBUG_MAP_RESULT = "mapa %s (%s), abierto: %s, capa %.0f x %.0f, en combate: %s"
L.DEBUG_BAR = "la barra de búsqueda del mapa: /ms debug bar [live]"
L.DEBUG_BAR_LIVE = "barra: «%s» -> %d resultados en %.2f ms"
L.DEBUG_BAR_LIVE_ON = "cada búsqueda de la barra saldrá en el chat (/ms debug bar live para dejarlo)"
L.DEBUG_BAR_LIVE_OFF = "las búsquedas de la barra ya no salen en el chat"
L.DEBUG_BAR_NOTHING = "la barra aún no ha buscado nada"
L.DEBUG_SAMPLE = "lugares de prueba (solo desarrollo): /ms debug sample [big]"
L.DEBUG_SAMPLE_ON = "proveedor de prueba activado: %d lugares (/ms debug sample otra vez para quitarlo, @sample para verlos)"
L.DEBUG_SAMPLE_OFF = "proveedor de prueba quitado"
L.DEBUG_NORMALIZE = "cómo se busca un texto: /ms debug normalize <texto>"
L.DEBUG_NORMALIZE_RESULT = "«%s» se busca como «%s»"

-- Teclas (ns.KeyName)
L.KEY_ALT_MAC = "Opción"

-- Palabras de búsqueda en español (además de las inglesas, que siempre funcionan).
-- Cada proveedor añade las suyas (p. ej. ns.W.FILTER_FLIGHTS = { "vuelos", "vuelo" }).
-- Singular primero (la que se enseña), sin acentos (con acento también
-- funcionan: se comparan sin acentos); los plurales también funcionan
ns.W.GEOGRAPHY = { "lugar", "region", "mapa", "lugares", "regiones", "mapas" }
ns.W.CONTINENTS = { "continente", "continentes" }
ns.W.CITIES = { "ciudad", "capital", "ciudades", "capitales" }
ns.W.ZONES = { "zona", "zonas" }
ns.W.OTHERS = { "campo", "area", "campos", "areas" }
ns.W.INSTANCES = { "instancia", "instancias" }
ns.W.DUNGEONS = { "mazmorra", "mazmorras" }
ns.W.RAIDS = { "banda", "bandas" }
ns.W.DUNGEON = { "mazmorra" }
ns.W.RAID = { "banda" }
ns.W.FLIGHTS = { "vuelo", "volar", "vuelos" }
ns.W.FLIGHT_MASTER = { "maestro de vuelo" }
ns.W.QUESTS = { "mision", "misiones" }
ns.W.QUEST = { "mision" }
ns.W.QUEST_LOG = { "registro" }
ns.W.AVAILABLE = { "disponible", "disponibles" }
ns.W.SERVICES = { "servicio", "servicios" }
ns.W.BANK = { "banco", "banquero", "bancos" }
ns.W.AUCTION = { "subasta", "subastador", "subastas" }
ns.W.INN = { "posada", "posadero", "tabernero", "taberna", "posadas" }
ns.W.STABLE = { "establo", "establos" }
ns.W.TRAINER = { "instructor", "instructores" }
ns.W.REPAIR = { "reparar", "reparacion" }
ns.W.BATTLEMASTER = { "batalla", "maestro de batalla" }
ns.W.GUILD = { "hermandad", "tabardo" }
ns.W.VENDOR = { "vendedor", "tienda", "mercader", "vendedores" }
