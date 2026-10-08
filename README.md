# Ente Auth dropdown

Ente Auth vera (app desktop) come dropdown in sovraimpressione: icona lucchetto
sulla barra oppure `SUPER + E` per mostrarla/nasconderla ovunque tu sia.

## Come funziona

- Widget barra (`BarWidget.qml`, plugin `meviusisback.ente-auth`): bottone icona,
  click = toggle, stato rilevato ogni 2s. Non tocca segreti: legge solo
  `VISIBLE=0/1` e non logga mai l'output raw.
- `hypr/ente-auth.lua` — regola finestra: la classe `io.ente.auth` va su
  `special:ente-auth`, flottante, centrata sotto la barra (70% larghezza
  x 95% altezza del monitor).
- `ente-auth-dropdown` — script di toggle: se l'app gira nascosta la mostra,
  se visibile la nasconde, se non gira la lancia (`/usr/bin/enteauth`, AUR).
  Usa la sintassi dispatcher Lua di Hyprland 0.56
  (`hl.dsp.workspace.toggle_special`), quella legacy `togglespecialworkspace`
  su questa build fallisce in silenzio.
- Keybind `SUPER + E` in `bindings.lua` → `~/.local/bin/ente-auth-dropdown toggle`.

Nessun segreto toccato: login, sync E2EE e codici restano nell'app di Ente.
Lo script chiede solo al compositor se la finestra esiste.

Chiusura: premi di nuovo `SUPER + E` (oppure `Esc` a lista visibile: è l'app
stessa a chiudere il pannello). Se hai `special_fallthrough` attivo
(lo imposta già il plugin dropdown-terminal, non questo script), basta anche
cliccare fuori.

## Requirements

- Omarchy con Hyprland 0.56+ (sintassi dispatcher Lua)
- App desktop Ente Auth installata (`ente-auth` da AUR, comando `/usr/bin/enteauth`)
- Nerd Font per l'icona lucchetto nella barra

## Installazione

```bash
omarchy plugin add https://github.com/meviusisback/omarchy-ente-auth-dropdown.git
omarchy plugin enable meviusisback.ente-auth
./install.sh
```

`install.sh` è idempotente (blocchi marcati, mai duplicati) e installa solo
regola finestra + keybind:
1. copia `ente-auth-dropdown` in `~/.local/bin/` (modo 755, verificato con `cmp`)
2. copia `hypr/ente-auth.lua` in `~/.config/hypr/`
3. aggiunge l'hook di caricamento in `~/.config/hypr/hyprland.lua`
4. aggiunge il keybind `SUPER + E` in `~/.config/hypr/bindings.lua`
5. `hyprctl reload` + controllo `hyprctl configerrors`

Poi posiziona il widget: `omarchy bar put meviusisback.ente-auth --section right`.

## Removal

```bash
./install.sh uninstall
omarchy plugin disable meviusisback.ente-auth
omarchy plugin remove meviusisback.ente-auth
```

Rimuove script, regola, hook e keybind, poi `hyprctl reload`. Resta solo un
backup `shell.json.bak` se creato (cancellalo a mano se non serve).

## License

MIT — vedi `LICENSE`.
