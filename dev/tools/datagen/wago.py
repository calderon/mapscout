"""Client data tables (DB2) of one exact game build, from wago.tools.

wago.tools publishes the DB2 tables of every build as CSV exports, and its
robots.txt and /llms.txt allow automated downloads of those exports (not of the
browsing pages). Each table is downloaded once per build and locale and kept in
the cache folder, so running the generator again does not ask for it again.
"""

import csv
import json
import os
import urllib.parse
import urllib.request

SITE = "https://wago.tools"
USER_AGENT = "MapScout-datagen (World of Warcraft addon data tool)"


def _get(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def build_date(product, version):
    """The date wago.tools processed this build (YYYY-MM-DD), or None."""
    builds = json.loads(_get(SITE + "/api/builds"))
    for build in builds.get(product, []):
        if build.get("version") == version:
            return (build.get("created_at") or "")[:10] or None
    return None


class Tables:
    """Reads DB2 tables of one build: tables.rows("Map"), tables.rows("Map", "esES")."""

    def __init__(self, version, cache_dir, refresh=False):
        self.version = version
        self.cache_dir = os.path.join(cache_dir, version)
        self.refresh = refresh

    def path(self, table, locale):
        return os.path.join(self.cache_dir, "%s.%s.csv" % (table, locale))

    def rows(self, table, locale="enUS"):
        path = self.path(table, locale)
        if self.refresh or not os.path.exists(path):
            query = {"version": self.version}
            if locale != "enUS":
                query["locale"] = locale
            url = "%s/db2/%s/csv?%s" % (SITE, urllib.parse.quote(table), urllib.parse.urlencode(query))
            data = _get(url)
            if data.lstrip().startswith(b"{"):  # an error comes as JSON
                raise RuntimeError("%s (%s): %s" % (table, self.version, data.decode("utf-8", "replace")))
            os.makedirs(self.cache_dir, exist_ok=True)
            with open(path, "wb") as out:
                out.write(data)
        with open(path, newline="", encoding="utf-8") as source:
            return list(csv.DictReader(source))
