# ente-auth-dropdown

Ente Auth vera (app desktop) come dropdown in sovraimpressione: icona
sulla barra non serve — `SUPER + E` la mostra/nasconde ovunque tu sia.

## Come funziona

- `hypr/ente-auth.lua` — regola finestra: la classe `io.ente.auth` va su
  `special:ente-auth`, flottante, centrata sotto la barra (520px x 85% monitor).
- `ente-auth-dropdown` — script di toggle: se l'app gira nascosta la mostra,
  se visibile la nasconde, se non gira la lancia (`/usr/bin/enteauth`, AUR).
  Usa la sintassi dispatcher Lua di Hyprland 0.56
  (`hl.dsp.workspace.toggle_special`), quella legacy `togglespecialworkspace`
  su questa build fallisce in silenzio.
- Keybind `SUPER + E` in `bindings.lua` → `~/.local/bin/ente-auth-dropdown toggle`.

Nessun segreto toccato: login, sync E2EE e codici restano nell'app di Ente.
Lo script chiede solo al compositor se la finestra esiste.

Chiusura: premi di nuovo `SUPER + E` (oppure `Esc` a lista visibile: chiude il pannello). Se hai `special_fallthrough` attivo
(lo imposta già il plugin dropdown-terminal), basta anche cliccare fuori.

## Icona nella top bar

Un lucchetto in fondo a destra: click = stesso toggle (`SUPER + E`).
L'icona si accende quando il dropdown è visibile. Aggiunta da `install.sh`
come modulo `command` in `shell.json` (sezione `right`); lo stato viene
rilevato ogni 2s senza segreti né rete.

## Installazione

./install.sh

Fa, in modo idempotente (blocchi marcati, mai duplicati):
1. copia `ente-auth-dropdown` in `~/.local/bin/` (modo 755, verificato con `cmp`)
2. copia `hypr/ente-auth.lua` in `~/.config/hypr/`
3. aggiunge l'hook di caricamento in `~/.config/hypr/hyprland.lua`
4. aggiunge il keybind `SUPER + E` in `~/.config/hypr/bindings.lua`
5. installa il modulo icona (`bar/scripts/ente-auth-status` + voce in `shell.json`)
6. `hyprctl reload` + controllo `hyprctl configerrors`

## Disinstallazione

./install.sh uninstall

Rimuove script, regola, hook e keybind, poi `hyprctl reload`.
