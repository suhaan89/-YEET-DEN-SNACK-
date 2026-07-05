# 🍫 YEET DEN SNACK!

Ein chaotisch-kompetitives Roblox-Spiel: Der **Schoko-Truck** verliert Snacks,
alle stürzen sich drauf, und heimgetragen wird nichts – heimge**YEETet** wird!
(Konzept: "KitKat Heist"-Meme × Steal-a-X-Loop × Ragdoll-Slapstick)

## Gameplay-Loop

1. 🚚 Alle 3 Minuten rast der Schoko-Truck über die Straße und verliert Snacks
   (8 Raritäten: Keks-Krümel → El Cacao Supremo). Jeder 4. Truck = **RUSH HOUR**
   mit zwei Trucks aus beiden Richtungen!
2. ✋ Snack aufheben (E) – aber nur **4 Sekunden** haltbar, dann fällt er runter.
3. 🖱️ Klick halten & loslassen = YEET – mit **Live-Flugbahn-Vorschau** (gepunktete
   Kurve, spiegelt exakt die Server-Formel). Goldene Zone am Ladebalken =
   **Perfekter Yeet** (+25 % Wurfkraft). Der gelbe Beam zeigt den Weg zur Basis.
   Gravitation ist leicht floaty (Config.Gravity 140) für weite Comedy-Würfe.
4. 🏦 Landet der Snack in der eigenen Basis-Zone → Tresor → **Cash/Sekunde**.
   Eingelagerte Snacks stehen als **Mini-Modelle sichtbar auf der Basis** (max. 24).
   Landet er in einer fremden Zone → gehört dem anderen (FEHLWURF-Announcement 😂).
   Der Tresor hat **begrenzte Plätze** (20 + 10 pro Rebirth, `Config.VaultLimit`);
   ist er voll, bleibt der Snack liegen. Mit **[R] am eigenen Tresor** wird der
   billigste Snack rausgeworfen, um Platz zu schaffen.
5. 👋 Q = SLAP: Ragdoll-Flug. Snack-Träger lassen fallen und werden 5 Sek.
   **selbst zum Snack verwandelt** (verwandelte fliegen bei Slaps 1,5× weiter –
   "Snack-Kick"). Träger von Legendary+ leuchten für alle sichtbar.
   4 Sek. Spawn-Schutz gegen Spawn-Slapping.
6. 😈 Fremde Tresore knacken (E halten am Tresor) – der Besitzer wird gewarnt
   und kann den Dieb wegslappen.
7. 🔥 Schnell hintereinander einlagern = **Combo-Bonus**.
8. 🎁 Alle 4 Minuten Spielzeit: **Geschenk-Snack** direkt in den Tresor
   (Anti-Frust für Neulinge, RewardService).
9. 🌟 **Sugar Rush** (Rebirth): Cash & Upgrades resetten, +50 % Einkommen für
   immer, mehr Tresor-Plätze, Sterne überm Kopf. Der Tresor springt dabei AUF:
   alle Snacks fliegen als lose Beute aus der Basis (mit kurzer Bank-Immunität,
   damit die eigene Zone sie nicht sofort wieder einsaugt) – Chaos-Moment!
10. 🏠 Basen werden **nicht automatisch zugewiesen**: Neue Spieler suchen sich
   eine FREIE BASIS aus und beanspruchen sie per [E] am Tresor.
11. ⬆️ **Tycoon-Ausbau**: Am grünen Bau-Pad der eigenen Basis kauft man
   Ausbaustufen (Camp → Hütte → Lager → Fabrik → Imperium, `Config.BaseLevels`):
   mehr Tresor-Plätze, Einkommens-Bonus und sichtbare Deko (Zaun, Fahnen,
   Gold-Tresor, Leuchtsäule). Rebirth setzt den Ausbau zurück auf Camp.
12. 🧍 **Skins** im Style-Shop: Ganzkörper-Umfärbung (Schoko, Gummibärchen,
   Gold, Mutanten-Glibber) – rein kosmetisch, überlebt Respawns.
13. 🐞 **Admin-Menü**: im Studio immer sichtbar; live automatisch für den
   Spiel-Besitzer (bzw. Gruppen-Rang ≥254) + UserIds aus `Config.DebugUserIds`.

## Entwicklung

```bash
rojo serve          # Live-Sync nach Studio
rojo build -o MeinRobloxProjekt.rbxlx   # Place bauen

# Statische Analyse (luau-lsp + Roblox-API-Definitionen):
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap sourcemap.json --definitions <globalTypes.d.luau> src
```

## Architektur

```
src/shared/   → ReplicatedStorage.Shared
  Config.luau       Alle Tuning-/Balancing-Werte an einem Ort
  SnackTypes.luau   Snack-Definitionen (Rarität, Drop-Gewicht, Einkommen, Optik)
  Remotes.luau      RemoteEvent/-Function-Verwaltung (Server erstellt, Client findet)

src/server/   → ServerScriptService.Server
  Main.server.lua   Bootstrap, verdrahtet die Services (services-Tabelle)
  Modules/Ragdoll.luau     Fling-Physik (Server + Client-Replikation via "Fling"-Remote)
  Services/MapService      Baut die Platzhalter-Map aus Code
  Services/DataService     DataStore: Laden/Speichern/Autosave (pcall-gesichert)
  Services/PlayerService   Leaderstats, Attribute, WalkSpeed, Cash-API, Rebirth-Sterne
  Services/BaseService     8 Basen (per Prompt beanspruchen), Tresore mit Limit,
                           Fang-Zonen, Einkommen, Knack-/Rauswerf-/Freilass-Mechanik
  Services/SnackService    Spawnen/Greifen/YEETen/Einlagern, Verwandlung, Combos
  Services/SlapService     Slap mit Cooldown, Reichweiten-Check, POW-Effekt
  Services/TruckService    Truck-Event (räumliche Abfragen statt .Touched!), Rush Hour
  Services/ShopService     Upgrades + Rebirth (serverseitig validiert)
  Services/RewardService   Spielzeit-Geschenke (alle 4 Min ein Snack in den Tresor)
  Services/PetService      Pets (passive Einkommens-Begleiter) + GetCollections-Remote
  Services/StyleService    Trails + Ganzkörper-Skins (kosmetisch)
  Services/MergeService    Merge-Maschine (2+ gleiche Snacks -> Chance auf seltener)
  Services/DebugService    Admin-/Test-Menü (Studio, Spiel-Besitzer, Whitelist)

src/client/   → StarterPlayerScripts
  init.client.luau  Input (YEET-Aufladung, Slap), Fling-Handler, Kamera-Shake,
                    Heimweg-Beam, Tutorial für neue Spieler
  Ui.luau           Cash, Shop, Banner, Toasts, Ladebalken mit Sweet-Spot, Hilfe
  SoundFx.luau      Sounds (nur eingebaute rbxasset-Sounds, sofort lauffähig)
```

**Wichtige Konventionen:**
- Balancing NIE im Code verteilen – alles in `Config.luau`.
- Der Server validiert alles (Kosten, Cooldowns, Reichweiten, Charge-Clamp);
  der Client ist nur Anzeige + Input.
- Spieler-Status läuft über replizierende **Attribute** am Player
  (`HoldingSnack`, `Snackified`, Upgrade-Level, `Multiplier`, `VaultPos`, …).

## In Studio noch zu tun

1. **Game Settings → Security → Enable Studio Access to API Services**
   (sonst kein Speichern; Spiel läuft trotzdem mit Warnung).
2. **Max Players auf 8** (es gibt 8 Basen).
3. Truck-**Hupe**: SoundId im `TruckService` (Horn-Sound) eintragen – dafür gibt
   es keinen Built-in-Sound. Optional alle SoundFx-Ids gegen bessere tauschen.
4. Platzhalter-Parts durch **Meshes** ersetzen (Truck, Snacks, Tresor).
5. UI-Polish, Game-Icon, Thumbnail.
