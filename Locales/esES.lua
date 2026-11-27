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
L.GEOGRAPHY_TOWNS = "Pueblos y campamentos"
L.GEOGRAPHY_SUBZONES = "Lugares con nombre"
L.GEOGRAPHY_TOWN = "Pueblo"
L.GEOGRAPHY_SUBZONE = "Lugar"

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
L.DUNGEONS_WITH_WING = "%s (%s)"
L.DUNGEONS_WING_LIBRARY = "Biblioteca"
L.DUNGEONS_WING_ARMORY = "Armería"
L.DUNGEONS_WING_CATHEDRAL = "Catedral"
L.DUNGEONS_WING_GRAVEYARD = "Cementerio"
L.DUNGEONS_WING_MAIN = "Puerta principal"
L.DUNGEONS_WING_SERVICE = "Puerta de servicio"
L.DUNGEONS_WING_EAST = "Este"
L.DUNGEONS_WING_WEST = "Oeste"
L.DUNGEONS_WING_NORTH = "Norte"
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
L.TRANSPORT_NAME = "Barcos, zepelines y tranvías"
L.TRANSPORT_DESCRIPTION = "Muelles y estaciones, por dónde están y adónde van"
L.TRANSPORT_BOATS = "Barcos"
L.TRANSPORT_ZEPPELINS = "Zepelines y aeronaves"
L.TRANSPORT_TRAMS = "Tranvías"
L.TRANSPORT_BOAT_TO = "Barco a %s"
L.TRANSPORT_ZEPPELIN_TO = "Zepelín a %s"
L.TRANSPORT_SKYSHIP_TO = "Aeronave a %s"
L.TRANSPORT_TRAM_TO = "Tranvía a %s"
L.DEBUG_TRANSPORT = "muelles de barcos, zepelines y tranvías y el mapa donde se coloca cada uno"
L.DEBUG_TRANSPORT_RESULT = "%d muelles (paquete de datos: %s):"

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
L.AVAILABLE_STARTS_AT = "Empieza en: %s"
L.AVAILABLE_HAND_IN = "Se entrega a: %s"
L.AVAILABLE_REQUIRES = "Requiere nivel %d"
L.AVAILABLE_SHOW_HIGHLEVEL = "Mostrar misiones de nivel alto"
L.AVAILABLE_SHOW_HIGHLEVEL_TIP = "También las de más de 10 niveles por encima del tuyo, y las que aún no puedes coger."
L.AVAILABLE_SHOW_LOWLEVEL = "Mostrar misiones de nivel bajo (grises)"
L.AVAILABLE_SHOW_LOWLEVEL_TIP = "Misiones tan por debajo de tu nivel que apenas dan experiencia."
L.AVAILABLE_SHOW_SEASONAL = "Mostrar misiones de temporada"
L.AVAILABLE_SHOW_SEASONAL_TIP = "Misiones de festividades, solo mientras dura la fiesta (cuando el calendario del juego lo dice)."
L.AVAILABLE_SHOW_REPEATABLE = "Mostrar misiones repetibles"
L.AVAILABLE_SHOW_REPEATABLE_TIP = "Misiones que se pueden hacer una y otra vez: esfuerzo de guerra, entregas de reputación..."
L.DEBUG_QUESTIE = "misiones disponibles de QuestieDB"
L.DEBUG_QUESTIE_RESULT = "QuestieDB contrato %d: %d misiones, %d disponibles ahora (%d sin sitio conocido), creado en %.0f ms"

-- Servicios (QuestieDB)
L.SERVICES_NAME = "Servicios"
L.SERVICES_DESCRIPTION = "Bancos, casas de subastas, posadas, buzones, maestros de establos, reparaciones, peluquerías, transfiguradores, maestros de hermandad, maestros de batalla, yunques y forjas en las ciudades"
L.DEBUG_SERVICES = "servicios de las ciudades"
L.DEBUG_SERVICES_RESULT = "%d servicios (paquete de datos: %s)"
L.QUESTIE_SERVICES_NAME = "Servicios (QuestieDB)"
L.QUESTIE_SERVICES_DESCRIPTION = "Bancos, posadas, instructores y otros servicios, de QuestieDB, donde MapScout aún no tiene"
L.SERVICE_mailbox = "Buzón"
L.SERVICE_bank = "Banco"
L.SERVICE_auction = "Casa de subastas"
L.SERVICE_inn = "Posada"
L.SERVICE_stable = "Maestro de establos"
L.SERVICE_trainer = "Instructor"
L.SERVICE_repair = "Reparaciones"
L.SERVICE_battle = "Maestro de batalla"
L.SERVICE_guild = "Hermandad"
L.SERVICE_vendor = "Vendedor"
L.SERVICE_barber = "Peluquería"
L.SERVICE_transmog = "Transfigurador"
L.SERVICE_anvil = "Yunque"
L.SERVICE_forge = "Forja"
L.SERVICE_quartermaster = "Intendente"
L.BATTLE_alterac = "Maestro de batalla del Valle de Alterac"
L.BATTLE_arathi = "Maestro de batalla de la Cuenca de Arathi"
L.BATTLE_warsong = "Maestro de batalla de la Garganta Grito de Guerra"
L.DEBUG_QUESTIE_SERVICES = "servicios de QuestieDB"
L.DEBUG_QUESTIE_SERVICES_RESULT = "QuestieDB: %d PNJ, %d servicios, creado en %.0f ms"
L.TRAINERS_NAME = "Instructores"
L.TRAINERS_DESCRIPTION = "Instructores de clase, de profesiones, de equitación y de armas en las ciudades"
L.TRAINERS_class = "Tu clase"
L.TRAINERS_otherclass = "Otras clases"
L.TRAINERS_profession = "Profesiones"
L.TRAINERS_riding = "Equitación"
L.TRAINERS_weapon = "Armas"
L.DEBUG_TRAINERS = "instructores"
L.DEBUG_TRAINERS_RESULT = "%d instructores (paquete de datos: %s)"
L.TRAINER_WARRIOR = "Instructor de guerreros"
L.TRAINER_PALADIN = "Instructor de paladines"
L.TRAINER_HUNTER = "Instructor de cazadores"
L.TRAINER_ROGUE = "Instructor de pícaros"
L.TRAINER_PRIEST = "Instructor de sacerdotes"
L.TRAINER_SHAMAN = "Instructor de chamanes"
L.TRAINER_MAGE = "Instructor de magos"
L.TRAINER_WARLOCK = "Instructor de brujos"
L.TRAINER_DRUID = "Instructor de druidas"
L.TRAINER_alchemy = "Instructor de alquimia"
L.TRAINER_blacksmithing = "Instructor de herrería"
L.TRAINER_cooking = "Instructor de cocina"
L.TRAINER_enchanting = "Instructor de encantamiento"
L.TRAINER_engineering = "Instructor de ingeniería"
L.TRAINER_fishing = "Instructor de pesca"
L.TRAINER_herbalism = "Instructor de botánica"
L.TRAINER_firstaid = "Instructor de primeros auxilios"
L.TRAINER_skinning = "Instructor de desuello"
L.TRAINER_leatherworking = "Instructor de peletería"
L.TRAINER_tailoring = "Instructor de sastrería"
L.TRAINER_mining = "Instructor de minería"
L.TRAINER_riding = "Instructor de equitación"
L.TRAINER_weapon = "Instructor de armas"

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
ns.W.TOWNS = { "pueblo", "aldea", "campamento", "poblado", "pueblos", "aldeas", "campamentos", "poblados" }
ns.W.SUBZONES = { "subzona", "sitio", "subzonas", "sitios" }
ns.W.INSTANCES = { "instancia", "instancias" }
ns.W.DUNGEONS = { "mazmorra", "mazmorras" }
ns.W.RAIDS = { "banda", "bandas" }
ns.W.DUNGEON = { "mazmorra" }
ns.W.RAID = { "banda" }
ns.W.FLIGHTS = { "vuelo", "volar", "vuelos" }
ns.W.FLIGHT_MASTER = { "maestro de vuelo" }
ns.W.TRANSPORTS = { "transporte", "viaje", "transportes", "viajes" }
ns.W.BOATS = { "barco", "barcos" }
ns.W.ZEPPELINS = { "zepelin", "aeronave", "zepelines", "aeronaves" }
ns.W.TRAMS = { "tranvia", "tranvias" }
ns.W.BOAT = { "barco" }
ns.W.ZEPPELIN = { "zepelin" }
ns.W.SKYSHIP = { "aeronave" }
ns.W.TRAM = { "tranvia", "metro" }
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
ns.W.TRAINER_CLASS = { "clase", "clases" }
ns.W.TRAINER_OTHERCLASS = { "otraclase", "otrasclases" }
ns.W.TRAINER_PROFESSION = { "profesion", "profesiones", "oficio", "oficios" }
ns.W.TRAINER_RIDING = { "equitacion", "montura", "monturas", "montar" }
ns.W.TRAINER_WEAPON = { "armas", "maestro de armas" }
ns.W.TRAINER_WARRIOR = { "guerrero", "guerrera" }
ns.W.TRAINER_HUNTER = { "cazador", "cazadora" }
ns.W.TRAINER_ROGUE = { "picaro", "picara" }
ns.W.TRAINER_PRIEST = { "sacerdote", "sacerdotisa" }
ns.W.TRAINER_SHAMAN = { "chaman", "chamana" }
ns.W.TRAINER_MAGE = { "mago", "maga" }
ns.W.TRAINER_WARLOCK = { "brujo", "bruja" }
ns.W.TRAINER_HERBALISM = { "herboristeria", "herbalismo", "hierbas" }
ns.W.TRAINER_FIRSTAID = { "medico", "vendas" }
ns.W.REPAIR = { "reparar", "reparacion" }
ns.W.MAILBOX = { "buzon", "correo", "buzones" }
ns.W.BATTLEMASTER = { "batalla", "maestro de batalla", "campo de batalla", "maestros de batalla" }
ns.W.BATTLEGROUND_ALTERAC = { "valle de alterac" }
ns.W.BATTLEGROUND_ARATHI = { "cuenca de arathi" }
ns.W.BATTLEGROUND_WARSONG = { "garganta grito de guerra", "grito de guerra" }
ns.W.TRANSMOG = { "transfigurador", "transfiguracion", "transfiguradora", "apariencia" }
ns.W.ANVIL = { "yunque", "yunques" }
ns.W.QUARTERMASTER = { "intendente", "intendentes" }
ns.W.FORGE = { "forja", "forjas" }
ns.W.BARBER = { "peluqueria", "peluquero", "barbero", "barberia", "peluquerias" }
ns.W.GUILD = { "hermandad", "tabardo", "maestro de la hermandad" }
ns.W.VENDOR = { "vendedor", "proveedor", "tienda", "mercader", "vendedores", "proveedores" }
