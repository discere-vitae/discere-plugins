# discere-plugins

Plugins für [Claude Code](https://code.claude.com) aus der discere-Suite. Das Repo ist eine Plugin-Sammlung
(Marketplace) mit dem Namen **discere**. Im Repo steht nichts Geheimes: Die Schlüssel bleiben auf den Rechnern.

## Plugin «process»

Für die Arbeit mit [discere process](https://process.discere.ch) in Claude Code (Tasks P120, P127 und P129,
Definition P113 §6.4).

- **Vier Hooks** melden Beginn, Prompt, Antwort und Ende jeder Sitzung an process. Gesendet werden nur die Art des
  Signals und die Kennung der Sitzung; den Zeitpunkt setzt process bei der Ankunft. Nie gesendet werden Prompts,
  Antworten, Ordner oder Dateinamen. Aus den Zeitpunkten rechnet process die Menschenzeit für den Tagesabschluss.
- **Beim Beginn** bekommt Claude die Kennung der Sitzung (für `arbeit_beginnen`), die eigenen offenen Aufgaben (nur
  Nummer und Status) und die Ordner der Ablage dieses Rechners: den kDrive-Ordner und den Arbeitsordner, je wenn
  eingestellt (siehe «Ordner der Ablage»). Die Ordner auch dann, wenn kein Signal ankommt.
- **Der Skill «Arbeiten mit process»** sagt Claude, wann `kontext` und wann `arbeit_beginnen`.
- **Die Werkzeuge** (`kontext`, `arbeit_beginnen` …) kommen nicht aus dem Plugin, sondern vom Connector «discere
  process» in claude.ai. Er erscheint in Claude Code von selbst.

### Einrichten, einmal je Rechner

1. **Signal-Schlüssel anlegen.** In process: Menü oben rechts → Profil → KI-Verbindungen → «Neuer Schlüssel».
   Bezeichnung etwa «Claude Code Laptop», Zweck **«nur Signale»**. Den Schlüssel kopieren — er ist nur jetzt
   sichtbar.
2. **Plugin installieren**, in Claude Code:

   ```text
   /plugin marketplace add discere-vitae/discere-plugins
   /plugin install process@discere
   ```

   Ab Claude Code 2.1.275 geht es auch in einem Schritt:
   `/plugin install process --marketplace discere-vitae/discere-plugins`.
   Beim Aktivieren fragt Claude Code nach dem Signal-Schlüssel und, freiwillig, nach dem kDrive-Ordner und dem
   Arbeitsordner. Fragt es nicht (etwa nach `claude plugin install` im Terminal), dann in Claude Code
   `/plugin configure process@discere`. Danach Claude Code neu starten.
3. **Connector verbinden**, falls noch nicht geschehen: in claude.ai unter Einstellungen → Connectors «discere
   process», mit **demselben process-Login** wie der Signal-Schlüssel. Sonst gehören die Signale einer anderen
   Person als die Arbeit.
4. **Prüfen:** eine neue Sitzung beginnen und fragen: «Was steht in process an?»

**Voraussetzungen:** unter Windows Git for Windows (Claude Code führt die Hooks in Git Bash aus); unter macOS git
(macOS bietet die Installation beim ersten Mal an) und curl (ist dabei). Ein Proxy, der TLS aufbricht, geht nur,
wenn sein Zertifikat im System hinterlegt ist: Zertifikate aus Umgebungsvariablen (`SSL_CERT_FILE` …) nimmt das
Skript bewusst nicht, sonst kommen die Signale nicht an («nicht erreichbar»).

### Ordner der Ablage

Eine Aufgabe oder ein Projekt in process kann eine Ablage haben: wo die Dateien liegen. process kennt davon nur die
Wurzel, den Pfad ab ihr und einen Link, nie den Ordner auf dem Rechner. Den nennen zwei freiwillige Einstellungen:

| Wurzel | Einstellung | Beispiel |
|---|---|---|
| `kdrive` | kDrive-Ordner | `C:\Users\…\kDrive`, `/Users/…/kDrive` |
| `arbeitsordner` | Arbeitsordner | ein lokaler Ordner, etwa `C:\AI` |

- Beide bleiben auf dem Rechner. Das Skript gibt sie nur Claude in den Zusatzkontext, ohne Steuerzeichen; ein Ordner
  über 500 Byte fällt ganz weg, ebenso ein Wert mit `dpk_` (ein Signal-Schlüssel im falschen Feld). An process gehen
  sie nie.
- Jeder Ordner unter dem Arbeitsordner kann eine Ablage werden — und eine Ablage setzen in process alle, die die
  Aufgabe ändern dürfen. Den Arbeitsordner also bewusst wählen. Bevor Claude in einer Ablage zum ersten Mal liest
  oder schreibt, nennt es den aufgelösten Ordner. Hat die Ablage einer Aufgabe jemand anderes gesetzt (process sagt
  es Claude, P129), fragt es vorher nach — ebenso bei einem Pfad, der nur im Text der Aufgabe steht und aus der Ablage
  hinausführt. Ordner mit `.` vorne (`.git`, `.claude`) und Kurznamen von Windows (`GIT~1`)
  lehnt process als Ablage ab.
- Ist ein Ordner nicht eingestellt, sagt Claude der Person, dass die Dateien dieser Wurzel auf einem anderen Rechner
  liegen.
- Ändern: in Claude Code `/plugin configure process@discere`, danach Claude Code neu starten.

### Wenn process nicht antwortet

Eine Sitzung bleibt nie hängen. Die Hooks enden immer ohne Fehler.

- **Prompt und Antwort** laufen im Hintergrund; der Prompt wartet nie.
- **Beginn:** höchstens 4 s. Kommt er nicht an, steht eine Zeile da, etwa «discere process: nicht erreichbar …»,
  und Claude arbeitet wie ohne Plugin. Die Ordner der Ablage bekommt Claude trotzdem (ab 1.1.1): Sie brauchen weder
  den Schlüssel noch process.
- **Ende:** höchstens 1 s. Claude Code gibt allen Hooks am Ende zusammen 1,5 s.
- **Nichts wird nachgesendet:** process nimmt die Ankunftszeit, und eine Zeit vom Rechner liesse sich fälschen.
  Fehlende Zeit trägst du im Tagesabschluss nach. Kommt kein Ende an, schliesst process die Sitzung nach 30 Minuten
  ohne Signal beim letzten Signal («bitte prüfen»).

### Schlüssel

- Ein Signal-Schlüssel darf nur Signale der eigenen Sitzungen schreiben und die eigenen offenen Aufgaben lesen
  (Nummer und Status). Er ist kein Connector-Schlüssel.
- Claude Code legt ihn als geheimen Wert ab (`sensitive`), nicht in `settings.json`: unter macOS im Schlüsselbund,
  unter Windows in `~/.claude/.credentials.json` (Abschnitt `pluginSecrets`, dieselbe Datei, in der Claude Code seine
  eigene Anmeldung hält). Nur die Hooks bekommen ihn, als `CLAUDE_PLUGIN_OPTION_SIGNAL_SCHLUESSEL`; in der Umgebung
  von Claudes Shell steht er nicht.
- Das Skript gibt ihn curl über stdin, nie in der Befehlszeile, und schreibt ihn nie in eine Datei oder Ausgabe.
- **Neuer Schlüssel** (nach einem Widerruf oder nach einem Jahr): in Claude Code `/plugin configure process@discere`
  und den neuen Schlüssel eingeben, danach Claude Code neu starten. Im Terminal geht es auch, ohne Datei, aus der
  Zwischenablage über stdin:
  - macOS: `printf '{"signal_schluessel":"%s"}\n' "$(pbpaste)" | claude plugin configure process@discere --values-stdin`
  - PowerShell: `@{signal_schluessel = (Get-Clipboard -Raw).Trim()} | ConvertTo-Json -Compress | claude plugin configure process@discere --values-stdin`

  Nie den Schlüssel in eine Datei legen, und nie `--config signal_schluessel=…`: Dann stünde er in der Befehlszeile
  und im Verlauf der Shell.
- Widerrufen im Profil von process wirkt sofort. Ein Schlüssel läuft nach einem Jahr ab.

### Abschalten

- **Ganz:** `/plugin`, dann «process» deaktivieren (oder im Terminal `claude plugin disable process@discere`).
- **Für einen Ordner,** etwa für private Arbeit: in dessen `.claude/settings.local.json`
  `{"enabledPlugins": {"process@discere": false}}`.

### Aktualisieren

Ein Update kommt nur mit einer neuen Version in `plugin.json`. Holen in Claude Code über `/plugin` → Marketplaces →
discere, oder im Terminal mit `claude plugin update process@discere`. Das automatische Update bleibt für diese
Sammlung aus (Vorgabe von Claude Code): Ein Update bringt Code, der in jeder Sitzung läuft — vorher ansehen, was
sich geändert hat.

- **1.1.1** (P129): Die Ordner der Ablage stehen auch dann im Zusatzkontext, wenn kein Signal ankommt (Schlüssel
  fehlt oder ist ungültig, curl fehlt, process ist nicht erreichbar oder antwortet mit einem Fehler). Bisher hiess es
  dann, sie seien nicht eingestellt. Der Skill: Hat jemand anderes die Ablage einer Aufgabe gesetzt, fragt Claude vor
  dem ersten Lesen oder Schreiben dort nach; ebenso bei einem Pfad, der nur im Text der Aufgabe steht und aus der Ablage
  hinausführt (oder wenn sie keine hat). Härtungen: Ein Wert mit `dpk_` in einem Ordner-Feld fällt weg; Funktionen
  `[` und `test` aus der Umgebung entfernt das Skript wie die übrigen.
- **1.1.0** (P127): die Einstellung «Arbeitsordner (freiwillig)» und im Zusatzkontext beide Ordner der Ablage. Nach
  dem Update den Arbeitsordner mit `/plugin configure process@discere` eintragen (oder leer lassen).
- **1.0.0** (P120): Hooks, Signal-Schlüssel, kDrive-Ordner, Skill.

## Entwickeln

- **Tests:** `node --test test/signal.test.mjs`. Sie laufen bei jedem PR auf Linux (sh = dash), macOS (bash 3.2) und
  Windows (Git Bash). Statt process antwortet eine Attrappe auf 127.0.0.1. Ein gefälschtes curl zeigt, dass der
  Schlüssel nie in der Befehlszeile steht. Wächter prüfen die Plugin-Dateien.
- **Prüfen:** `claude plugin validate --strict .` und `claude plugin validate --strict plugins/process`.
- **Version:** `version` in `plugins/process/.claude-plugin/plugin.json` und `VERSION` in `signal.sh` gemeinsam
  erhöhen (ein Test prüft das).
- **main ist geschützt** (G101, G108): Branch → PR → Merge.
