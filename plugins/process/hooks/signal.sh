#!/bin/sh
# discere process — Hook-Skript des Plugins «process» (P120; Definition P113 §6.4 und §7).
#
# Aufruf aus hooks/hooks.json:   /bin/sh signal.sh beginn|prompt|antwort|ende
#
# Was es tut:
# - Es meldet einen Zeitpunkt an process: POST /api/ki/signal mit {"art","client_ref"}. Die Zeit
#   setzt process bei der Ankunft. Inhalte gibt es keine.
# - Vom Eingang (JSON von Claude Code auf stdin) liest es nur die Kennung der Sitzung (session_id).
#   Alles andere, auch den Text eines Prompts, verwirft es ungelesen.
# - Beim Beginn gibt es Claude einen Zusatzkontext: die Kennung der Sitzung (für «arbeit_beginnen»),
#   die eigenen offenen Aufgaben (nur Nummer und Status, beides geprüft) und die Ordner der Ablage
#   dieses Rechners (P127: kDrive-Ordner und Arbeitsordner, je eine Einstellung des Plugins). Die
#   Ordner bleiben auf dem Rechner, sie gehen nie an process. Kommt der Beginn nicht an, sieht die
#   Person eine Zeile, und Claude arbeitet wie ohne Plugin.
#
# Was es nie tut:
# - Mit einem Fehler enden: immer Exit 0. Ein Exit 2 hielte den Prompt oder das Ende auf.
# - Lange warten: der Beginn höchstens 4 s, das Ende 1 s (Claude Code gibt allen Hooks am Ende
#   zusammen 1,5 s, und Git Bash braucht selbst einen Teil davon); Prompt und Antwort laufen im
#   Hintergrund (hooks.json: async), mit 3 s.
# - Nachsenden: process nimmt die Ankunftszeit; eine Zeit vom Rechner liesse sich fälschen.
# - Den Signal-Schlüssel zeigen: Er steht nie in der Befehlszeile (curl bekommt ihn über stdin),
#   nie in einer Ausgabe, nie in einer Datei und nicht in der Umgebung der Hilfsprozesse. curl liest
#   keine ~/.curlrc (-q zuerst) und folgt keiner Weiterleitung.
#
# Läuft mit jedem POSIX-sh: dash (Linux), bash 3.2 (macOS), Git Bash (Windows). Geprüft in
# test/signal.test.mjs, dort auch mit einem gefälschten curl, das seine Befehlszeile festhält.

# Zuerst die Umgebung zähmen (Security-Durchsicht P120):
# - keine Shell-Optionen von aussen: SHELLOPTS=xtrace zeigte sonst jede Zeile samt Schlüssel auf
#   stderr, allexport legte jede Variable (Schlüssel, Anfang des Prompts) in die Umgebung der
#   Hilfsprozesse, errexit brächte einen anderen Exit als 0;
# - keine Funktionen von aussen (bash importiert exportierte Funktionen auch als sh): eine Funktion
#   «printf» oder «curl» bekäme sonst den Schlüssel. set, unset und exit sind spezielle Builtins,
#   die keine Funktion ersetzen kann;
# - die Werkzeuge zuerst aus den Ordnern des Systems: ein curl, head oder cat in ~/bin oder einem
#   relativen Ordner bekäme sonst Schlüssel oder Prompt (Git für Windows legt curl je nach Fassung in
#   /ucrt64, /mingw64 oder auf ARM64 in /clangarm64);
# - keine Variablen, die TLS schwächen (Mitschnitt der Sitzungsschlüssel, fremde Zertifikate);
# - keine Vorbelegung der eigenen Variablen (Security-Durchsicht P127): Stünde eine davon schon in
#   der Umgebung, behielte sie nach POSIX ihr Export-Kennzeichen, und Schlüssel, Eingang oder Ordner
#   landeten in der Umgebung der Hilfsprozesse.
set +aeuvx
unset -f printf command curl head cat tail sed tr grep awk 2>/dev/null
PATH=/usr/bin:/bin:/ucrt64/bin:/mingw64/bin:/clangarm64/bin${PATH:+:$PATH}
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR
unset ADRESSE VERSION art schluessel kdrive arbeit eingang wert sid rest antwort liste code frist fehlt kontext
LC_ALL=C
# Git Bash (Windows) wandelt sonst Argumente, die wie Pfade aussehen, für curl.exe um.
MSYS_NO_PATHCONV=1
MSYS2_ARG_CONV_EXCL='*'
export PATH LC_ALL MSYS_NO_PATHCONV MSYS2_ARG_CONV_EXCL

ADRESSE='https://process.discere.ch'
VERSION='1.1.0'

art=${1-}
case $art in
beginn | prompt | antwort | ende) ;;
*) exit 0 ;;
esac

# Die Einstellungen des Plugins: in Variablen der Shell übernehmen und aus der Umgebung nehmen,
# bevor der erste Hilfsprozess startet — dessen Umgebung liesse sich sonst von aussen lesen.
schluessel=${CLAUDE_PLUGIN_OPTION_SIGNAL_SCHLUESSEL-}
kdrive=${CLAUDE_PLUGIN_OPTION_KDRIVE_WURZEL-}
arbeit=${CLAUDE_PLUGIN_OPTION_ARBEITSORDNER-}
unset CLAUDE_PLUGIN_OPTION_SIGNAL_SCHLUESSEL CLAUDE_PLUGIN_OPTION_KDRIVE_WURZEL CLAUDE_PLUGIN_OPTION_ARBEITSORDNER

# Beim Beginn ohne Signal: eine Zeile für die Person (systemMessage) und für Claude der Hinweis,
# ohne «client_ref» zu arbeiten — eine Sitzung mit «client_ref», deren Signale fehlen, zählte
# die Werkzeug-Aufrufe nicht (process rechnet sie nur Sitzungen ohne Kennung an). Beide Texte
# sind fest; hier kommt nichts von aussen hinein.
ohne() {
  if [ "$art" = beginn ]; then
    printf '{"systemMessage":"discere process: %s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"discere process (Plugin): Die Signale dieser Sitzung kommen nicht an (%s). Arbeite mit dem Connector «discere process» wie ohne Plugin: «arbeit_beginnen» und «arbeit_beenden» ohne «client_ref»."}}\n' "$1" "$2"
  fi
  exit 0
}

# Eingang: Nur der Anfang zählt (dort steht session_id); der Rest wird verworfen.
eingang=$(head -c 8192 2>/dev/null)
cat >/dev/null 2>&1

# session_id: der Wert nach dem ersten «"session_id":"» (Claude Code schreibt JSON ohne Leerraum;
# mit einem Leerzeichen nach dem Doppelpunkt geht es auch), bis zum nächsten Anführungszeichen.
# In einem JSON-Text steht ein Anführungszeichen in einem Wert nur als \" — der Text eines Prompts
# kann also kein «"session_id":"» enthalten. Nur mit Mustern der Shell, in linearer Zeit: unter
# Git Bash kostet jeder Prozess Zeit, und ein Eingang voller Leerzeichen darf nichts aufhalten.
case $eingang in
*'"session_id":"'*) wert=${eingang#*'"session_id":"'} ;;
*'"session_id": "'*) wert=${eingang#*'"session_id": "'} ;;
*) wert= ;;
esac
eingang=
sid=
case $wert in
*'"'*) sid=${wert%%'"'*} ;;
esac
wert=
case $sid in
'' | *[!A-Za-z0-9_-]*) sid= ;;
esac
[ ${#sid} -le 200 ] || sid=
[ -n "$sid" ] || ohne 'Kennung der Sitzung fehlt – diese Sitzung zählt nicht.' 'Kennung der Sitzung fehlt'

# Der Signal-Schlüssel: Leerraum vom Einfügen weg, dann nur in der genauen Form «dpk_» und 43
# Zeichen base64url. Alles andere gilt als fehlend — so kommt auch nichts in die Anweisungen an
# curl, was dort nicht hingehört.
[ ${#schluessel} -le 200 ] || schluessel=
while :; do
  case $schluessel in
  [[:space:]]*) schluessel=${schluessel#?} ;;
  *[[:space:]]) schluessel=${schluessel%?} ;;
  *) break ;;
  esac
done
rest=${schluessel#dpk_}
case $schluessel in
dpk_*) ;;
*) rest= ;;
esac
case $rest in
*[!A-Za-z0-9_-]*) rest= ;;
esac
[ ${#rest} -eq 43 ] || rest=
rest=${rest:+ok}
if [ -z "$rest" ]; then
  schluessel=
  ohne 'Signal-Schlüssel fehlt – diese Sitzung zählt nicht. Einrichten unter /plugin → process.' 'Signal-Schlüssel fehlt'
fi

command -v curl >/dev/null 2>&1 || ohne 'curl fehlt auf diesem Rechner – diese Sitzung zählt nicht.' 'curl fehlt'

case $art in
beginn) frist=4 ;;
ende) frist=1 ;;
*) frist=3 ;;
esac

# Höchstens 64 KiB Antwort: Mehr braucht es nie, und ein fehlgeleiteter Server soll nicht den
# Speicher füllen oder den Beginn über seine Frist bringen.
antwort=$(printf 'header = "Authorization: Bearer %s"\n' "$schluessel" |
  curl -q -K - -s --connect-timeout 2 --max-time "$frist" --max-filesize 65536 \
    -H 'Content-Type: application/json' -H 'Accept: application/json' \
    -A "discere-plugin-process/$VERSION" \
    --data-binary "{\"art\":\"$art\",\"client_ref\":\"$sid\"}" \
    -o - -w '\n%{http_code}' "$ADRESSE/api/ki/signal" 2>/dev/null)
schluessel=

[ "$art" = beginn ] || exit 0

code=$(printf '%s\n' "$antwort" | tail -n 1)
case $code in
[0-9][0-9][0-9]) ;;
*) code=000 ;;
esac
case $code in
200) ;;
000) ohne 'nicht erreichbar – die Zeit dieser Sitzung fehlt vielleicht (im Tagesabschluss nachtragen).' 'process nicht erreichbar' ;;
401) ohne 'Signal-Schlüssel ungültig, abgelaufen oder widerrufen – diese Sitzung zählt nicht. Neuen Schlüssel im Profil anlegen.' 'Signal-Schlüssel ungültig' ;;
403) ohne 'kein Zugang (keine Firma mit «Aufgaben») – diese Sitzung zählt nicht.' 'kein Zugang' ;;
409) ohne 'nimmt gerade keine neue Sitzung an (zu viele offen) – im Tagesabschluss aufräumen.' 'zu viele offene Sitzungen' ;;
429) ohne 'zu viele Signale in kurzer Zeit – diese Sitzung zählt vielleicht nicht.' 'zu viele Signale' ;;
*) ohne "antwortet mit Fehler $code – die Zeit dieser Sitzung fehlt vielleicht." "Fehler $code" ;;
esac

# Die offenen Aufgaben aus der Antwort: nur Paare, deren Nummer (Kürzel und Zahl) genau so aussieht,
# wie process sie schreibt, und deren Status einer der drei offenen ist (process:
# OFFENE_STATUS, Vertragstest signal-kontext.test.ts). Kein anderer Text kommt in den Kontext.
liste=$(printf '%s\n' "$antwort" | sed '$d' | tr -d '\r\n' |
  grep -o -E '"nummer":"[A-Z]{1,2}[0-9]{1,9}","status":"(offen|in_arbeit|wartet)"' 2>/dev/null |
  head -n 20 |
  sed -e 's/^"nummer":"\([A-Z0-9]*\)","status":"\([a-z_]*\)"$/\1 (\2)/' -e 's/(in_arbeit)/(in Arbeit)/' |
  awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
antwort=

# Die Ordner der Ablage kommen aus den Einstellungen des Plugins (vom Menschen gesetzt): je ohne
# Steuerzeichen, mit maskiertem \ und " für den JSON-Text, höchstens 500 Byte (sonst weg). Ein
# leerer Ordner kostet keinen Hilfsprozess.
if [ -n "$kdrive" ]; then
  [ ${#kdrive} -le 2000 ] || kdrive=
  kdrive=$(printf '%s' "$kdrive" | tr -d '\000-\037\177')
  [ ${#kdrive} -le 500 ] || kdrive=
  kdrive=$(printf '%s' "$kdrive" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
fi
if [ -n "$arbeit" ]; then
  [ ${#arbeit} -le 2000 ] || arbeit=
  arbeit=$(printf '%s' "$arbeit" | tr -d '\000-\037\177')
  [ ${#arbeit} -le 500 ] || arbeit=
  arbeit=$(printf '%s' "$arbeit" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
fi
fehlt='hier nicht eingestellt – Dateien mit dieser Wurzel liegen auf einem anderen Rechner; sag das der Person'

kontext="discere process (Plugin): Diese Claude-Code-Sitzung meldet ihre Zeitpunkte an process (Beginn, Prompt, Antwort, Ende; keine Inhalte)."
kontext="$kontext\\n- Kennung dieser Sitzung: $sid. Gib sie bei «arbeit_beginnen» und «arbeit_beenden» (Connector «discere process») als «client_ref» mit."
kontext="$kontext\\n- Meine offenen Aufgaben (Nummer und Status): ${liste:-keine}. Inhalte liest du mit «aufgabe_lesen»."
kontext="$kontext\\n- Ablage einer Aufgabe oder eines Projekts («aufgabe_lesen», «arbeit_beginnen», «projekt_lesen»): Ihr Pfad gilt ab dem Ordner ihrer «wurzel» auf diesem Rechner; bleib darunter."
kontext="$kontext\\n  - «kdrive», der kDrive-Ordner: ${kdrive:-$fehlt}"
kontext="$kontext\\n  - «arbeitsordner», der Arbeitsordner: ${arbeit:-$fehlt}"
kontext="$kontext\\n- Arbeit an einer Aufgabe oder einem Projekt rahmst du mit «arbeit_beginnen» und «arbeit_beenden» ein (Skill «Arbeiten mit process»)."

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$kontext"
exit 0
