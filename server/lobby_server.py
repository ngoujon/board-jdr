"""Serveur communautaire d'Arcanes & Lames.

Gère : comptes (pseudo unique + avatar), statistiques / classement, amis,
présence en ligne, invitations, messagerie privée entre amis (historique conservé),
salons de partie et relais des parties en ligne, replays des parties et statistiques
globales des cartes (issues de toutes les parties enregistrées).

Protocole : TCP, un objet JSON par ligne (UTF-8), en TLS sur --tls-port (serveur officiel).
Aucune dépendance : Python 3.9+ (bibliothèque standard uniquement).

Anti-triche : le serveur fournit la graine de chaque partie (« ticket ») et rejoue la partie avec le moteur
du jeu (Godot sans affichage, voir Verifier) avant d'accorder victoire, pièces d'or, XP et statistiques.
En ligne, il enregistre lui-même les actions relayées entre les joueurs.

Mises à jour : le dossier updates/ contient latest.json (version, fichier, sha256, taille, notes)
et le paquet .pck du jeu (voir tools/publier_mise_a_jour.bat). Ils sont servis en HTTP sur le
port suivant (7779 par défaut) et les clients plus anciens que latest.json sont refusés.

Lancement :  python lobby_server.py [--host 0.0.0.0] [--port 7778] [--data lobby_data.json]
Les joueurs doivent pouvoir joindre ces ports TCP (redirection de port sur la box ou VPN).
"""

import argparse
import asyncio
import json
import os
import re
import secrets
import signal
import sqlite3
import ssl
import time
from urllib.parse import unquote

PROTOCOL_VERSION = 1
NAME_RE = re.compile(r"^[\w\- ]{3,16}$", re.UNICODE)
MAX_AVATAR = 15
COSMETICS = {}   # catalogue de personnalisation (data/cosmetics.json du jeu)
I18N = {}        # traductions des messages : langue -> {texte français: traduction}
LANGS = ("fr", "en", "de", "es", "it", "pt")
COSMETIC_KINDS = {"title": "titles", "avatar": "avatars", "border": "borders", "card_back": "card_backs", "board": "boards"}
DEFAULT_EQUIP = {"title": "novice", "border": "none", "card_back": "default", "board": "default"}
# Statistiques envoyées par le jeu en fin de partie (les autres sont calculées par le serveur).
REPORTED_STATS = ("minions_played", "spells_played", "enchants_played", "taunt_played", "charge_played",
                  "shield_played", "deathrattle_played", "enchants_destroyed", "hero_damage")
REPLAY_MAX = 200000       # taille maximale d'un replay (JSON)
STATS_CACHE_S = 60        # les statistiques globales sont recalculées au plus une fois par minute
CARD_ID_RE = re.compile(r"^[a-z0-9_]{1,32}$")
DM_MAX_LEN = 300          # longueur maximale d'un message privé
DM_HISTORY = 200          # messages renvoyés à l'ouverture d'une conversation
DM_RATE = (8, 10.0)       # au plus 8 messages par tranche de 10 s
SUGGEST_RATE = (10, 3600)  # sujets de suggestion : au plus 10 par heure et par compte
REPLY_RATE = (30, 600)     # réponses dans les fils : au plus 30 par tranche de 10 min
SUGGEST_MAX_LEN = 600
REPLY_MAX_LEN = 400
SUGGEST_MAX_CARDS = 5
SUGGEST_KINDS = ("buff", "nerf", "bug", "autre")
SUGGEST_LIST = 150         # sujets renvoyés par la liste (activité la plus récente d'abord)
SUGGEST_REPLIES = 300      # réponses renvoyées pour un fil
CARD_ID_RE = re.compile(r"[a-z0-9_]{1,32}")
CTRL_RE = re.compile(r"[\x00-\x1f\x7f]")
UPDATES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "updates")
TICKET_TTL = 4 * 3600      # une partie enregistrée doit être terminée dans les 4 h
RELAY_LOG_MAX = 12000      # événements enregistrés au plus par partie en ligne
RELAY_KINDS = ("_hello", "_start", "_request", "_apply", "_reject", "_chat", "_version_mismatch", "_rematch")
HOST_ONLY = ("_start", "_apply", "_reject")
PAIR_DAILY_CAP = 10        # parties récompensées par jour contre le même adversaire (anti-farm entre comptes)
NEW_ACCOUNTS_PER_IP = (3, 3600)   # comptes créés au plus par adresse IP et par heure
MSG_RATE = (25.0, 80.0)    # messages par seconde (débit continu, rafale) par connexion
STALLED_REQUEST_S = 15     # demande de l'invité sans réponse de l'hôte : l'invité peut partir sans pénalité
CHALLENGER_BONUS = {"health": 5, "cards": 1}   # identique à AIPlayer.challenger_bonus (jeu)
INFERNO_BONUS = {"health": 0, "cards": 1, "inferno": True}   # identique à AIPlayer.inferno_bonus (jeu)
INFERNO = 4                # niveau « Inferno » : PV infinis pour l'IA, score = dégâts infligés
INFERNO_SCORE_PO = (10, 50)   # Inferno : 1 PO de plus par tranche de 10 dégâts, 50 au maximum
AI_NAMES = {0: "Apprenti", 1: "Chevalier", 2: "Seigneur de guerre", 3: "Challenger", 4: "Inferno"}
DRAIN_MAX_S = 3 * 3600     # redémarrage en douceur : attente maximale de la fin des parties en ligne
VERIFY_TIMEOUT_INFERNO = 240   # une partie Inferno est plus longue à rejouer


def version_tuple(v):
    parts = []
    for p in str(v).split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return tuple(parts)


def latest_release():
    """Contenu de updates/latest.json (relu à chaque fois : publier ne demande pas de redémarrage)."""
    try:
        with open(os.path.join(UPDATES_DIR, "latest.json"), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) and "version" in data else None
    except (OSError, ValueError):
        return None


class Store:
    """Persistance JSON des comptes : token -> profil."""

    def __init__(self, path):
        self.path = path
        self.accounts = {}
        if os.path.exists(path):
            with open(path, "r", encoding="utf-8") as f:
                self.accounts = json.load(f).get("accounts", {})
        for a in self.accounts.values():
            played = a.get("wins", 0) + a.get("losses", 0) + a.get("ai_wins", 0) + a.get("ai_losses", 0) + a.get("draws", 0)
            if "seasons" not in a:
                a["seasons"] = {"1": {"xp": 0, "games": 1}} if played else {}
            a.setdefault("gold", 0)

    def save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"accounts": self.accounts}, f, ensure_ascii=False, indent=1)
            f.flush()
            os.fsync(f.fileno())   # écrit réellement sur le disque avant la bascule
        os.replace(tmp, self.path)

    def token_for_name(self, name):
        low = name.lower()
        for tok, acc in self.accounts.items():
            if acc["name"].lower() == low:
                return tok
        return None

    def new_account(self, token, name, avatar):
        self.accounts[token] = {
            "name": name, "avatar": avatar, "created": int(time.time()),
            "wins": 0, "losses": 0, "ai_wins": 0, "ai_losses": 0,
            "friends": [], "incoming": [], "gold": 0, "seasons": {}, "owned": {},
        }


class History:
    """Historique complet des parties (SQLite, conservé sans limite de durée)."""

    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("""CREATE TABLE IF NOT EXISTS matches (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,              -- date (epoch UTC)
            mode TEXT NOT NULL,               -- 'pvp' | 'ai'
            p1_token TEXT, p1_name TEXT,      -- joueur 1 (hôte, ou le joueur contre l'IA)
            p2_token TEXT, p2_name TEXT,      -- joueur 2 (invité) ; NULL contre l'IA
            winner INTEGER,                   -- 1, 2 (ou 2 = l'IA), 0 = égalité
            difficulty INTEGER,               -- contre l'IA : 0 Apprenti, 1 Chevalier, 2 Seigneur de guerre, 3 Challenger
            turns INTEGER, duration INTEGER,  -- nombre de tours, durée en secondes
            reason TEXT,                      -- 'normal' | 'concede' | 'disconnect'
            game_version TEXT)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_p1 ON matches(p1_token, ts)")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_p2 ON matches(p2_token, ts)")
        # Messagerie privée entre amis (conservée sans limite de durée, comme les parties).
        self.db.execute("""CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            from_token TEXT NOT NULL,
            to_token TEXT NOT NULL,
            text TEXT NOT NULL)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_msg_pair ON messages(from_token, to_token, id)")
        # 1.6 : replay de la partie (graine + actions) et « le premier joueur a gagné » (statistiques).
        cols = {r[1] for r in self.db.execute("PRAGMA table_info(matches)")}
        if "replay" not in cols:
            self.db.execute("ALTER TABLE matches ADD COLUMN replay TEXT")
        if "first_won" not in cols:
            self.db.execute("ALTER TABLE matches ADD COLUMN first_won INTEGER")
        if "score" not in cols:   # 2.0 : score du mode Inferno
            self.db.execute("ALTER TABLE matches ADD COLUMN score INTEGER")
        # Cartes jouées par chaque camp de chaque partie (statistiques globales des cartes).
        self.db.execute("""CREATE TABLE IF NOT EXISTS match_cards (
            match_id INTEGER NOT NULL,
            side INTEGER NOT NULL,            -- 0 / 1 (index du joueur dans la partie)
            token TEXT,                       -- NULL pour l'IA
            card_id TEXT NOT NULL,
            plays INTEGER NOT NULL,
            won INTEGER NOT NULL)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_mc_match ON match_cards(match_id)")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_mc_token ON match_cards(token)")
        # 2.0.8 : forum des suggestions (équilibrage des cartes, bugs, idées) : un sujet par suggestion,
        # les joueurs y répondent dans un fil de discussion public.
        self.db.execute("""CREATE TABLE IF NOT EXISTS suggestions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts INTEGER NOT NULL,
            token TEXT NOT NULL, name TEXT NOT NULL,   -- auteur (nom au moment de l'envoi)
            cards TEXT NOT NULL,                       -- identifiants des cartes, séparés par des virgules
            kind TEXT NOT NULL,                        -- 'buff' | 'nerf' | 'bug' | 'autre'
            text TEXT NOT NULL,
            game_version TEXT,
            last_ts INTEGER, replies INTEGER DEFAULT 0)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_sugg_token ON suggestions(token, ts)")
        self.db.execute("""CREATE TABLE IF NOT EXISTS suggestion_replies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sugg_id INTEGER NOT NULL,
            ts INTEGER NOT NULL,
            token TEXT NOT NULL, name TEXT NOT NULL,
            text TEXT NOT NULL)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_reply_sugg ON suggestion_replies(sugg_id, id)")
        self.db.execute("CREATE INDEX IF NOT EXISTS idx_reply_token ON suggestion_replies(token, ts)")
        self.db.commit()
        self._stats_cache = {}

    def add_message(self, ts, from_token, to_token, text):
        self.db.execute("INSERT INTO messages (ts, from_token, to_token, text) VALUES (?, ?, ?, ?)",
                        (ts, from_token, to_token, text))
        self.db.commit()

    def add_suggestion(self, ts, token, name, cards, kind, text, version):
        cur = self.db.execute("INSERT INTO suggestions (ts, token, name, cards, kind, text, game_version, last_ts, replies) "
                              "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)", (ts, token, name, ",".join(cards), kind, text, version, ts))
        self.db.commit()
        return cur.lastrowid

    def count_since(self, table, token, since):
        return self.db.execute(f"SELECT COUNT(*) FROM {table} WHERE token=? AND ts>=?", (token, since)).fetchone()[0]

    @staticmethod
    def _topic(row):
        sid, ts, name, cards, kind, text, last_ts, replies = row
        return {"id": sid, "ts": ts, "name": name, "cards": [x for x in cards.split(",") if x], "kind": kind,
                "text": text, "last_ts": last_ts or ts, "replies": replies or 0}

    def suggestion_topics(self, kind="", search="", card_ids=(), limit=SUGGEST_LIST):
        """Sujets du forum. `search` : mots cherchés dans le texte, l'auteur et les réponses ; `card_ids` : cartes
        dont le nom (traduit, calculé par le jeu) correspond à la recherche."""
        q = "SELECT id, ts, name, cards, kind, text, last_ts, replies FROM suggestions WHERE 1=1"
        args = []
        if kind in SUGGEST_KINDS:
            q += " AND kind=?"
            args.append(kind)
        if search:
            like = "%" + search.replace("\\", "").replace("%", "") + "%"
            ors = ["text LIKE ?", "name LIKE ?",
                   "id IN (SELECT sugg_id FROM suggestion_replies WHERE text LIKE ?)"]
            args += [like, like, like]
            for cid in card_ids:
                ors.append("(',' || cards || ',') LIKE ?")
                args.append(f"%,{cid},%")
            q += " AND (" + " OR ".join(ors) + ")"
        q += " ORDER BY COALESCE(last_ts, ts) DESC, id DESC LIMIT ?"
        args.append(limit)
        return [self._topic(r) for r in self.db.execute(q, args).fetchall()]

    def suggestion_thread(self, sid):
        row = self.db.execute("SELECT id, ts, name, cards, kind, text, last_ts, replies FROM suggestions WHERE id=?", (sid,)).fetchone()
        if row is None:
            return None
        topic = self._topic(row)
        rows = self.db.execute("SELECT ts, name, text FROM suggestion_replies WHERE sugg_id=? ORDER BY id DESC LIMIT ?",
                               (sid, SUGGEST_REPLIES)).fetchall()
        topic["messages"] = [{"ts": ts, "name": name, "text": text} for ts, name, text in rows[::-1]]
        return topic

    def add_reply(self, sid, ts, token, name, text):
        self.db.execute("INSERT INTO suggestion_replies (sugg_id, ts, token, name, text) VALUES (?, ?, ?, ?, ?)",
                        (sid, ts, token, name, text))
        self.db.execute("UPDATE suggestions SET last_ts=?, replies=COALESCE(replies, 0)+1 WHERE id=?", (ts, sid))
        self.db.commit()

    def conversation(self, a, b, limit=DM_HISTORY):
        rows = self.db.execute(
            "SELECT ts, from_token, text FROM messages WHERE (from_token=? AND to_token=?) "
            "OR (from_token=? AND to_token=?) ORDER BY id DESC LIMIT ?", (a, b, b, a, limit)).fetchall()
        return rows[::-1]

    def add(self, cards=None, **m):
        """Enregistre une partie. `cards` : [(side, token, {card_id: plays}, won)]."""
        cols = ", ".join(m)
        cur = self.db.execute(f"INSERT INTO matches ({cols}) VALUES ({', '.join('?' * len(m))})", tuple(m.values()))
        mid = cur.lastrowid
        for side, token, plays, won in cards or []:
            self.db.executemany(
                "INSERT INTO match_cards (match_id, side, token, card_id, plays, won) VALUES (?, ?, ?, ?, ?, ?)",
                [(mid, side, token, cid, n, 1 if won else 0) for cid, n in plays.items()])
        self.db.commit()
        return mid

    def replay(self, match_id):
        row = self.db.execute("SELECT replay, mode, ts FROM matches WHERE id=?", (match_id,)).fetchone()
        if not row or not row[0]:
            return None
        try:
            data = json.loads(row[0])
        except ValueError:
            return None
        data["id"] = match_id
        data["mode"] = row[1]
        data["ts"] = row[2]
        return data

    def favorite_cards(self, token, limit=5):
        return [{"card": cid, "plays": n, "games": g, "wins": w} for cid, n, g, w in self.db.execute(
            "SELECT card_id, SUM(plays), COUNT(*), SUM(won) FROM match_cards WHERE token=? "
            "GROUP BY card_id ORDER BY SUM(plays) DESC, card_id LIMIT ?", (token, limit))]

    def global_stats(self, mode):
        """Statistiques de toutes les parties enregistrées ; mode : all | pvp | ai."""
        now = time.monotonic()
        hit = self._stats_cache.get(mode)
        if hit and now - hit[0] < STATS_CACHE_S:
            return hit[1]
        where, args = ("", ()) if mode == "all" else ("WHERE m.mode=?", (mode,))
        games, avg_turns, avg_dur = self.db.execute(
            f"SELECT COUNT(*), AVG(turns), AVG(NULLIF(duration, 0)) FROM matches m {where}", args).fetchone()
        by_mode = dict(self.db.execute("SELECT mode, COUNT(*) FROM matches GROUP BY mode").fetchall())
        fw = self.db.execute(f"SELECT COUNT(first_won), SUM(first_won) FROM matches m {where}", args).fetchone()
        ai = []
        for diff, n, won in self.db.execute(
                "SELECT difficulty, COUNT(*), SUM(winner = 1) FROM matches WHERE mode='ai' GROUP BY difficulty ORDER BY difficulty"):
            ai.append({"difficulty": diff or 0, "games": n, "player_wins": won or 0})
        sides = self.db.execute(
            f"SELECT COUNT(*) FROM (SELECT DISTINCT mc.match_id, mc.side FROM match_cards mc JOIN matches m ON m.id = mc.match_id {where})",
            args).fetchone()[0]
        cards = []
        for cid, plays, g, w in self.db.execute(
                f"SELECT mc.card_id, SUM(mc.plays), COUNT(*), SUM(mc.won) FROM match_cards mc "
                f"JOIN matches m ON m.id = mc.match_id {where} GROUP BY mc.card_id", args):
            cards.append({"card": cid, "plays": plays, "games": g, "wins": w})
        out = {"mode": mode, "games": games, "by_mode": by_mode, "avg_turns": round(avg_turns or 0, 1),
               "avg_duration": int(avg_dur or 0), "first_games": fw[0] or 0, "first_wins": fw[1] or 0,
               "ai": ai, "sides": sides, "cards": cards}
        self._stats_cache[mode] = (now, out)
        return out

    def ai_records(self):
        """{jeton: [[victoires, parties] par niveau 0 Apprenti … 3 Challenger]} (parties contre l'IA, hors Inferno)."""
        out = {}
        for tok, diff, won, n in self.db.execute("SELECT p1_token, difficulty, SUM(winner = 1), COUNT(*) FROM matches "
                                                 "WHERE mode='ai' GROUP BY p1_token, difficulty"):
            if tok and diff is not None and 0 <= diff <= 3:
                out.setdefault(tok, [[0, 0] for _ in range(4)])[diff] = [won or 0, n]
        return out

    def ai_wins_by_level(self):
        """{jeton: {niveau: victoires}} d'après l'historique (reprise des comptes d'avant la 2.0)."""
        out = {}
        for tok, diff, n in self.db.execute("SELECT p1_token, difficulty, COUNT(*) FROM matches "
                                            "WHERE mode='ai' AND winner=1 GROUP BY p1_token, difficulty"):
            if tok and diff is not None and 0 <= diff <= 3:
                out.setdefault(tok, {})[str(diff)] = n
        return out

    def for_player(self, token, limit=100):
        total = self.db.execute("SELECT COUNT(*) FROM matches WHERE p1_token=? OR p2_token=?",
                                (token, token)).fetchone()[0]
        rows = self.db.execute(
            "SELECT ts, mode, p1_token, p1_name, p2_name, winner, difficulty, turns, duration, reason, id, "
            "replay IS NOT NULL, score FROM matches WHERE p1_token=? OR p2_token=? ORDER BY ts DESC, id DESC LIMIT ?",
            (token, token, limit)).fetchall()
        out = []
        for ts, mode, p1_tok, p1_name, p2_name, winner, diff, turns, dur, reason, mid, has_replay, score in rows:
            me_is_p1 = p1_tok == token
            if mode == "ai":
                opponent = "IA " + AI_NAMES.get(diff, "Apprenti")
                if diff == INFERNO:
                    opponent += f" ({score or 0})"
            else:
                opponent = p2_name if me_is_p1 else p1_name
            me_slot = 1 if me_is_p1 else 2
            result = "draw" if winner == 0 else ("win" if winner == me_slot else "loss")
            out.append({"ts": ts, "mode": mode, "opponent": opponent, "result": result,
                        "turns": turns or 0, "duration": dur or 0, "reason": reason or "normal",
                        "id": mid, "replay": bool(has_replay)})
        return total, out


def load_i18n(folder):
    """Traductions des messages du serveur (data/i18n/<langue>.json du jeu)."""
    for lang in LANGS[1:]:
        try:
            with open(os.path.join(folder, f"{lang}.json"), encoding="utf-8") as f:
                I18N[lang] = json.load(f)
        except (OSError, ValueError):
            pass
    print(f"Traductions : {', '.join(sorted(I18N)) or 'aucune'}")


def load_cosmetics(path):
    global COSMETICS
    try:
        with open(path, encoding="utf-8") as f:
            COSMETICS = json.load(f)
        print(f"Personnalisation : {sum(len(COSMETICS.get(k, [])) for k in COSMETIC_KINDS.values())} éléments ({path})")
    except (OSError, ValueError) as e:
        COSMETICS = {}
        print(f"Personnalisation indisponible ({path}) : {e}")


# ------------------------------------------------------------------ saisons (une par mois)
def _add_months(d, n):
    import datetime
    y, m = divmod(d.month - 1 + n, 12)
    y += d.year
    m += 1
    import calendar
    return d.replace(year=y, month=m, day=min(d.day, calendar.monthrange(y, m)[1]))


def season_info(now=None):
    """Saison en cours : (numéro, début, fin) en secondes UTC. La saison 1 commence le jour « epoch »."""
    import datetime
    now = now if now is not None else time.time()
    conf = COSMETICS.get("seasons", {})
    epoch = datetime.datetime.strptime(conf.get("epoch", "2026-09-26"), "%Y-%m-%d").replace(tzinfo=datetime.timezone.utc)
    n = 1
    while _add_months(epoch, n).timestamp() <= now and n < 1200:
        n += 1
    return n, int(_add_months(epoch, n - 1).timestamp()), int(_add_months(epoch, n).timestamp())


def season_conf():
    c = COSMETICS.get("seasons", {})
    return int(c.get("levels", 30)), int(c.get("xp_per_level", 250))


def season_rewards(n):
    c = COSMETICS.get("seasons", {})
    return c.get("rewards", {}).get(str(n)) or c.get("default_rewards", [])


def pass_level(acc, n):
    levels, per = season_conf()
    xp = acc.get("seasons", {}).get(str(n), {}).get("xp", 0)
    return min(levels, xp // per)


AI_WEIGHTS = (0.25, 0.5, 0.8, 1.0)   # Apprenti, Chevalier, Seigneur de guerre, Challenger
AI_MIN_GAMES = 5


def ai_score(records):
    """Score contre l'IA (0 à 100) : % de victoires pondéré par la difficulté de chaque partie.
    Ne gagner qu'en Apprenti plafonne à 25 ; tout gagner contre le Challenger donne 100.
    -1 : moins de AI_MIN_GAMES parties (non classé)."""
    if not records:
        return -1
    games = sum(n for _, n in records)
    if games < AI_MIN_GAMES:
        return -1
    return round(100.0 * sum(AI_WEIGHTS[d] * records[d][0] for d in range(4)) / games, 1)


def claimed_levels(acc, n):
    """Niveaux du passe de la saison n dont le joueur a récupéré la récompense."""
    return {int(x) for x in acc.get("seasons", {}).get(str(n), {}).get("claimed", [])}


def claimable_levels(acc, n):
    """Niveaux atteints dont la récompense n'a pas encore été récupérée."""
    lvl, done = pass_level(acc, n), claimed_levels(acc, n)
    return [int(r["level"]) for r in season_rewards(n) if int(r.get("level", 0)) <= lvl and int(r["level"]) not in done]


def stat_values(acc):
    """Statistiques d'un compte, y compris celles déduites des résultats."""
    st = dict(acc.get("stats", {}))
    st["pvp_wins"] = acc["wins"]
    st["ai_wins"] = acc["ai_wins"]
    st["wins"] = acc["wins"] + acc["ai_wins"]
    st["games"] = acc["wins"] + acc["losses"] + acc["ai_wins"] + acc["ai_losses"] + acc.get("draws", 0)
    st["best_streak"] = acc.get("best_streak", 0)
    for lvl in range(4):
        st[f"ai_beaten_{lvl}"] = acc.get("ai_beaten", {}).get(str(lvl), 0)   # victoires contre chaque niveau d'IA
    st["inferno_best"] = acc.get("inferno_best", 0)
    st["worst_loss_streak"] = acc.get("worst_loss_streak", 0)
    return st


def rule_ok(rule, stats, champion, acc=None, kind="", item_id=None):
    if not rule:
        return True
    if "rank" in rule:
        return champion
    acc = acc or {}
    if "shop" in rule:
        return str(item_id) in [str(x) for x in acc.get("owned", {}).get(kind, [])]
    if "pass" in rule:
        # 2.0 : l'objet du passe est à vous une fois la récompense du niveau récupérée (bouton « Récupérer »).
        return int(rule["pass"]) in claimed_levels(acc, int(rule.get("season", 1)))
    if "pioneer" in rule:
        # Participants de la saison 1, récompensés à la fin de celle-ci.
        return acc.get("seasons", {}).get("1", {}).get("games", 0) > 0 and season_info()[0] > 1
    return stats.get(rule.get("stat", ""), 0) >= int(rule.get("min", 0))


def _int(v, lo=0, hi=10 ** 6):
    try:
        return max(lo, min(hi, int(v)))
    except (TypeError, ValueError):
        return 0


def _card_plays(v):
    """{card_id: nombre} envoyé par le jeu, validé (80 cartes différentes au plus)."""
    out = {}
    if isinstance(v, dict):
        for k, n in list(v.items())[:80]:
            if isinstance(k, str) and CARD_ID_RE.match(k):
                out[k] = _int(n, 0, 60)
    return {k: n for k, n in out.items() if n > 0}


def _replay_json(v):
    """Replay compact envoyé par le jeu : graine, premier joueur, noms, avatars, actions."""
    if not isinstance(v, dict) or not isinstance(v.get("actions"), list):
        return None
    data = {"v": 1, "seed": _int(v.get("seed"), 0, 2 ** 32 - 1), "first": _int(v.get("first"), 0, 1),
            "me": _int(v.get("me"), 0, 1), "difficulty": _int(v.get("difficulty"), 0, INFERNO),
            "bonus": _bonus_json(v.get("bonus")),
            "game": str(v.get("game", ""))[:16],
            "names": [str(x)[:24] for x in (v.get("names") or ["?", "?"])[:2]],
            "avatars": [_int(x, 0, MAX_AVATAR) for x in (v.get("avatars") or [0, 0])[:2]],
            "actions": v["actions"][:4000]}
    txt = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    return txt if len(txt) <= REPLAY_MAX else None


def _bonus_json(v):
    """Avantage de départ du Challenger (PV / cartes en plus pour l'IA)."""
    if not isinstance(v, dict) or not v:
        return {}
    return {"player": _int(v.get("player"), 0, 1), "health": _int(v.get("health"), 0, 20), "cards": _int(v.get("cards"), 0, 3)}


def _reason(v):
    return v if v in ("normal", "concede", "disconnect") else "normal"


class Client:
    def __init__(self, server, reader, writer):
        self.server = server
        self.reader = reader
        self.writer = writer
        self.token = None
        self.status = "online"  # online | lobby | in_game
        self.room = None
        self.dm_times = []   # horodatages des derniers messages privés (limite de débit)
        self.sugg_view = 0   # sujet de suggestion ouvert (réponses reçues en direct)
        peer = writer.get_extra_info("peername") if writer else None
        self.ip = peer[0] if peer else "?"
        self.rate_tokens = MSG_RATE[1]
        self.rate_ts = time.monotonic()
        self.dropped = 0
        self.lang = "fr"
        self.game_version = ""
        self.outdated = False   # version précédente du jeu : peut finir sa partie, pas en commencer une

    def t(self, text, **kw):
        """Message traduit dans la langue du joueur (fichiers i18n/<langue>.json du jeu)."""
        return I18N.get(self.lang, {}).get(text, text).format(**kw) if kw else I18N.get(self.lang, {}).get(text, text)

    @property
    def account(self):
        return self.server.store.accounts.get(self.token)

    def send(self, msg):
        try:
            self.writer.write((json.dumps(msg, ensure_ascii=False) + "\n").encode("utf-8"))
        except Exception:
            pass


class Room:
    def __init__(self, host, name=""):
        self.id = secrets.token_hex(4)
        self.host = host
        self.guest = None
        self.name = name or f"Partie de {host.account['name']}"
        self.created = int(time.time())
        self.in_game = False
        self.ticket = None    # partie en cours : graine, joueurs, événements enregistrés
        self.log = []
        self.pending = []     # horodatages des demandes de l'invité pas encore traitées par l'hôte

    def other(self, client):
        return self.guest if client is self.host else self.host

    def pending_since(self, seconds):
        return bool(self.pending) and time.time() - self.pending[0] > seconds

    def describe(self):
        def p(c):
            if c is None:
                return None
            return c.server.public(c.token)
        return {"id": self.id, "name": self.name, "host": p(self.host), "guest": p(self.guest)}

    def listing(self):
        state = "in_game" if self.in_game and self.guest else ("full" if self.guest else "waiting")
        return {"id": self.id, "name": self.name, "created": self.created, "state": state,
                "players": 2 if self.guest else 1,
                "host": self.host.server.public(self.host.token)}


class Verifier:
    """Rejoue une partie avec le moteur du jeu (Godot sans affichage) pour en valider le résultat.

    Le paquet du jeu utilisé est la dernière version publiée (updates/latest.json) : il contient la scène
    scenes/tools/verifier.tscn. --verifier-project permet d'utiliser un dossier de projet (développement).
    Une partie à la fois, avec un délai maximal : le VPS est partagé avec d'autres services."""

    def __init__(self, godot="", project="", work_dir="", timeout=40):
        self.godot = godot
        self.project = project
        self.work_dir = work_dir
        self.timeout = timeout
        self.lock = asyncio.Semaphore(1)

    def configured(self):
        return bool(self.godot) and os.path.isfile(self.godot)

    def _source(self, version=""):
        """Paquet du jeu : celui de la version sur laquelle la partie a été jouée s'il est encore là
        (les versions précédentes sont gardées dans updates/packs/), sinon la dernière version publiée."""
        if self.project:
            return ["--path", self.project]
        if re.fullmatch(r"\d+(\.\d+){1,3}", str(version)):
            for folder in (UPDATES_DIR, os.path.join(UPDATES_DIR, "packs")):
                pck = os.path.join(folder, f"arcanes_{version}.pck")
                if os.path.isfile(pck):
                    return ["--main-pack", pck]
        latest = latest_release()
        pck = os.path.join(UPDATES_DIR, os.path.basename(str((latest or {}).get("file", ""))))
        return ["--main-pack", pck] if latest and os.path.isfile(pck) else None

    async def run(self, job, version="", timeout=None):
        """Résultat de MatchCheck (jeu) ; None si aucun vérificateur n'est configuré.
        {"ok": False, "infra": True} : la vérification n'a pas pu avoir lieu (le joueur n'y est pour rien)."""
        if not self.configured():
            return None
        source = self._source(version)
        if source is None:
            return {"ok": False, "infra": True, "error": "paquet du jeu introuvable"}
        async with self.lock:
            os.makedirs(self.work_dir, exist_ok=True)
            path = os.path.join(self.work_dir, f"job_{secrets.token_hex(8)}.json")
            with open(path, "w", encoding="utf-8") as f:
                json.dump(job, f, separators=(",", ":"))
            env = dict(os.environ, HOME=self.work_dir, XDG_DATA_HOME=self.work_dir, XDG_CONFIG_HOME=self.work_dir,
                       APPDATA=self.work_dir)
            proc = None
            try:
                proc = await asyncio.create_subprocess_exec(
                    self.godot, "--headless", *source, "res://scenes/tools/verifier.tscn", "--", "--verifier",
                    f"--job={path}", stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
                    stdin=asyncio.subprocess.DEVNULL, env=env)
                out, _ = await asyncio.wait_for(proc.communicate(), timeout or self.timeout)
            except asyncio.TimeoutError:
                if proc:
                    proc.kill()
                    await proc.wait()
                return {"ok": False, "infra": True, "error": "délai de vérification dépassé"}
            except OSError as e:
                return {"ok": False, "infra": True, "error": f"vérificateur indisponible : {e}"}
            finally:
                try:
                    os.remove(path)
                except OSError:
                    pass
        for line in out.decode("utf-8", "replace").splitlines():
            if line.startswith("@@RESULT "):
                try:
                    res = json.loads(line[9:])
                    if isinstance(res, dict):
                        return res
                except ValueError:
                    pass
        return {"ok": False, "infra": True, "error": "le vérificateur n'a pas répondu"}


def _verified_cards(res, tokens, winner_side):
    cards = []
    raw = res.get("cards")
    if isinstance(raw, list) and len(raw) == 2:
        for side in (0, 1):
            plays = _card_plays(raw[side])
            if plays:
                cards.append((side, tokens[side], plays, winner_side == side))
    return cards


class LobbyServer:
    MAX_PER_IP = 8        # connexions simultanées par adresse IP (anti-abus)
    MAX_CLIENTS = 2000

    def __init__(self, data_path, history_path):
        self.store = Store(data_path)
        self.history = History(history_path)
        self.online = {}  # token -> Client
        self.rooms = {}   # id -> Room
        self.per_ip = {}  # ip -> nombre de connexions ouvertes
        self.room_watchers = set()   # clients qui affichent la liste des parties
        self.verifier = Verifier()
        self.new_accounts = {}       # ip -> horodatages des derniers comptes créés
        self.pair_games = {}         # (jour, jeton, jeton) -> parties récompensées ce jour-là
        # Parties contre l'IA en cours, par compte : elles survivent à une reconnexion et à un redémarrage du serveur.
        self.tickets_path = os.path.join(os.path.dirname(os.path.abspath(data_path)), "ai_tickets.json")
        self.ai_tickets = self.load_tickets()
        self._ai_levels, self._ai_levels_at = {}, 0.0   # cache de History.ai_records (classement)
        self.tasks = set()           # validations de parties en cours (attendues avant un redémarrage)
        self.draining = False        # redémarrage demandé : on attend la fin des parties en ligne
        levels = self.history.ai_wins_by_level()
        changed = False
        for acc in self.store.accounts.values():
            for n, sea in acc.get("seasons", {}).items():
                if "claimed" not in sea and n.isdigit():
                    lvl = pass_level(acc, int(n))
                    sea["claimed"] = [int(r["level"]) for r in season_rewards(int(n)) if int(r.get("level", 0)) <= lvl]
                    changed = True
        for tok, acc in self.store.accounts.items():
            if "ai_beaten" not in acc:
                acc["ai_beaten"] = levels.get(tok, {})
                changed = True
        if changed:
            self.store.save()

    # ------------------------------------------------------------ redémarrage sans couper les parties
    def load_tickets(self):
        try:
            with open(self.tickets_path, encoding="utf-8") as f:
                data = json.load(f)
            now = time.time()
            return {tok: t for tok, t in data.items() if isinstance(t, dict) and now - t.get("created", 0) < TICKET_TTL}
        except (OSError, ValueError):
            return {}

    def save_tickets(self):
        tmp = self.tickets_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({k: v for k, v in self.ai_tickets.items() if not v.get("done")}, f)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, self.tickets_path)

    def spawn(self, coro):
        task = asyncio.get_running_loop().create_task(coro)
        self.tasks.add(task)
        task.add_done_callback(self.tasks.discard)
        return task

    def live_matches(self):
        return [r for r in self.rooms.values() if r.ticket and not r.ticket["done"] and r.guest is not None]

    def request_restart(self):
        """SIGUSR1 (systemctl reload) : nouvelles parties en ligne suspendues, on attend la fin de celles en cours
        et des validations, puis le serveur s'arrête proprement et systemd le relance avec le nouveau code.
        Les parties contre l'IA ne bloquent rien : leurs tickets sont enregistrés et restent valables."""
        if self.draining:
            return
        self.draining = True
        print(f"[maj] redémarrage demandé : {len(self.live_matches())} partie(s) en ligne à terminer")
        self.spawn(self.drain())

    async def drain(self):
        start = time.time()
        while time.time() - start < DRAIN_MAX_S:
            if not self.live_matches() and not [t for t in self.tasks if t is not asyncio.current_task()]:
                break
            await asyncio.sleep(2)
        self.save_tickets()
        self.store.save()
        for c in list(self.online.values()):
            c.send({"t": "server_restart"})   # le jeu se reconnecte tout seul, sans message d'erreur
        await asyncio.sleep(0.5)
        print(f"[maj] redémarrage après {int(time.time() - start)} s d'attente")
        os._exit(0)

    def refuse_new_match(self, c):
        """Nouvelle partie impossible : jeu à mettre à jour, ou serveur sur le point de redémarrer."""
        if c.outdated:
            latest = latest_release() or {}
            c.send({"t": "error", "code": "outdated", "required": latest.get("version", ""),
                    "msg": c.t("Votre jeu n'est pas à jour : la version {version} est requise.", version=latest.get("version", ""))})
            return True
        if self.draining:
            c.send({"t": "error", "code": "restarting",
                    "msg": c.t("Mise à jour du serveur en cours : les nouvelles parties en ligne reprennent dans un instant.")})
            return True
        return False

    # ------------------------------------------------------------ nouvelles versions
    async def watch_releases(self, interval=float(os.environ.get("ARCANES_RELEASE_POLL", "20"))):
        """Prévient les joueurs déjà connectés quand une nouvelle version est publiée.

        Les parties en cours continuent : le jeu affiche la proposition de mise à jour
        à la fin de la partie (ou tout de suite si le joueur est dans les menus)."""
        latest = latest_release()
        known = latest["version"] if latest else "0"
        while True:
            await asyncio.sleep(interval)
            latest = latest_release()
            if not latest or version_tuple(latest["version"]) <= version_tuple(known):
                continue
            known = latest["version"]
            msg = {"t": "new_version", "version": known}
            for c in list(self.online.values()):
                c.send(msg)
            print(f"Nouvelle version {known} publiée : {len(self.online)} joueur(s) prévenu(s)")

    # ------------------------------------------------------------ connexion
    async def handle(self, reader, writer):
        peer = writer.get_extra_info("peername")
        ip = peer[0] if peer else "?"
        if self.per_ip.get(ip, 0) >= self.MAX_PER_IP or sum(self.per_ip.values()) >= self.MAX_CLIENTS:
            writer.close()
            return
        self.per_ip[ip] = self.per_ip.get(ip, 0) + 1
        client = Client(self, reader, writer)
        print(f"[+] connexion {peer}")
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                if len(line) > REPLAY_MAX + 20000:
                    break
                try:
                    msg = json.loads(line.decode("utf-8"))
                except ValueError:
                    continue
                if not isinstance(msg, dict):
                    continue
                now = time.monotonic()
                client.rate_tokens = min(MSG_RATE[1], client.rate_tokens + (now - client.rate_ts) * MSG_RATE[0])
                client.rate_ts = now
                if client.rate_tokens < 1:
                    client.dropped += 1
                    if client.dropped > 200:
                        print(f"[!] {ip} : trop de messages, connexion fermée")
                        break
                    continue
                client.rate_tokens -= 1
                self.dispatch(client, msg)
                await writer.drain()
        except (ConnectionError, asyncio.IncompleteReadError, asyncio.LimitOverrunError, ValueError):
            pass
        finally:
            self.per_ip[ip] -= 1
            if self.per_ip[ip] <= 0:
                del self.per_ip[ip]
            self.room_watchers.discard(client)
            self.disconnect(client)
            writer.close()
            print(f"[-] déconnexion {peer}")

    def disconnect(self, client):
        self.leave_room(client)
        if client.token and self.online.get(client.token) is client:
            del self.online[client.token]
            self.push_presence(client.token)

    # ------------------------------------------------------------ messages
    def dispatch(self, c, msg):
        t = msg.get("t")
        if t == "hello":
            return self.on_hello(c, msg)
        if c.token is None:
            return c.send({"t": "error", "code": "not_logged", "msg": c.t("Identifiez-vous d'abord.")})
        handler = getattr(self, "on_" + str(t), None)
        if handler and t not in ("hello",):
            handler(c, msg)

    def on_hello(self, c, msg):
        if msg.get("version") != PROTOCOL_VERSION:
            return c.send({"t": "error", "code": "version", "msg": c.t("Version du jeu incompatible avec le serveur.")})
        latest = latest_release()
        c.game_version = str(msg.get("game_version", ""))[:16]
        # Jeu d'une version précédente : connexion acceptée pour finir (et faire valider) la partie en cours,
        # mais pas pour en commencer une nouvelle (voir refuse_new_match).
        c.outdated = bool(latest and version_tuple(c.game_version or "0") < version_tuple(latest["version"]))
        c.lang = msg.get("lang") if msg.get("lang") in LANGS else "fr"
        token = str(msg.get("token", ""))
        name = str(msg.get("name", "")).strip()
        avatar = self.clamp_avatar(msg.get("avatar", 1))
        if not NAME_RE.match(name):
            return c.send({"t": "error", "code": "name_invalid", "msg": c.t("Pseudo invalide (3 à 16 caractères : lettres, chiffres, - _ espace).")})
        owner = self.store.token_for_name(name)
        if token not in self.store.accounts:
            if owner is not None:
                return c.send({"t": "error", "code": "name_taken", "msg": c.t("Le pseudo « {name} » est déjà pris.", name=name)})
            if not self.may_create_account(c.ip):
                return c.send({"t": "error", "code": "too_many_accounts",
                               "msg": c.t("Trop de comptes créés depuis cette connexion : réessayez dans une heure.")})
            token = secrets.token_hex(16)
            self.store.new_account(token, name, avatar if avatar in base_avatars() else 1)   # 9 à 14 : à débloquer
        else:
            acc = self.store.accounts[token]
            if owner is not None and owner != token:
                return c.send({"t": "error", "code": "name_taken", "msg": c.t("Le pseudo « {name} » est déjà pris.", name=name)})
            acc["name"] = name
            acc["avatar"] = self.allowed_avatar(token, avatar)
        self.store.save()
        old = self.online.get(token)
        if old is not None and old is not c:
            old.send({"t": "error", "code": "replaced", "msg": old.t("Connecté depuis un autre endroit.")})
            old.token = None
            self.leave_room(old)
        c.token = token
        self.online[token] = c
        c.send({"t": "welcome", "token": token, "profile": self.profile(token)})
        if c.outdated:
            c.send({"t": "new_version", "version": latest["version"]})
        self.send_friends(c)
        self.push_presence(token)

    def may_create_account(self, ip):
        if ip in ("127.0.0.1", "::1"):
            return True   # tests locaux
        now = time.time()
        recent = [t for t in self.new_accounts.get(ip, []) if now - t < NEW_ACCOUNTS_PER_IP[1]]
        if len(recent) >= NEW_ACCOUNTS_PER_IP[0]:
            self.new_accounts[ip] = recent
            return False
        self.new_accounts[ip] = recent + [now]
        return True

    def on_set_lang(self, c, msg):
        if msg.get("lang") in LANGS:
            c.lang = msg["lang"]

    def on_set_profile(self, c, msg):
        name = str(msg.get("name", "")).strip()
        if not NAME_RE.match(name):
            return c.send({"t": "error", "code": "name_invalid", "msg": c.t("Pseudo invalide (3 à 16 caractères).")})
        owner = self.store.token_for_name(name)
        if owner is not None and owner != c.token:
            return c.send({"t": "error", "code": "name_taken", "msg": c.t("Le pseudo « {name} » est déjà pris.", name=name)})
        acc = c.account
        acc["name"] = name
        acc["avatar"] = self.allowed_avatar(c.token, msg.get("avatar", acc["avatar"]))
        self.store.save()
        c.send({"t": "profile", "profile": self.profile(c.token)})
        self.push_presence(c.token)

    def on_status(self, c, msg):
        st = msg.get("status")
        if st in ("online", "lobby", "in_game"):
            c.status = st
            self.push_presence(c.token)

    # ------------------------------------------------------------ amis
    def on_friend_request(self, c, msg):
        target = self.store.token_for_name(str(msg.get("name", "")).strip())
        me = c.account
        if target is None:
            return c.send({"t": "error", "code": "not_found", "msg": c.t("Aucun joueur ne porte ce pseudo.")})
        if target == c.token:
            return c.send({"t": "error", "code": "self", "msg": c.t("Vous ne pouvez pas vous ajouter vous-même.")})
        other = self.store.accounts[target]
        if target in me["friends"]:
            return c.send({"t": "info", "msg": c.t("{name} est déjà votre ami.", name=other['name'])})
        if target in me["incoming"]:
            return self.on_friend_respond(c, {"name": other["name"], "accept": True})
        if c.token not in other["incoming"]:
            other["incoming"].append(c.token)
        self.store.save()
        c.send({"t": "info", "msg": c.t("Demande d'ami envoyée à {name}.", name=other['name'])})
        self.send_friends(c)
        oc = self.online.get(target)
        if oc:
            oc.send({"t": "info", "msg": oc.t("{name} vous a envoyé une demande d'ami.", name=me['name'])})
            self.send_friends(oc)

    def on_friend_respond(self, c, msg):
        target = self.store.token_for_name(str(msg.get("name", "")))
        me = c.account
        if target is None or target not in me["incoming"]:
            return
        me["incoming"].remove(target)
        if msg.get("accept"):
            other = self.store.accounts[target]
            if target not in me["friends"]:
                me["friends"].append(target)
            if c.token not in other["friends"]:
                other["friends"].append(c.token)
            if c.token in other["incoming"]:
                other["incoming"].remove(c.token)
        self.store.save()
        self.send_friends(c)
        oc = self.online.get(target)
        if oc:
            if msg.get("accept"):
                oc.send({"t": "info", "msg": oc.t("{name} a accepté votre demande d'ami.", name=me['name'])})
            self.send_friends(oc)

    def on_friend_remove(self, c, msg):
        target = self.store.token_for_name(str(msg.get("name", "")))
        if target is None:
            return
        me = c.account
        other = self.store.accounts[target]
        for a, b in ((me, target), (other, c.token)):
            if b in a["friends"]:
                a["friends"].remove(b)
            if b in a["incoming"]:
                a["incoming"].remove(b)
        self.store.save()
        self.send_friends(c)
        oc = self.online.get(target)
        if oc:
            self.send_friends(oc)

    def on_get_friends(self, c, msg):
        self.send_friends(c)

    def send_friends(self, c):
        acc = c.account
        if acc is None:
            return
        friends = []
        for tok in acc["friends"]:
            a = self.store.accounts.get(tok)
            if a:
                oc = self.online.get(tok)
                friends.append(dict(self.public(tok), status=oc.status if oc else "offline"))
        friends.sort(key=lambda f: (f["status"] == "offline", f["name"].lower()))
        outgoing = [a["name"] for tok, a in self.store.accounts.items() if c.token in a["incoming"]]
        incoming = [self.store.accounts[t]["name"] for t in acc["incoming"] if t in self.store.accounts]
        c.send({"t": "friends", "friends": friends, "incoming": incoming, "outgoing": outgoing})

    def push_presence(self, token):
        """Prévient les amis connectés d'un changement de statut / profil."""
        acc = self.store.accounts.get(token)
        if not acc:
            return
        for tok in acc["friends"]:
            oc = self.online.get(tok)
            if oc:
                self.send_friends(oc)

    # ------------------------------------------------------------ messagerie
    def on_dm(self, c, msg):
        target = self.store.token_for_name(str(msg.get("to", "")))
        if target is None or target not in c.account["friends"]:
            return c.send({"t": "error", "code": "not_friend", "msg": c.t("Vous ne pouvez écrire qu'à vos amis.")})
        oc = self.online.get(target)
        if oc is None:
            return c.send({"t": "error", "code": "offline",
                           "msg": c.t("{name} n'est pas connecté : message non envoyé.", name=self.store.accounts[target]['name'])})
        text = CTRL_RE.sub(" ", str(msg.get("text", ""))).strip()[:DM_MAX_LEN]
        if not text:
            return
        now = time.monotonic()
        c.dm_times = [t for t in c.dm_times if now - t < DM_RATE[1]]
        if len(c.dm_times) >= DM_RATE[0]:
            return c.send({"t": "error", "code": "rate", "msg": c.t("Vous envoyez trop de messages : patientez quelques secondes.")})
        c.dm_times.append(now)
        ts = int(time.time())
        self.history.add_message(ts, c.token, target, text)
        out = {"t": "dm", "from": c.account["name"], "to": oc.account["name"], "text": text, "ts": ts}
        oc.send(out)
        c.send(out)

    def on_dm_history(self, c, msg):
        target = self.store.token_for_name(str(msg.get("with", "")))
        if target is None or target not in c.account["friends"]:
            return
        names = {c.token: c.account["name"], target: self.store.accounts[target]["name"]}
        rows = [{"from": names.get(f, "?"), "text": text, "ts": ts}
                for ts, f, text in self.history.conversation(c.token, target)]
        c.send({"t": "dm_history", "with": names[target], "messages": rows})

    # ------------------------------------------------------------ suggestions (forum)
    def on_suggest(self, c, msg):
        """Nouveau sujet : cartes visées (obligatoires pour un buff ou un nerf), type, texte."""
        raw = msg.get("cards", [])
        cards = []
        for x in raw if isinstance(raw, list) else []:
            x = str(x)
            if CARD_ID_RE.fullmatch(x) and x not in cards:
                cards.append(x)
        cards = cards[:SUGGEST_MAX_CARDS]
        kind = msg.get("kind") if msg.get("kind") in SUGGEST_KINDS else "autre"
        text = CTRL_RE.sub(" ", str(msg.get("text", ""))).strip()[:SUGGEST_MAX_LEN]
        if not text or (kind in ("buff", "nerf") and not cards):
            return c.send({"t": "error", "code": "suggest_invalid",
                           "msg": c.t("Choisissez au moins une carte et décrivez votre proposition.") if kind in ("buff", "nerf")
                           else c.t("Décrivez votre suggestion.")})
        now = int(time.time())
        if self.history.count_since("suggestions", c.token, now - SUGGEST_RATE[1]) >= SUGGEST_RATE[0]:
            return c.send({"t": "error", "code": "rate",
                           "msg": c.t("Trop de suggestions envoyées : réessayez dans une heure.")})
        sid = self.history.add_suggestion(now, c.token, c.account["name"], cards, kind, text, c.game_version)
        print(f"Suggestion #{sid} de {c.account['name']} ({kind}) : {', '.join(cards)} : {text}")
        c.sugg_view = sid
        c.send({"t": "sugg_thread", "created": True, "topic": self.history.suggestion_thread(sid)})

    def on_sugg_list(self, c, msg):
        kind = str(msg.get("kind", ""))
        search = CTRL_RE.sub(" ", str(msg.get("q", ""))).strip()[:60]
        raw = msg.get("cards", [])
        card_ids = [str(x) for x in (raw if isinstance(raw, list) else [])[:40] if CARD_ID_RE.fullmatch(str(x))]
        c.sugg_view = 0
        c.send({"t": "sugg_list", "kind": kind, "q": search,
                "topics": self.history.suggestion_topics(kind, search, card_ids)})

    def on_sugg_thread(self, c, msg):
        topic = self.history.suggestion_thread(_int(msg.get("id"), 0, 2 ** 62))
        if topic is None:
            return c.send({"t": "error", "code": "sugg_missing", "msg": c.t("Ce sujet n'existe plus.")})
        c.sugg_view = topic["id"]
        c.send({"t": "sugg_thread", "created": False, "topic": topic})

    def on_sugg_close(self, c, msg):
        c.sugg_view = 0

    def on_sugg_reply(self, c, msg):
        sid = _int(msg.get("id"), 0, 2 ** 62)
        text = CTRL_RE.sub(" ", str(msg.get("text", ""))).strip()[:REPLY_MAX_LEN]
        if not text:
            return
        now = int(time.time())
        if self.history.count_since("suggestion_replies", c.token, now - REPLY_RATE[1]) >= REPLY_RATE[0]:
            return c.send({"t": "error", "code": "rate",
                           "msg": c.t("Vous envoyez trop de messages : patientez quelques secondes.")})
        if self.history.suggestion_thread(sid) is None:
            return c.send({"t": "error", "code": "sugg_missing", "msg": c.t("Ce sujet n'existe plus.")})
        self.history.add_reply(sid, now, c.token, c.account["name"], text)
        topic = self.history.suggestion_thread(sid)
        # Fil mis à jour chez tous ceux qui le lisent (discussion en direct).
        for oc in list(self.online.values()):
            if oc is c or getattr(oc, "sugg_view", 0) == sid:
                oc.send({"t": "sugg_thread", "created": False, "topic": topic})

    # ------------------------------------------------------------ classement
    def ai_levels(self):
        """Bilans par niveau d'IA (historique), recalculés au plus toutes les 30 s."""
        now = time.time()
        if now - self._ai_levels_at > 30:
            self._ai_levels = self.history.ai_records()
            self._ai_levels_at = now
        return self._ai_levels

    def ranking(self):
        """Classement : [(token, ligne)], du premier au dernier."""
        rows = []
        levels = self.ai_levels()
        for tok, a in self.store.accounts.items():
            played = a["wins"] + a["losses"]
            ai_played = a["ai_wins"] + a["ai_losses"]
            rows.append((tok, {
                "name": a["name"], "avatar": a["avatar"],
                "wins": a["wins"], "losses": a["losses"],
                "winrate": round(100.0 * a["wins"] / played, 1) if played else 0.0,
                "ai_wins": a["ai_wins"], "ai_losses": a["ai_losses"],
                "ai_winrate": round(100.0 * a["ai_wins"] / ai_played, 1) if ai_played else 0.0,
                "ai_levels": [[w, n - w] for w, n in levels.get(tok, [[0, 0]] * 4)],
                "ai_score": ai_score(levels.get(tok)),
                "inferno": a.get("inferno_best", 0), "inferno_games": a.get("inferno_games", 0),
                "inferno_ts": a.get("inferno_best_ts", 0),
            }))
        rows.sort(key=lambda r: (-(r[1]["wins"] + r[1]["losses"] > 0), -r[1]["winrate"], -r[1]["wins"],
                                 -r[1]["ai_winrate"], r[1]["name"].lower()))
        return rows

    def champion_token(self):
        """N°1 du classement (il faut avoir joué au moins une partie en ligne)."""
        rows = self.ranking()
        if rows and rows[0][1]["wins"] + rows[0][1]["losses"] > 0:
            return rows[0][0]
        return None

    def on_leaderboard(self, c, msg):
        rows = []
        ranking = self.ranking()
        champ = ranking[0][0] if ranking and ranking[0][1]["wins"] + ranking[0][1]["losses"] > 0 else None
        for tok, r in ranking[:500]:
            r.update(self.public(tok, champ))
            r["online"] = tok in self.online
            r["me"] = tok == c.token
            rows.append(r)
        c.send({"t": "leaderboard", "rows": rows})

    # ------------------------------------------------------------ PO et passe de combat
    def grant(self, token, result, msg, ai_difficulty=None):
        """Pièces d'or + XP de passe pour une partie. result : "win" | "loss" | "draw".
        Une défaite rapporte toujours un peu, d'autant plus que la partie a duré ; un abandon presque rien."""
        acc = self.store.accounts.get(token)
        if acc is None:
            return None
        eco = COSMETICS.get("economy", {})
        turns = _int(msg.get("turns"), 0, 200)
        duration = _int(msg.get("duration"), 0, 10 ** 5)
        reason = _reason(msg.get("reason"))
        if duration < int(eco.get("min_duration", 45)):
            po = xp = 0
        elif result == "loss" and reason == "concede":
            po, xp = int(eco.get("concede_po", 1)), int(eco.get("concede_xp", 10))
        else:
            po = int(eco.get(result + "_po", 0)) + min(turns, int(eco.get("po_turns_cap", 24))) // 4 * int(eco.get("po_per_4_turns", 1))
            xp = int(eco.get(result + "_xp", 0)) + min(turns, int(eco.get("xp_turns_cap", 25))) * int(eco.get("xp_per_turn", 3))
        if ai_difficulty is not None:
            mult = eco.get("ai_mult", [0.5, 0.75, 1.0, 1.25])
            f = float(mult[min(ai_difficulty, len(mult) - 1)])
            po, xp = int(round(po * f)), int(round(xp * f))
        bonus = 0
        today = time.strftime("%Y-%m-%d", time.gmtime())
        if result == "win" and po > 0 and acc.get("first_win_day") != today:
            acc["first_win_day"] = today
            bonus = int(eco.get("first_win_of_day_po", 20))
        n, _start, _end = season_info()
        sea = acc.setdefault("seasons", {}).setdefault(str(n), {"xp": 0, "games": 0})
        before_lvl = pass_level(acc, n)
        sea["xp"] += xp
        sea["games"] += 1
        after_lvl = pass_level(acc, n)
        sea.setdefault("claimed", [])
        # Les récompenses du passe se récupèrent dans le passe de combat (on_claim_pass).
        acc["gold"] = acc.get("gold", 0) + po + bonus
        return {"t": "reward", "po": po, "bonus": bonus, "pass_po": 0, "xp": xp, "gold": acc["gold"],
                "season": n, "level": after_lvl, "level_up": after_lvl > before_lvl, "result": result,
                "claimable": len(claimable_levels(acc, n))}

    def on_claim_pass(self, c, msg):
        """Récupérer une récompense du passe de la saison en cours ({"level": n}) ou toutes ({"level": "all"})."""
        acc = c.account
        n, _start, _end = season_info()
        want = msg.get("level")
        todo = [lv for lv in claimable_levels(acc, n) if want == "all" or lv == _int(want, 0, 1000)]
        if not todo:
            return c.send({"t": "error", "code": "nothing_to_claim", "msg": c.t("Aucune récompense à récupérer.")})
        before = self.unlocked(c.token)
        rewards = {int(r["level"]): r for r in season_rewards(n)}
        po = sum(int(rewards[lv].get("po", 0)) for lv in todo)
        sea = acc.setdefault("seasons", {}).setdefault(str(n), {"xp": 0, "games": 0})
        sea.setdefault("claimed", []).extend(todo)
        acc["gold"] = acc.get("gold", 0) + po
        self.store.save()
        c.send({"t": "pass_claimed", "levels": todo, "po": po, "gold": acc["gold"]})
        self.notify_unlocks(c, before)   # profil à jour + objets débloqués (animation côté jeu)

    def on_shop_buy(self, c, msg):
        kind = msg.get("kind")
        if kind not in COSMETIC_KINDS:
            return
        item = next((it for it in COSMETICS.get(COSMETIC_KINDS[kind], []) if str(it["id"]) == str(msg.get("id"))), None)
        rule = (item or {}).get("rule") or {}
        if not item or "shop" not in rule:
            return c.send({"t": "error", "code": "not_for_sale", "msg": c.t("Cet objet n'est pas en vente.")})
        acc = c.account
        owned = acc.setdefault("owned", {}).setdefault(kind, [])
        if str(item["id"]) in [str(x) for x in owned]:
            return c.send({"t": "error", "code": "owned", "msg": c.t("Vous possédez déjà cet objet.")})
        price = int(rule["shop"])
        if acc.get("gold", 0) < price:
            return c.send({"t": "error", "code": "gold", "msg": c.t("Pas assez de pièces d'or : il vous faut {price} PO.", price=price)})
        before = self.unlocked(c.token)
        acc["gold"] -= price
        owned.append(item["id"])
        self.store.save()
        c.send({"t": "bought", "kind": kind, "id": item["id"], "gold": acc["gold"]})
        self.notify_unlocks(c, before)

    # ------------------------------------------------------------ parties enregistrées (anti-triche)
    def on_match_start(self, c, msg):
        """Début d'une partie : le serveur tire la graine et le premier joueur, puis validera la partie."""
        t = {"id": secrets.token_hex(8), "seed": secrets.randbelow(2 ** 31 - 1), "first": secrets.randbelow(2),
             "created": time.time(), "done": False}
        mode = msg.get("mode")
        if mode not in ("ai", "pvp"):
            return
        if c.outdated or (self.draining and mode == "pvp"):
            self.refuse_new_match(c)
            return c.send({"t": "match_ticket_refused"})
        t["version"] = c.game_version
        if mode == "ai":
            t.update(mode="ai", token=c.token, difficulty=_int(msg.get("difficulty", 1), 0, INFERNO))
            self.ai_tickets[c.token] = t
            if self.draining:
                self.save_tickets()
        elif mode == "pvp":
            room = c.room
            if room is None or room.host is not c or room.guest is None:
                return c.send({"t": "error", "code": "no_room", "msg": c.t("Aucun adversaire dans la partie.")})
            self.close_match(room)   # partie précédente non déclarée (revanche) : validée maintenant
            t.update(mode="pvp", host=room.host.token, guest=room.guest.token)
            room.ticket, room.log, room.pending = t, [], []
        c.send({"t": "match_ticket", "id": t["id"], "seed": t["seed"], "first": t["first"]})

    def flag(self, token, reason):
        """Trace d'une partie refusée (triche probable), consultable dans lobby_data.json."""
        acc = self.store.accounts.get(token)
        print(f"[triche ?] {acc['name'] if acc else token} : {reason}")
        if acc is not None:
            flags = acc.setdefault("cheat_flags", [])
            flags.append({"ts": int(time.time()), "reason": str(reason)[:200]})
            del flags[:-20]

    def reject_match(self, token, text):
        oc = self.online.get(token)
        if oc:
            oc.send({"t": "match_rejected", "msg": oc.t(text)})

    @staticmethod
    def add_stats(acc, stats):
        st = acc.setdefault("stats", {})
        if isinstance(stats, dict):
            for k in REPORTED_STATS:
                st[k] = st.get(k, 0) + _int(stats.get(k, 0), 0, 5000)

    def on_report_ai(self, c, msg):
        t = self.ai_tickets.get(c.token)
        if not t or t["id"] != str(msg.get("ticket", "")) or t["done"]:
            return c.send({"t": "match_rejected", "msg": c.t("Partie inconnue du serveur : elle n'est pas comptée.")})
        t["done"] = True
        del self.ai_tickets[c.token]
        if time.time() - t["created"] > TICKET_TTL:
            return c.send({"t": "match_rejected", "msg": c.t("Partie trop ancienne : elle n'est pas comptée.")})
        self.spawn(self.finalize_ai(c.token, t, msg))

    async def finalize_ai(self, token, t, msg):
        replay = msg.get("replay") if isinstance(msg.get("replay"), dict) else {}
        actions = replay.get("actions") if isinstance(replay.get("actions"), list) else []
        me = _int(replay.get("me", 0), 0, 1)
        ai = 1 - me
        inferno = t["difficulty"] == INFERNO
        if inferno:
            bonus = dict(INFERNO_BONUS, player=ai)
        else:
            bonus = dict(CHALLENGER_BONUS, player=ai) if t["difficulty"] == 3 else {}
        job = {"mode": "ai", "seed": t["seed"], "first": t["first"], "bonus": bonus, "difficulty": t["difficulty"],
               "ai": ai, "actions": actions[:4000]}
        played_on = t.get("version") or str(msg.get("game_version", ""))
        res = await self.verifier.run(job, played_on, VERIFY_TIMEOUT_INFERNO if inferno else None)
        acc = self.store.accounts.get(token)
        if acc is None:
            return
        if res is None:
            # Aucun vérificateur configuré (serveur de développement) : résultat déclaré par le jeu.
            res = {"ok": True, "winner": me if msg.get("won") else ai, "turns": _int(msg.get("turns")),
                   "reason": _reason(msg.get("reason")), "stats": [{}, {}], "cards": msg.get("cards"),
                   "actions": actions[:4000], "score": _int(msg.get("score"), 0, 10 ** 6)}
        if not res.get("ok"):
            if res.get("infra") or (played_on and res.get("version") and played_on != res.get("version")):
                # Vérificateur indisponible, ou partie jouée sur la version précédente pendant une mise à jour.
                print(f"[vérif] partie IA de {acc['name']} non vérifiable : {res.get('error')}")
                return self.reject_match(token, "Le serveur n'a pas pu vérifier la partie : elle n'est pas comptée.")
            self.flag(token, f"partie IA refusée : {res.get('error')}")
            self.store.save()
            return self.reject_match(token, "Partie refusée par le serveur (actions invalides) : elle n'est pas comptée.")
        winner = _int(res.get("winner"), 0, 2)
        if winner == 2:
            return
        won = winner == me
        duration = int(time.time() - t["created"])
        info = {"turns": _int(res.get("turns"), 0, 200), "duration": duration, "reason": _reason(res.get("reason"))}
        champion = self.champion_token()
        before = self.unlocked(token)
        score = _int(res.get("score"), 0, 10 ** 6) if inferno else None
        if inferno:
            # Inferno : ni victoire ni défaite au classement, seul le meilleur score compte.
            best = acc.get("inferno_best", 0)
            acc["inferno_games"] = acc.get("inferno_games", 0) + 1
            if score > best:
                acc["inferno_best"] = score
                acc["inferno_best_ts"] = int(time.time())
            self.add_stats(acc, (res.get("stats") or [{}, {}])[me])
            reward = self.grant(token, "loss", info, 3)
            if reward:
                extra = min(score // INFERNO_SCORE_PO[0], INFERNO_SCORE_PO[1]) if info["duration"] >= 45 else 0
                acc["gold"] = acc.get("gold", 0) + extra
                reward.update(po=reward["po"] + extra, gold=acc["gold"], result="inferno", score=score,
                              best=max(best, score), record=score > best)
        else:
            acc["ai_wins" if won else "ai_losses"] += 1
            if won:
                lv = acc.setdefault("ai_beaten", {})
                lv[str(t["difficulty"])] = lv.get(str(t["difficulty"]), 0) + 1
            self.update_streak(acc, won)
            self.add_stats(acc, (res.get("stats") or [{}, {}])[me])
            reward = self.grant(token, "win" if won else "loss", info, t["difficulty"])
        self.store.save()
        oc = self.online.get(token)
        if oc:
            if reward:
                oc.send(reward)
            self.notify_unlocks(oc, before)
        self.check_champion(champion)
        tokens = [token, None] if me == 0 else [None, token]
        rep_data = dict(replay, seed=t["seed"], first=t["first"], bonus=bonus, difficulty=t["difficulty"],
                        actions=res.get("actions", actions))
        self.history.add(cards=_verified_cards(res, tokens, winner), replay=_replay_json(rep_data),
                         first_won=1 if t["first"] == winner else 0,
                         ts=int(time.time()), mode="ai", p1_token=token, p1_name=acc["name"],
                         winner=1 if won else 2, difficulty=t["difficulty"], turns=info["turns"], duration=duration,
                         reason=info["reason"], game_version=str(played_on)[:16], score=score)
        if oc:
            oc.send({"t": "profile", "profile": self.profile(token)})

    def on_report_pvp(self, c, msg):
        """Fin de partie signalée par l'un des joueurs : le serveur valide la partie qu'il a enregistrée."""
        room = c.room
        if room is None or not room.ticket or room.ticket["done"]:
            return
        if c is room.host and msg.get("winner") in ("host", "guest", "draw"):
            room.ticket["claim"] = msg.get("winner")   # utilisé seulement sans vérificateur (développement)
        room.ticket["version"] = str(msg.get("game_version", ""))[:16]
        self.close_match(room)

    def close_match(self, room, leaver=None):
        """Valide (en tâche de fond) la partie en cours du salon ; leaver : joueur parti avant la fin (0/1)."""
        t = room.ticket
        if not t or t["done"]:
            return
        t["done"] = True
        if leaver == 1 and room.pending_since(STALLED_REQUEST_S):
            leaver = None   # l'hôte ne traitait plus les demandes de l'invité : pas de pénalité
        log = room.log
        room.ticket, room.log, room.pending = None, [], []
        self.spawn(self.finalize_pvp(t, log, leaver))

    async def finalize_pvp(self, t, log, leaver):
        job = {"mode": "pvp", "seed": t["seed"], "first": t["first"], "events": log}
        if leaver is not None:
            job["leaver"] = leaver
        tokens = [t["host"], t["guest"]]
        res = await self.verifier.run(job, t.get("version", ""))
        if res is None:
            claim = t.get("claim")
            if claim is None and leaver is None:
                return
            winner = {"host": 0, "guest": 1, "draw": 2}.get(claim, 1 - (leaver or 0))
            res = {"ok": True, "winner": winner, "turns": 0, "reason": "disconnect" if claim is None else "normal",
                   "stats": [{}, {}], "cards": None, "actions": []}
        if not res.get("ok"):
            err = str(res.get("error", ""))
            if err == "partie non terminée":
                return   # partie abandonnée sans résultat (salon fermé, hôte bloqué...)
            played_on = t.get("version", "")
            if res.get("infra") or (played_on and res.get("version") and played_on != res.get("version")):
                print(f"[vérif] partie en ligne non vérifiable : {err}")
            else:
                self.flag(t["host"], f"partie en ligne refusée : {err}")   # l'hôte fait autorité
                self.store.save()
            for tok in tokens:
                self.reject_match(tok, "Le serveur n'a pas pu valider la partie : elle n'est pas comptée.")
            return
        winner = _int(res.get("winner"), 0, 2)
        accs = [self.store.accounts.get(tok) for tok in tokens]
        if None in accs:
            return
        duration = int(time.time() - t["created"])
        info = {"turns": _int(res.get("turns"), 0, 200), "duration": duration, "reason": _reason(res.get("reason"))}
        day = time.strftime("%Y-%m-%d", time.gmtime())
        pair = (day,) + tuple(sorted(tokens))
        self.pair_games = {k: v for k, v in self.pair_games.items() if k[0] == day}
        self.pair_games[pair] = self.pair_games.get(pair, 0) + 1
        counted = self.pair_games[pair] <= PAIR_DAILY_CAP
        champion = self.champion_token()
        befores = {tok: self.unlocked(tok) for tok in tokens}
        rewards = {}
        if counted:
            if winner != 2:
                accs[winner]["wins"] += 1
                accs[1 - winner]["losses"] += 1
                self.update_streak(accs[winner], True)
                self.update_streak(accs[1 - winner], False)
            else:
                for a in accs:
                    a["draws"] = a.get("draws", 0) + 1
            for side, tok in enumerate(tokens):
                self.add_stats(accs[side], (res.get("stats") or [{}, {}])[side])
                result = "draw" if winner == 2 else ("win" if winner == side else "loss")
                # L'abandon ne pénalise que celui qui abandonne (le perdant).
                rewards[tok] = self.grant(tok, result, info if result == "loss" else dict(info, reason="normal"))
        self.store.save()
        for tok in tokens:
            oc = self.online.get(tok)
            if not oc:
                continue
            if rewards.get(tok):
                oc.send(rewards[tok])
            elif not counted:
                oc.send({"t": "info", "msg": oc.t("Plus de {cap} parties aujourd'hui contre le même adversaire : "
                                                  "celle-ci n'est pas comptée (classement, PO, passe).", cap=PAIR_DAILY_CAP)})
            self.notify_unlocks(oc, befores[tok])
        self.check_champion(champion)
        names = [a["name"] for a in accs]
        rep_data = {"seed": t["seed"], "first": t["first"], "me": 0, "difficulty": 0, "bonus": {},
                    "game": t.get("version", ""), "names": names, "avatars": [a.get("avatar", 1) for a in accs],
                    "actions": res.get("actions", [])}
        self.history.add(cards=_verified_cards(res, tokens, winner) if counted else [], replay=_replay_json(rep_data),
                         first_won=(1 if t["first"] == winner else 0) if winner != 2 else None,
                         ts=int(time.time()), mode="pvp", p1_token=tokens[0], p1_name=names[0],
                         p2_token=tokens[1], p2_name=names[1], winner={0: 1, 1: 2, 2: 0}[winner],
                         turns=info["turns"], duration=duration, reason=info["reason"],
                         game_version=t.get("version", ""))
        for tok in tokens:
            oc = self.online.get(tok)
            if oc:
                oc.send({"t": "profile", "profile": self.profile(tok)})

    # ------------------------------------------------------------ personnalisation
    @staticmethod
    def update_streak(acc, won):
        acc["streak"] = acc.get("streak", 0) + 1 if won else 0
        acc["best_streak"] = max(acc.get("best_streak", 0), acc["streak"])
        acc["loss_streak"] = 0 if won else acc.get("loss_streak", 0) + 1
        acc["worst_loss_streak"] = max(acc.get("worst_loss_streak", 0), acc["loss_streak"])

    def unlocked(self, token, champion=None):
        """Éléments débloqués par un compte : {kind: [ids]}."""
        acc = self.store.accounts[token]
        stats = stat_values(acc)
        if champion is None:
            champion = token == self.champion_token()
        out = {}
        for kind, key in COSMETIC_KINDS.items():
            out[kind] = [it["id"] for it in COSMETICS.get(key, []) if rule_ok(it.get("rule"), stats, champion, acc, kind, it["id"])]
        if not out["avatar"]:
            out["avatar"] = sorted(base_avatars())
        return out

    def equipped(self, token, unlocked=None):
        """Personnalisation effective (un élément qui n'est plus débloqué revient à celui par défaut)."""
        acc = self.store.accounts[token]
        unlocked = unlocked or self.unlocked(token)
        eq = dict(DEFAULT_EQUIP)
        eq.update(acc.get("equipped", {}))
        for kind in DEFAULT_EQUIP:
            if COSMETICS and eq[kind] not in unlocked[kind]:
                eq[kind] = DEFAULT_EQUIP[kind]
        return eq

    def public(self, token, champion_tok=False):
        """Ce que les autres joueurs voient : pseudo, avatar, titre, contour (le n°1 a le contour Champion)."""
        acc = self.store.accounts[token]
        champion = token == (self.champion_token() if champion_tok is False else champion_tok)
        eq = self.equipped(token, self.unlocked(token, champion))
        return {"name": acc["name"], "avatar": acc["avatar"], "title": eq["title"], "card_back": eq["card_back"],
                "board": eq.get("board", "default"),
                "border": "champion" if champion else eq["border"], "champion": champion}

    def notify_unlocks(self, c, before):
        after = self.unlocked(c.token)
        names = {kind: {it["id"]: it["name"] for it in COSMETICS.get(key, [])} for kind, key in COSMETIC_KINDS.items()}
        new = [{"kind": k, "id": i, "name": names[k].get(i, str(i))} for k in after for i in after[k] if i not in before.get(k, [])]
        c.send({"t": "profile", "profile": self.profile(c.token)})
        if new:
            c.send({"t": "unlocked", "items": new})

    def check_champion(self, previous):
        """Le n°1 a changé : on met à jour le profil de l'ancien et du nouveau champion connectés."""
        now = self.champion_token()
        if now == previous:
            return
        for tok in (previous, now):
            oc = self.online.get(tok) if tok else None
            if oc:
                oc.send({"t": "profile", "profile": self.profile(tok)})
                self.push_presence(tok)
        if now and now in self.online:
            self.online[now].send({"t": "unlocked", "items": [{"kind": "border", "id": "champion", "name": "Champion (n°1 du classement)"}]})

    def on_report_stats(self, c, msg):
        """Ancien protocole : les statistiques sont désormais calculées en rejouant la partie."""
        return

    def on_equip(self, c, msg):
        kind = msg.get("kind")
        if kind not in COSMETIC_KINDS:
            return
        item = msg.get("id")
        if kind == "avatar":
            item = _int(item, 1, MAX_AVATAR)
        if item not in self.unlocked(c.token)[kind]:
            return c.send({"t": "error", "code": "locked", "msg": c.t("Cet élément n'est pas encore débloqué.")})
        if kind == "avatar":
            c.account["avatar"] = item
        else:
            c.account.setdefault("equipped", {})[kind] = item
        self.store.save()
        c.send({"t": "profile", "profile": self.profile(c.token)})
        self.push_presence(c.token)

    def on_history(self, c, msg):
        # Historique d'un joueur (par défaut soi-même), les plus récentes d'abord.
        name = str(msg.get("name", "")).strip()
        token = self.store.token_for_name(name) if name else c.token
        if token is None:
            return c.send({"t": "error", "code": "unknown_player", "msg": c.t("Joueur « {name} » introuvable.", name=name)})
        total, rows = self.history.for_player(token, _int(msg.get("limit", 100), 1, 500))
        c.send({"t": "history", "name": self.store.accounts[token]["name"], "total": total, "rows": rows})

    def on_replay(self, c, msg):
        data = self.history.replay(_int(msg.get("id"), 0, 2 ** 62))
        if data is None:
            return c.send({"t": "error", "code": "no_replay", "msg": c.t("Replay indisponible pour cette partie.")})
        c.send(dict(data, t="replay"))

    def on_global_stats(self, c, msg):
        mode = msg.get("mode") if msg.get("mode") in ("all", "pvp", "ai") else "all"
        c.send(dict(self.history.global_stats(mode), t="global_stats"))

    def rank_rows(self, c, tokens=None):
        """Lignes du classement (avec le rang), éventuellement limitées à certains joueurs."""
        ranking = self.ranking()
        champ = ranking[0][0] if ranking and ranking[0][1]["wins"] + ranking[0][1]["losses"] > 0 else None
        rows = []
        for i, (tok, r) in enumerate(ranking):
            if tokens is not None and tok not in tokens:
                continue
            r.update(self.public(tok, champ))
            r["rank"] = i + 1
            r["online"] = tok in self.online
            r["me"] = tok == c.token
            rows.append(r)
        return rows

    def on_search_players(self, c, msg):
        q = str(msg.get("q", "")).strip().lower()[:16]
        if not q:
            return c.send({"t": "players_found", "q": q, "rows": []})
        found = {tok for tok, a in self.store.accounts.items() if q in a["name"].lower()}
        rows = self.rank_rows(c, found)[:50]
        c.send({"t": "players_found", "q": q, "rows": rows})

    def on_player_profile(self, c, msg):
        name = str(msg.get("name", "")).strip()
        token = self.store.token_for_name(name) if name else c.token
        if token is None:
            return c.send({"t": "error", "code": "unknown_player", "msg": c.t("Joueur « {name} » introuvable.", name=name)})
        rows = self.rank_rows(c, {token})
        acc = self.store.accounts[token]
        st = stat_values(acc)
        out = rows[0] if rows else dict(self.public(token), name=acc["name"])
        out.update({"t": "player_profile", "games": st["games"], "draws": acc.get("draws", 0),
                    "streak": acc.get("streak", 0), "best_streak": st["best_streak"],
                    "friend": token in (c.account or {}).get("friends", []),
                    "favorites": self.history.favorite_cards(token),
                    "stats": {k: st.get(k, 0) for k in ("minions_played", "spells_played", "enchants_played",
                                                         "hero_damage", "enchants_destroyed")}})
        c.send(out)

    # ------------------------------------------------------------ salons / invitations
    def rooms_listing(self):
        rooms = [r.listing() for r in self.rooms.values()]
        order = {"waiting": 0, "full": 1, "in_game": 2}
        rooms.sort(key=lambda r: (order[r["state"]], -r["created"]))
        return rooms[:200]

    def broadcast_rooms(self):
        if not self.room_watchers:
            return
        msg = {"t": "rooms", "rooms": self.rooms_listing()}
        for w in list(self.room_watchers):
            w.send(msg)

    def on_watch_rooms(self, c, msg):
        # L'écran Multijoueur s'abonne à la liste des parties (mise à jour en direct).
        if msg.get("on", True):
            self.room_watchers.add(c)
            c.send({"t": "rooms", "rooms": self.rooms_listing()})
        else:
            self.room_watchers.discard(c)

    def on_create_room(self, c, msg):
        if self.refuse_new_match(c):
            return
        self.leave_room(c)
        name = re.sub(r"[\x00-\x1f]", "", str(msg.get("name", ""))).strip()[:32]
        room = Room(c, name)
        self.rooms[room.id] = room
        c.room = room
        c.status = "lobby"
        self.push_presence(c.token)
        c.send({"t": "room", "room": room.describe(), "role": "host"})
        self.broadcast_rooms()

    def on_invite(self, c, msg):
        room = c.room
        if room is None or room.host is not c:
            return c.send({"t": "error", "code": "no_room", "msg": c.t("Créez d'abord une partie.")})
        target = self.store.token_for_name(str(msg.get("name", "")))
        if target is None or target not in c.account["friends"]:
            return c.send({"t": "error", "code": "not_friend", "msg": c.t("Vous ne pouvez inviter que vos amis.")})
        oc = self.online.get(target)
        if oc is None:
            return c.send({"t": "error", "code": "offline", "msg": c.t("Ce joueur n'est pas connecté.")})
        oc.send(dict(self.public(c.token), t="invite", **{"from": c.account["name"], "room": room.id}))
        c.send({"t": "info", "msg": c.t("Invitation envoyée à {name}.", name=oc.account['name'])})

    def on_join_room(self, c, msg):
        if self.refuse_new_match(c):
            return
        room = self.rooms.get(str(msg.get("room", "")))
        if room is None:
            return c.send({"t": "error", "code": "room_gone", "msg": c.t("Cette partie n'existe plus.")})
        if room.guest is not None and room.guest is not c:
            return c.send({"t": "error", "code": "room_full", "msg": c.t("Cette partie est déjà complète.")})
        if room.host is c:
            return
        self.leave_room(c)
        room.guest = c
        c.room = room
        c.status = "lobby"
        self.push_presence(c.token)
        desc = room.describe()
        c.send({"t": "room", "room": desc, "role": "guest"})
        room.host.send({"t": "room", "room": desc, "role": "host"})
        self.broadcast_rooms()

    def on_leave_room(self, c, msg):
        self.leave_room(c)

    def leave_room(self, c):
        room = c.room
        if room is None:
            return
        if room.ticket and not room.ticket["done"] and room.guest is not None:
            self.close_match(room, leaver=0 if c is room.host else 1)   # partir = abandonner
        c.room = None
        if c.token:
            c.status = "online"
            self.push_presence(c.token)
        other = room.other(c)
        if room.host is c:
            self.rooms.pop(room.id, None)
            if other:
                other.room = None
                other.status = "online"
                other.send({"t": "room_closed", "msg": other.t("L'hôte a fermé la partie.")})
                self.push_presence(other.token)
        else:
            room.guest = None
            room.in_game = False
            if other:
                other.send({"t": "peer_left"})
                other.send({"t": "room", "room": room.describe(), "role": "host"})
        self.broadcast_rooms()

    def on_relay(self, c, msg):
        room = c.room
        if room is None:
            return
        other = room.other(c)
        kind = msg.get("kind")
        args = msg.get("args", [])
        if kind not in RELAY_KINDS or not isinstance(args, list) or len(args) > 8:
            return
        if kind in HOST_ONLY and room.host is not c:
            return
        if kind == "_request" and room.guest is not c:
            return
        args = list(args)
        t = room.ticket
        if kind == "_hello":
            # Identité et personnalisation fournies par le serveur (pas de pseudo ni d'objet usurpé).
            while len(args) < 5:
                args.append("")
            look = self.public(c.token)
            args[0], args[1], args[4] = look["name"], look["avatar"], look
        elif kind == "_start":
            if not t or t["done"] or len(args) < 6 or args[0] != t["seed"] or args[1] != t["first"] or other is None:
                return c.send({"t": "error", "code": "no_ticket", "msg": c.t("Partie non enregistrée par le serveur.")})
            host_look = self.public(c.token)
            args[2], args[3], args[4], args[5] = host_look["name"], host_look["avatar"], other.account["name"], host_look
        elif kind == "_chat":
            args = [CTRL_RE.sub("", str(args[0] if args else ""))[:200]]
        elif t and not t["done"] and kind in ("_request", "_apply", "_reject"):
            if len(room.log) >= RELAY_LOG_MAX:
                return
            if kind == "_request" and args and isinstance(args[0], dict):
                room.log.append(["q", args[0]])
                room.pending.append(time.time())
            elif kind == "_apply" and len(args) >= 2 and isinstance(args[1], dict):
                room.log.append(["a", _int(args[0], 0, 1), args[1]])
                if _int(args[0], 0, 1) == 1 and room.pending:
                    room.pending.pop(0)
            elif kind == "_reject":
                room.log.append(["r"])
                if room.pending:
                    room.pending.pop(0)
        if other:
            other.send({"t": "relay", "kind": kind, "args": args})
            if kind == "_start" and not room.in_game:
                room.in_game = True
                self.broadcast_rooms()

    # ------------------------------------------------------------ utilitaires
    def profile(self, token):
        a = self.store.accounts[token]
        out = {k: a[k] for k in ("name", "avatar", "wins", "losses", "ai_wins", "ai_losses")}
        out["inferno_best"] = a.get("inferno_best", 0)
        champion = token == self.champion_token()
        unlocked = self.unlocked(token, champion)
        out["unlocked"] = unlocked
        out["equipped"] = self.equipped(token, unlocked)
        out["stats"] = stat_values(a)
        out["champion"] = champion
        out["border"] = "champion" if champion else out["equipped"]["border"]
        out["title"] = out["equipped"]["title"]
        out["gold"] = a.get("gold", 0)
        n, start, end = season_info()
        levels, per = season_conf()
        xp = a.get("seasons", {}).get(str(n), {}).get("xp", 0)
        out["season"] = {"n": n, "start": start, "end": end, "xp": xp, "level": pass_level(a, n), "levels": levels,
                         "xp_per_level": per, "name": COSMETICS.get("seasons", {}).get("names", {}).get(str(n), ""),
                         "rewards": season_rewards(n), "games": a.get("seasons", {}).get(str(n), {}).get("games", 0),
                         "claimed": sorted(claimed_levels(a, n)), "claimable": claimable_levels(a, n)}
        out["loss_streak"] = a.get("loss_streak", 0)
        return out

    def allowed_avatar(self, token, v):
        """Avatar demandé s'il est débloqué, sinon l'avatar actuel (ou 1)."""
        v = self.clamp_avatar(v)
        if token in self.store.accounts and v not in self.unlocked(token)["avatar"]:
            return self.store.accounts[token].get("avatar", 1)
        return v if v in base_avatars() or token in self.store.accounts else 1

    @staticmethod
    def clamp_avatar(v):
        try:
            v = int(v)
        except (TypeError, ValueError):
            v = 1
        return max(1, min(MAX_AVATAR, v))


def base_avatars():
    """Avatars au choix dès la création du compte (sans condition dans cosmetics.json) : 1 à 8 et 15."""
    return {a["id"] for a in COSMETICS.get("avatars", []) if not a.get("rule")} or set(range(1, 9))


LANDING_PAGE = """<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Arcanes &amp; Lames</title><link rel="icon" href="/favicon.ico">
<style>
body{{margin:0;background:#1a1220;color:#f5e9d0;font-family:system-ui,sans-serif;display:flex;min-height:100vh;align-items:center;justify-content:center}}
main{{max-width:680px;padding:32px;border:3px solid #f2c14e;background:#2b1d14;border-radius:6px;margin:16px}}
h1{{color:#f2c14e;margin-top:0}} h3{{color:#f2c14e;margin-bottom:6px}} small{{color:#c9b79a}} li{{margin:6px 0}}
a.btn,button{{display:inline-block;background:#c98a2b;color:#1a1220;padding:10px 18px;font-weight:bold;
text-decoration:none;border-radius:4px;border:0;cursor:pointer;font-size:15px}}
.cmd{{display:flex;gap:8px;align-items:stretch;margin:10px 0}}
code{{flex:1;background:#120c16;border:1px solid #6b5a3c;padding:10px;border-radius:4px;color:#9fd8ff;
font-size:13px;overflow-wrap:anywhere}}
.tabs{{display:flex;gap:6px;flex-wrap:wrap;margin:18px 0 0}}
.tabs button{{background:#3d2a1c;color:#f5e9d0;border:2px solid #6b5a3c;border-bottom:0;border-radius:4px 4px 0 0}}
.tabs button.on{{background:#c98a2b;color:#1a1220;border-color:#c98a2b}}
.os{{display:none;border:2px solid #6b5a3c;padding:4px 18px 14px;border-radius:0 4px 4px 4px}} .os.on{{display:block}}
</style></head><body><main>
<h1>Arcanes &amp; Lames</h1>
<p>Jeu de cartes médiéval-fantastique en pixel art. Version actuelle : <b>{version}</b></p>
<div class="tabs"><button data-os="windows">Windows</button><button data-os="macos">macOS</button><button data-os="linux">Linux</button></div>

<section class="os" id="windows">
<h3>Installation recommandée (Windows 10/11)</h3>
<ol><li>Appuyez sur <b>Windows + R</b>, collez la commande ci-dessous puis <b>Entrée</b> :</li></ol>
<div class="cmd"><code>{install_cmd}</code><button class="copy">Copier</button></div>
<p><small>Le jeu est téléchargé en HTTPS, son empreinte et sa signature « Arcanes &amp; Lames » sont vérifiées,
puis il est installé (sans droits administrateur) avec un raccourci sur le Bureau. Aucun avertissement Windows.</small></p>
<h3>Ou téléchargement manuel</h3>
{download_windows}
<p><small>Windows peut alors afficher « Windows a protégé votre ordinateur » : <i>Informations complémentaires</i>
puis <i>Exécuter quand même</i>. Empreinte du certificat de signature : <code style="font-size:11px">{thumbprint}</code>
(<a href="/arcanes_codesign.cer" style="color:#9fd8ff">certificat</a>).</small></p>
</section>

<section class="os" id="macos">
<h3>Installation recommandée (macOS 11 ou plus récent, Intel et Apple Silicon)</h3>
<ol><li>Ouvrez le <b>Terminal</b> (Launchpad &gt; Autres &gt; Terminal), collez la commande ci-dessous puis <b>Entrée</b> :</li></ol>
<div class="cmd"><code>{install_sh}</code><button class="copy">Copier</button></div>
<p><small>Le jeu est téléchargé en HTTPS, son empreinte est vérifiée, puis il est installé dans
<i>~/Applications</i> (sans mot de passe administrateur) et lancé. Aucun avertissement de macOS.</small></p>
<h3>Ou téléchargement manuel</h3>
{download_macos}
<p><small>Décompressez le zip et glissez « Arcanes &amp; Lames » dans Applications. Le jeu n'étant pas enregistré
auprès d'Apple, macOS bloque la première ouverture : ouvrez <i>Réglages Système &gt; Confidentialité et sécurité</i>
puis cliquez sur <i>Ouvrir quand même</i>.</small></p>
</section>

<section class="os" id="linux">
<h3>Installation recommandée (Linux x86_64)</h3>
<ol><li>Ouvrez un terminal, collez la commande ci-dessous puis <b>Entrée</b> :</li></ol>
<div class="cmd"><code>{install_sh}</code><button class="copy">Copier</button></div>
<p><small>Le jeu est téléchargé en HTTPS, son empreinte est vérifiée, puis il est installé dans
<i>~/.local/share/ArcanesEtLames</i> (sans sudo) avec un raccourci dans le menu des applications.</small></p>
<h3>Ou téléchargement manuel</h3>
{download_linux}
<p><small>Décompressez l'archive puis lancez <i>ArcanesEtLames.x86_64</i>. Nécessite une carte graphique compatible Vulkan.</small></p>
</section>

<p>Ensuite, choisissez votre pseudo dans <b>Paramètres &gt; Profil</b> : vous êtes connecté au serveur.
Les mises à jour s'installent automatiquement au lancement du jeu.</p>
<p><small>Nouveautés : {notes}</small></p>
<script>
function show(os){{document.querySelectorAll('.os,.tabs button').forEach(function(e){{
e.classList.toggle('on',e.id===os||e.dataset.os===os)}})}}
document.querySelectorAll('.tabs button').forEach(function(b){{b.onclick=function(){{show(b.dataset.os)}}}});
document.querySelectorAll('button.copy').forEach(function(b){{b.onclick=function(){{
navigator.clipboard.writeText(b.previousElementSibling.innerText);b.innerText='Copié !'}}}});
var p=(navigator.userAgentData&&navigator.userAgentData.platform)||navigator.platform||'';
show(/mac/i.test(p)?'macos':/linux|x11/i.test(p)&&!/android/i.test(navigator.userAgent)?'linux':'windows');
</script>
</main></body></html>"""


class UpdateHttpServer:
    """Mini serveur HTTP (lecture seule) :
    GET /                 page de téléchargement du jeu
    GET /version.json     dernière version publiée
    GET /files/<x>.pck    paquet de mise à jour
    GET /download/<x>.zip jeu complet (première installation ; .tar.gz pour Linux)
    GET /install.ps1, /install.sh  installateurs en une ligne (Windows ; Linux et macOS)"""

    CHUNK = 64 * 1024
    CTYPES = {".pck": "application/octet-stream", ".zip": "application/zip", ".gz": "application/gzip",
              ".apk": "application/vnd.android.package-archive"}
    STATIC = {
        "/install.ps1": ("install.ps1", "text/plain; charset=utf-8"),
        "/install.sh": ("install.sh", "text/plain; charset=utf-8"),
        "/arcanes_codesign.cer": ("arcanes_codesign.cer", "application/pkix-cert"),
        "/favicon.ico": ("favicon.ico", "image/x-icon"),
    }
    SITE_TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".webp": "image/webp", ".ttf": "font/ttf",
                  ".woff2": "font/woff2", ".css": "text/css; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                  ".mp4": "video/mp4", ".vtt": "text/vtt; charset=utf-8"}
    WEB_BASE = "https://arcanes.example.com"

    async def handle(self, reader, writer):
        try:
            request = await asyncio.wait_for(reader.readline(), 10)
            byte_range = ""
            for _ in range(100):  # en-têtes (100 lignes au plus) : seul Range sert (avance dans la vidéo)
                line = await asyncio.wait_for(reader.readline(), 10)
                if line in (b"\r\n", b"\n", b""):
                    break
                if line[:6].lower() == b"range:":
                    byte_range = line[6:].decode("latin-1").strip()
            parts = request.decode("latin-1").split()
            if len(parts) < 2 or parts[0] not in ("GET", "HEAD"):
                return await self.reply(writer, 405, b"Methode non autorisee")
            path = unquote(parts[1].split("?")[0])
            head = parts[0] == "HEAD"
            if path == "/version.json":
                latest = latest_release()
                if latest is None:
                    return await self.reply(writer, 404, b"Aucune version publiee")
                body = json.dumps(latest, ensure_ascii=False).encode("utf-8")
                return await self.reply(writer, 200, body, "application/json; charset=utf-8", head)
            if path in ("/", "/index.html"):
                return await self.reply(writer, 200, self.landing(), "text/html; charset=utf-8", head)
            if path.startswith("/site/"):
                name = os.path.basename(path[len("/site/"):])   # pas de sous-dossier ni de ../
                ctype = self.SITE_TYPES.get(os.path.splitext(name)[1].lower())
                full = os.path.join(UPDATES_DIR, "site", name)
                if not ctype or name == "index.html" or not os.path.isfile(full):
                    return await self.reply(writer, 404, b"Fichier introuvable")
                return await self.send_file(writer, full, ctype, head, byte_range, cache=86400)
            if path in self.STATIC:
                name, ctype = self.STATIC[path]
                full = os.path.join(UPDATES_DIR, name)
                if not os.path.isfile(full):
                    return await self.reply(writer, 404, b"Fichier introuvable")
                with open(full, "rb") as f:
                    return await self.reply(writer, 200, f.read(), ctype, head)
            prefix = "/files/" if path.startswith("/files/") else "/download/" if path.startswith("/download/") else ""
            if prefix:
                name = os.path.basename(path[len(prefix):])  # pas de sous-dossier ni de ../
                ext = os.path.splitext(name)[1]
                full = os.path.join(UPDATES_DIR, name)
                if (prefix == "/files/" and ext != ".pck") or (prefix == "/download/" and not name.endswith((".zip", ".tar.gz", ".apk"))) \
                        or not os.path.isfile(full):
                    return await self.reply(writer, 404, b"Fichier introuvable")
                size = os.path.getsize(full)
                writer.write(self.headers(200, size, self.CTYPES[ext]))
                if not head:
                    with open(full, "rb") as f:
                        while chunk := f.read(self.CHUNK):
                            writer.write(chunk)
                            await writer.drain()
                await writer.drain()
                print(f"[maj] {name} envoyé à {writer.get_extra_info('peername')}")
                return
            await self.reply(writer, 404, b"Introuvable")
        except (asyncio.TimeoutError, ConnectionError):
            pass
        finally:
            writer.close()

    @staticmethod
    def landing():
        # Page d'accueil générée à la publication (tools/site, voir publish_update.py) ; sinon page simple ci-dessous.
        try:
            with open(os.path.join(UPDATES_DIR, "site", "index.html"), "rb") as f:
                return f.read()
        except OSError:
            pass
        import html
        latest = latest_release() or {}
        downloads = dict(latest.get("downloads") or {})
        if "windows" not in downloads and latest.get("download"):   # latest.json d'avant les versions Linux/macOS
            downloads["windows"] = {"file": latest["download"]}
        labels = {"windows": "le zip Windows", "macos": "le zip macOS", "linux": "l'archive Linux"}
        blocks = {}
        for key, label in labels.items():
            name = os.path.basename(str((downloads.get(key) or {}).get("file", "")))
            full = os.path.join(UPDATES_DIR, name)
            if name and os.path.isfile(full):
                blocks["download_" + key] = (f'<p><a class="btn" href="/download/{html.escape(name)}">'
                                             f'Télécharger {label} ({os.path.getsize(full) / 1048576:.0f} Mo)</a></p>')
            else:
                blocks["download_" + key] = "<p><i>Le téléchargement sera bientôt disponible.</i></p>"
        install_cmd = f'powershell -c "irm {UpdateHttpServer.WEB_BASE}/install.ps1 | iex"'
        install_sh = f"curl -fsSL {UpdateHttpServer.WEB_BASE}/install.sh | sh"
        return LANDING_PAGE.format(version=html.escape(str(latest.get("version", "—"))),
                                   install_cmd=html.escape(install_cmd, quote=False),
                                   install_sh=html.escape(install_sh, quote=False),
                                   thumbprint=html.escape(str(latest.get("codesign_thumbprint", "—"))),
                                   notes=html.escape(str(latest.get("notes", "")) or "—"), **blocks).encode("utf-8")

    async def send_file(self, writer, full, ctype, head, byte_range="", cache=0):
        """Envoie un fichier par morceaux ; « Range: bytes=a-b » donne une réponse 206 (avance dans la vidéo)."""
        size = os.path.getsize(full)
        start, end, code, extra = 0, size - 1, 200, "Accept-Ranges: bytes\r\n"
        m = re.fullmatch(r"bytes=(\d*)-(\d*)", byte_range.replace(" ", ""))
        if m and (m.group(1) or m.group(2)):
            if m.group(1):
                start = int(m.group(1))
                end = min(int(m.group(2)), size - 1) if m.group(2) else size - 1
            else:   # « bytes=-n » : les n derniers octets
                start = max(0, size - int(m.group(2)))
            if start > end:
                writer.write(self.headers(416, 0, ctype, extra=f"Content-Range: bytes */{size}\r\n"))
                return await writer.drain()
            code, extra = 206, extra + f"Content-Range: bytes {start}-{end}/{size}\r\n"
        writer.write(self.headers(code, end - start + 1, ctype, cache, extra))
        if not head:
            with open(full, "rb") as f:
                f.seek(start)
                left = end - start + 1
                while left > 0 and (chunk := f.read(min(self.CHUNK, left))):
                    writer.write(chunk)
                    left -= len(chunk)
                    await writer.drain()
        await writer.drain()

    @staticmethod
    def headers(code, length, ctype, cache=0, extra=""):
        reason = {200: "OK", 206: "Partial Content", 404: "Not Found", 405: "Method Not Allowed",
                  416: "Range Not Satisfiable"}.get(code, "OK")
        cc = f"public, max-age={cache}" if cache else "no-cache"
        return (f"HTTP/1.1 {code} {reason}\r\nContent-Type: {ctype}\r\nContent-Length: {length}\r\n{extra}"
                f"Cache-Control: {cc}\r\nConnection: close\r\n\r\n").encode("latin-1")

    async def reply(self, writer, code, body, ctype="text/plain; charset=utf-8", head=False, cache=0):
        writer.write(self.headers(code, len(body), ctype, cache))
        if not head:
            writer.write(body)
        await writer.drain()


async def main():
    global UPDATES_DIR
    ap = argparse.ArgumentParser(description="Serveur communautaire d'Arcanes & Lames")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=7778)
    ap.add_argument("--update-port", type=int, default=0, help="port HTTP des mises à jour (défaut : port + 1)")
    ap.add_argument("--data", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "lobby_data.json"))
    ap.add_argument("--history", default="", help="base SQLite de l'historique (défaut : history.db à côté de --data)")
    ap.add_argument("--updates-dir", default=UPDATES_DIR, help="dossier de latest.json, des .pck et du .zip")
    here = os.path.dirname(os.path.abspath(__file__))
    default_cosm = os.path.join(here, "cosmetics.json")
    if not os.path.exists(default_cosm):
        default_cosm = os.path.join(here, "..", "data", "cosmetics.json")   # dépôt du jeu (développement)
    ap.add_argument("--cosmetics", default=default_cosm, help="catalogue de personnalisation (data/cosmetics.json)")
    default_i18n = os.path.join(here, "i18n")
    if not os.path.isdir(default_i18n):
        default_i18n = os.path.join(here, "..", "data", "i18n")
    ap.add_argument("--i18n", default=default_i18n, help="dossier des traductions (data/i18n du jeu)")
    ap.add_argument("--tls-port", type=int, default=0, help="port TLS du jeu (0 = désactivé)")
    ap.add_argument("--tls-cert", default="", help="certificat (fullchain.pem)")
    ap.add_argument("--tls-key", default="", help="clé privée du certificat")
    ap.add_argument("--verifier-godot", default="", help="exécutable Godot (sans affichage) qui rejoue les parties")
    ap.add_argument("--verifier-project", default="", help="dossier du projet (sinon : dernier paquet publié)")
    ap.add_argument("--verifier-dir", default="", help="dossier de travail du vérificateur")
    args = ap.parse_args()
    load_cosmetics(args.cosmetics)
    load_i18n(args.i18n)
    UPDATES_DIR = args.updates_dir
    history_path = args.history or os.path.join(os.path.dirname(os.path.abspath(args.data)), "history.db")
    server = LobbyServer(args.data, history_path)
    server.verifier = Verifier(args.verifier_godot, args.verifier_project,
                               args.verifier_dir or os.path.join(os.path.dirname(os.path.abspath(args.data)), "verifier"))
    print("Vérification des parties : " + ("activée" if server.verifier.configured() else
                                          "DÉSACTIVÉE (résultats déclarés par les joueurs, développement uniquement)"))
    srv = await asyncio.start_server(server.handle, args.host, args.port, limit=REPLAY_MAX + 65536)
    servers = [srv]
    if args.tls_port:
        ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(args.tls_cert, args.tls_key)
        servers.append(await asyncio.start_server(server.handle, args.host, args.tls_port, ssl=ctx,
                                                  ssl_handshake_timeout=15, limit=REPLAY_MAX + 65536))
        print(f"Connexions chiffrées (TLS) sur le port {args.tls_port}")
    update_port = args.update_port or args.port + 1
    http = await asyncio.start_server(UpdateHttpServer().handle, args.host, update_port)
    print(f"Serveur Arcanes & Lames à l'écoute sur {args.host}:{args.port} (données : {args.data})")
    latest = latest_release()
    print(f"Mises à jour servies sur le port {update_port} : " +
          (f"version {latest['version']} requise" if latest else "aucune version publiée (updates/latest.json)"))
    try:
        # systemctl reload arcanes-lobby -> SIGUSR1 : redémarrage sans couper les parties (voir request_restart).
        asyncio.get_running_loop().add_signal_handler(signal.SIGUSR1, server.request_restart)
    except (AttributeError, NotImplementedError, RuntimeError):
        pass   # Windows (développement)
    await asyncio.gather(*(s.serve_forever() for s in servers), http.serve_forever(), server.watch_releases())


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("Arrêt du serveur.")
