# YEET DEN SNACK!

Wir arbeiten gemeinsam an einem Roblox-Spiel namens "YEET DEN SNACK!" (Repo: https://github.com/suhaan89/-YEET-DEN-SNACK-.git). Hier der volle Kontext, bevor du irgendwas änderst:

## Konzept

Chaotisch-kompetitives Spiel für Zielgruppe 8–13, bewusst ALBERN statt seriös gehalten (KitKat-Heist-Meme × Steal-a-X-Loop × Ragdoll-Slapstick). Alle 3 Minuten rast ein Schoko-Truck über die Straße und verliert Snacks (8 Raritäten). Spieler schnappen sich Snacks (E, nur 4 Sek. haltbar), yeeten sie mit Klick-halten-und-loslassen in ihre Basis (Sweet-Spot-Ladebalken = Perfekter Yeet), lagern sie im Tresor für Cash/Sekunde ein, können sich gegenseitig per Slap (Q, Ragdoll-Fling) den Snack abnehmen oder in einen Snack verwandeln, fremde Tresore knacken, und per Rebirth ("Sugar Rush") resetten. Details & vollständige Mechanik-Liste stehen in README.md im Repo-Root — die zuerst lesen.

## Stand

Voll funktionsfähiger Prototyp inkl. Juice-Pass (Sounds, Trails, Highlights, Combos, Rush-Hour-Doppeltruck, Tutorial für neue Spieler). Architektur:

```
src/shared/   → ReplicatedStorage.Shared
  (Config.luau = ALLE Balancing-Werte, SnackTypes.luau, Remotes.luau)
src/server/   → ServerScriptService.Server
  (Main.server.lua bootstrapt Services-Tabelle;
  Services/ pro Feature: MapService, DataService, PlayerService, BaseService,
  SnackService, SlapService, TruckService, ShopService, RewardService)
src/client/   → StarterPlayerScripts
  (init.client.luau = Input/Fling/Kamera/Tutorial, Ui.luau, SoundFx.luau)
```

## Wichtige Konventionen (bitte einhalten)

- Balancing-Zahlen NIEMALS im Code verteilen – alles zentral in Config.luau.
- Server validiert ALLES (Kosten, Cooldowns, Reichweiten, Charge-Clamp). Client ist nur Anzeige + Input, nie Autorität.
- Spielerstatus läuft über replizierende Attribute am Player (HoldingSnack, Snackified, Upgrade-Level, Multiplier, VaultPos, …) statt eigener Remote-Zustandslogik.

## Verifikation (IMMER nach Codeänderungen, bevor du sagst "fertig")

```
rojo sourcemap default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap sourcemap.json --definitions C:\Users\rojan\Documents\RobloxProjekte\-YEET-DEN-SNACK-\globalTypes.d.luau src
rojo build -o MeinRobloxProjekt.rbxlx
```

Kein Studio-Zugriff vorausgesetzt – wir schreiben nur Code, Rojo synced/baut, im Studio wird von uns manuell getestet.

## Offene Aufgaben, die WIR (Menschen) noch in Studio erledigen müssen – nicht du:

1. Game Settings → Security → Enable Studio Access to API Services (sonst kein Speichern)
2. Max Players auf 8 (8 Basen)
3. Truck-Hupe: SoundId im TruckService eintragen (kein Built-in-Sound dafür)
4. Platzhalter-Parts durch echte Meshes ersetzen (Truck, Snacks, Tresor)
5. UI-Polish, Game-Icon, Thumbnail

## Wie wir arbeiten wollen

- Bitte auf Deutsch antworten.
- Wir wollen eigenständig/autonom durcharbeiten können statt ständiger Rückfragen – bei kleineren Entscheidungen einfach eine sinnvolle Wahl treffen und weitermachen.
- Am Ende einer Aufgabe kurz auflisten, was WIR noch manuell in Studio machen müssen.
- Spielideen dürfen ruhig albern/slapstick-lastig sein (Ragdoll, Verwandlungen, absurde Namen) – Humor geht hier vor Seriosität.
