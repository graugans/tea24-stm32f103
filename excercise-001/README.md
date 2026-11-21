# Übungsaufgabe 001: Rollladensteuerung mit Zustandsautomat

> **Worum geht es?**
> Sie erweitern eine kleine Rollladensteuerung auf dem STM32F103. Der
> Zustandsautomat steht als **Übergangstabelle im Flash** (`.rodata`).
> Ob Ihre Steuerung richtig arbeitet, prüfen automatische Tests, ganz ohne
> Hardware im Emulator Renode.

## Notwendige git-Kommandos

```sh
git fetch --all
# neuen lokalen Branch auf Basis der Aufgabe anlegen
git switch -c solution-001 upstream/exercise-001
# ... Änderungen ...
git add excercise-001
git commit -m "feat: solve exercise-001 roller shutter state machine"
git push -u origin solution-001
```

## Die Anlage

Stellen Sie sich einen Rollladen mit Elektromotor vor. Die Steuerung hat
zwei Taster und zwei Endschalter. Der Motor wird über zwei Relais
geschaltet, eines je Drehrichtung, wie bei einer Wendeschützschaltung.

```text
                 Nucleo-F103RB
              +-----------------+
 Taste hoch --| PC0         PB8 |-- Relais K1: Motor hoch
Taste runter--| PC1         PB9 |-- Relais K2: Motor runter
 ES oben    --| PC2         PA5 |-- LED LD2:   Motor läuft
 ES unten   --| PC3         PA2 |-- USART2 TX: Statusmeldungen (115200 Baud)
              +-----------------+
 Eingänge aktiv low mit Pull-up (wie Taster B1 auf dem Nucleo)
```

Die Relais gibt es nur gedanklich. In Renode erscheinen sie als LEDs: an =
Relais zieht an.

## Der Code

Die Firmware ist auf kleine Dateien verteilt. Jede hat genau eine Aufgabe:

| Datei | Aufgabe |
|---|---|
| `src/main.cpp` | Hauptschleife: Eingänge lesen, Automat weiterschalten, Ausgänge setzen |
| `src/rollladen.h/.cpp` | Der Zustandsautomat: Übergangstabelle, Motor je Zustand. **Keine Hardware.** |
| `src/eingaben.h/.cpp` | Flankenerkennung: aus „Taste ist gedrückt“ wird „Taste wurde gerade gedrückt“ |
| `src/board.h/.cpp` | Alles mit Hardware: GPIO, Relais, LED, UART (libopencm3) |
| `renode/rollladen.repl` | Beschreibt für Renode, wo Taster, Endschalter und Relais angeschlossen sind |
| `renode/rollladen.resc` | Startet die Simulation zum Ausprobieren |
| `tests/rollladen.robot` | Automatischer Abnahmetest mit Robot Framework |
| `cmake/check_rodata.cmake` | Prüft mit `nm`, dass die Übergangstabelle im Flash liegt |

Der Automat entspricht dem aus der Vorlesung und den alten Klausuren:

```text
  Start --> Fährt runter --ES unten--> Unten
               ^    |                   |
   Taste runter|    |Taste hoch         |Taste hoch
               |    v                   v
            Fährt hoch <----------------+
               |
               +--ES oben--> Oben --Taste runter--> Fährt runter

  Endschalter, der nicht zur Lage passt (z. B. ES oben, während der
  Rollladen unten steht) --> Fehler: Motor aus, nur ein Neustart hilft
```

Der **Fehlerzustand** ist eine Plausibilitätsprüfung, wie man sie aus der
Automatisierung kennt. Meldet ein Endschalter etwas, das physikalisch nicht
sein kann, ist vermutlich ein Kabel gebrochen oder ein Schalter verklemmt.
Weiterfahren wäre gefährlich.

## Bauen und testen

```sh
cmake --preset debug
cmake --build --preset debug --target rollladen
ctest --test-dir build/debug --output-on-failure
```

Der CTest `rollladen_tabelle_in_rodata` prüft, dass die Übergangstabelle im
Flash liegt und nicht im RAM.

## Ausprobieren in Renode

Aus dem Hauptverzeichnis des Repositorys:

```sh
renode --disable-xwt --console excercise-001/renode/rollladen.resc
```

Im Renode-Monitor `start` eingeben. Die Meldungen der Firmware erscheinen
über USART2. Taster drücken und loslassen Sie mit:

```text
sysbus.gpioPortC.endschalterUnten Press
sysbus.gpioPortC.tasteHoch Press
sysbus.gpioPortC.tasteHoch Release
sysbus.gpioPortC.endschalterUnten Release
sysbus.gpioPortB.relaisHoch State
```

> **Achtung:** `PressAndRelease` drückt und lässt im selben Augenblick los.
> Die Firmware fragt die Eingänge zyklisch ab (Polling, wie eine SPS) und
> sieht den Tastendruck dann nicht. Nutzen Sie `Press` und `Release`
> getrennt.

## Robot-Framework-Tests (optional, von Hand)

Robot Framework ist noch nicht im Dev-Container installiert. Wer die
Abnahmetests laufen lassen möchte, installiert es einmalig in einer
virtuellen Python-Umgebung:

```sh
python3 -m venv ~/.venv/robot
source ~/.venv/robot/bin/activate
pip install -r /opt/renode/tests/requirements.txt
```

Danach (nach dem Debug-Build, aus dem Hauptverzeichnis):

```sh
source ~/.venv/robot/bin/activate
/opt/renode/renode-test excercise-001/tests/rollladen.robot
```

Ein Testfall liest sich wie eine Prüfanweisung bei der Inbetriebnahme einer
Anlage:

```robot
Faehrt Hoch Und Haelt Oben
    Bis Nach Unten Fahren
    Betaetigen                  ${TASTE_HOCH}  Faehrt hoch
    Motor Sollte Sein           hoch=true  runter=false
    Betaetigen                  ${ES_OBEN}  Oben
    Motor Sollte Sein           hoch=false  runter=false
```

Alternativ laufen die Tests auch über CTest:

```sh
cmake --preset debug -DROLLLADEN_ROBOT_TESTS=ON
cmake --build --preset debug --target rollladen
ctest --test-dir build/debug --output-on-failure
```

## Aufgaben

### Teil 1: Verstehen

1. Bauen Sie die Firmware und starten Sie sie in Renode. Spielen Sie einen
   kompletten Ablauf durch: einschalten, unten ankommen, hochfahren, oben
   ankommen.
2. Zeichnen Sie den Zustandsautomaten aus `uebergangstabelle` in
   `src/rollladen.cpp` als Diagramm. Welche Einträge der Tabelle bedeuten
   „Ereignis wird ignoriert“?
3. Warum fährt der Rollladen nach dem Einschalten zuerst nach unten?
4. Warum führt „Endschalter oben“ im Zustand „Fährt runter“ *nicht* in den
   Fehlerzustand? Denken Sie an das Einschalten.

### Teil 2: Speicher

1. Wo liegt die Übergangstabelle? Prüfen Sie es selbst:
   ```sh
   arm-none-eabi-nm -C build/debug/excercise-001/rollladen | grep uebergang
   ```
2. Entfernen Sie das `const` vor `uebergangstabelle` und bauen Sie neu.
   Was meldet `nm` jetzt? Wie ändert sich die RAM-Belegung, die der Linker am
   Ende ausgibt? Was sagt der CTest? Erklären Sie das Ergebnis.
3. `gemeldet` in `src/eingaben.cpp` ist `static`. In welchem Segment liegt
   es, und warum?

### Teil 3: Erweitern

1. **Stopp-Taste:** Erweitern Sie die Steuerung um eine dritte Taste
   „Stopp“ an PC4. Sie hält den Rollladen in jeder Bewegung an. Ein neuer
   Zustand „Steht“ ist nötig. Ergänzen Sie dafür:
   - `enum Zustand` und `enum Ereignis` in `src/rollladen.h`,
   - die Übergangstabelle und die Tabellen für Motor und Namen,
   - den Eingang in `src/board.cpp` (Pin und Maske),
   - den Taster in `renode/rollladen.repl`.
2. **Test:** Schreiben Sie einen Robot-Testfall „Haelt Bei Stopp An“.
3. **Totzeit beim Richtungswechsel:** Ein echter Motor darf nicht direkt
   von hoch auf runter umgeschaltet werden. Beide Relais sollen erst für
   eine kurze Pause aus sein. Überlegen Sie: Gehört das in den Automaten
   (`rollladen.cpp`) oder in die Hardwareschicht (`board.cpp`)? Begründen
   Sie Ihre Entscheidung.

4. **Funktionszeiger (für Fortgeschrittene):** Statt nur den Folgezustand
   kann jede Zelle der Tabelle zusätzlich einen Zeiger auf eine Funktion
   enthalten, die beim Übergang ausgeführt wird:
   ```cpp
   struct Uebergang {
       Zustand folgezustand;
       void (*aktion)();   // z. B. motor_hoch, motor_aus, fehler_melden
   };
   ```
   Bauen Sie die Tabelle so um. Prüfen Sie danach mit `nm`, wo die Tabelle
   liegt, einmal mit und einmal ohne `const`. Warum ist eine Tabelle mit
   Funktionszeigern im RAM besonders heikel? Denken Sie an einen
   Pufferüberlauf, der ein paar Bytes zu weit schreibt.

> **Tipp:** Die Übergangstabelle muss nach jeder Erweiterung vollständig
> sein: eine Zeile je Zustand, eine Spalte je Ereignis. Fehlt ein Eintrag,
> setzt der Compiler dort 0 ein, also `ZUSTAND_FAEHRT_RUNTER`.
