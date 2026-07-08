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
13. 🥚 **Ei-Gacha-Pets** im Pet-Shop: Eier kaufen (Snack-/Gold-/Mutanten-Ei,
   `Config.Eggs`), Server würfelt ein Pet aus 5 Raritäten (`Config.EggPets`,
   ~20 Stück). Bis zu **3 Pets gleichzeitig** ausgerüstet, jedes gibt einen
   Boost (Cash/s, Tresor-%, Wurfkraft, Tempo, Slap-Reichweite/-Cooldown,
   breiterer Sweet-Spot). Duplikate → Trost-Cash. Reveal-Animation beim Öffnen.
14. 🎫 **Season-Pass** (`Config.SeasonPass`): XP durch Einlagern, Perfekte
   Yeets, Merges, Eier & Rebirths. 35 Stufen, Free-Spur für alle + Premium-Spur
   per Robux-Gamepass (bessere Belohnungen, exklusiver Zucker-Phönix auf 35).
   Season-exklusive Trails sind nicht kaufbar, nur erspielbar.
15. 🐞 **Admin-Menü** ([F4]): im Studio immer sichtbar; live automatisch für den
   Spiel-Besitzer (bzw. Gruppen-Rang ≥254) + UserIds aus `Config.DebugUserIds`.
   Tabs Spieler/Events/Diagnose/Server mit Suchfeld, Ziel-Spieler-Auswahl und
   Bestätigungs-Dialog für zerstörerische Aktionen. Diagnose: State-Inspector,
   Trigger-Zonen-Anzeige, Server-Log-/Remote-Panel, Performance-HUD.
16. 🌟 **Goldener Snack**: Alle 2–4 Minuten (unabhängig vom Truck!) spawnt
   irgendwo ein goldener Snack mit Leuchtsäule. Wer ihn ZUERST berührt/[E]
   drückt, kassiert einen Cash-Bonus (×Rebirth-Multiplikator) + Pass-XP.
17. 🏅 **Achievements**: 12 Meilensteine (`Config.Achievements`) – Einlagern,
   Rebirths, Tresor knacken, Legendary-Pet, perfekte Yeets u.v.m. Serverseitig
   getrackt (eigener DataStore), vorbereitet für echte Roblox-Badges
   (BadgeIds eintragen!). Eigenes 🏅-Panel im UI.
18. 👫 **Freunde-Bonus**: Spielt ein Roblox-Freund im selben Server, kriegen
   BEIDE +10 % aufs Tresor-Einkommen (`Config.FriendBonusPercent`), solange
   beide online sind – mit Anzeige im UI.
19. 🤝 **Referral-System**: Jeder hat den festen Code `SNACK-<UserId>` (👥-Menü).
   Neue Spieler (vor Rebirth 1) lösen ihn ein; schafft der Eingeladene
   Rebirth 1, bekommt der EINLADER 10k💰 + Gold-Ei (offline-sicher gespeichert).
20. 🏡 **Basis-Deko**: 8 kaufbare Süßigkeiten-Props (`Config.HousingDecor`,
   Zuckerstange bis Disco-Bonbon) für 6 feste Slots rund um die eigene Basis –
   rein kosmetisch, persistent, wird beim Join automatisch wieder aufgebaut.
21. ✨ **Grafik-Politur** (AtmosphereService): ShadowMap-Lighting, Atmosphere,
   Bloom, SunRays, ColorCorrection, Wolken + Candy-Straßenlaternen,
   Riesen-Zuckerstangen, Plaza-Neonrahmen und Willkommens-Bogen am Spawn.
22. 🌀 **Parkour-Minigame** (`Config.ParkourCourses`): Portal-Hub hinter dem
   Spawn mit 8 Portalen → 8 separate Arenen hoch über der Map (5 kurze,
   3 lange mit Checkpoints). Feste Freischaltungs-Reihenfolge (Parcours n+1
   erst nach Abschluss von n, persistent), steigende Schwierigkeit (Sprünge →
   Lava → rotierende Balken → Blink-Platten → Fahr-Plattformen → Kombis).
   Server-autoritative Zeitmessung (Start-/Ziellinie), zeitbasierte Tier-
   Belohnungen, Cooldown pro Parcours, „Aufgeben“-Button, Session-Bestzeit
   als Leaderboard am Portal. Slap ist in den Arenen deaktiviert.
23. 💎 **Juwelen** (GemService, eigener DataStore): zweite Währung, verdienbar
   NUR im Parkour (leaderstats + HUD neben Cash). Ausgeben: **Juwelen-Ei**
   (`Config.GemEggs`, deutlich bessere Pet-Chancen), **Juwelen-Trails/-Skin**
   (`Config.GemTrails`/`GemSkins`, nicht mit Cash kaufbar) und der exklusive
   **Juwelensturm-Trail** für alle 8 Parcours unter der Meister-Zeit
   (`MasterTime` pro Parcours).

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
  Services/PetService      Ei-Gacha: Eier öffnen, Pet-Boosts (als Attribute),
                           Begleiter-Following + GetCollections-Remote
  Services/SeasonPassService  Season-Pass: XP-Vergabe, Stufen-Belohnungen,
                           Gamepass-Check (MarketplaceService)
  Services/StyleService    Trails + Ganzkörper-Skins (kosmetisch, inkl. Season-Trails)
  Services/MergeService    Merge-Maschine (2+ gleiche Snacks -> Chance auf seltener)
  Services/GoldenSnackService  Goldener Snack (Zufalls-Minievent, Cash für den Ersten)
  Services/AchievementService  Meilensteine + Badge-Vergabe (eigener DataStore)
  Services/FriendService   Freunde-Bonus (+10% Einkommen bei Freund im Server)
  Services/ReferralService Einladungs-Codes + Prämie bei Rebirth 1 (eigener DataStore)
  Services/HousingService  Basis-Deko: kaufen, Slots, persistenter Wiederaufbau
  Services/AtmosphereService  Grafik-Politur (Lighting-Effects + Map-Deko)
  Services/GemService      Juwelen-Währung + Parkour-Fortschritt/Bestzeiten
                           (eigener DataStore, leaderstats "Juwelen")
  Services/ParkourService  Portal-Hub, Teleports, Zeitmessung, Belohnungen,
                           Hindernis-Animationen, Portal-Leaderboards
  Modules/ParkourMap.luau  Baut die 8 Parkour-Arenen (Cursor-Segment-System)
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
6. **Premium-Pass-Gamepass** im Creator Dashboard anlegen und die Id in
   `Config.SeasonPass.GamepassId` eintragen (solange 0: Kauf-Button zeigt
   nur einen Hinweis-Toast).
7. **Achievement-Badges** im Creator Dashboard anlegen (Spiel -> Engagement
   -> Badges, eine pro Eintrag in `Config.Achievements`) und die BadgeIds
   dort eintragen (solange 0: Freischaltung nur intern, keine Roblox-Badge).
8. **Parkour testlaufen**: alle 8 Parcours einmal durchspringen (Debug-Menü:
   „Parkour: alle 8 freischalten“ + „Cooldowns resetten“) und bei zu
   harten/leichten Stellen Zeiten/Belohnungen in `Config.ParkourCourses`
   bzw. Layouts in `Modules/ParkourMap.luau` nachjustieren.
