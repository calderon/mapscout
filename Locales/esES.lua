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
L.DEBUG_NORMALIZE = "cómo se busca un texto: /ms debug normalize <texto>"
L.DEBUG_NORMALIZE_RESULT = "«%s» se busca como «%s»"

-- Teclas (ns.KeyName)
L.KEY_ALT_MAC = "Opción"

-- Palabras de búsqueda en español (además de las inglesas, que siempre funcionan).
-- Cada proveedor añade las suyas (p. ej. ns.W.FILTER_FLIGHTS = { "vuelos", "vuelo" }).
