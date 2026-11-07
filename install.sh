#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────╮
# │  assistente-fedora — pós-instalação do Fedora Workstation    │
# │  Reaplica: pacotes, flatpaks, terminal (kitty + zsh), cursor,│
# │  GNOME, extensões e Firefox.                                 │
# ╰──────────────────────────────────────────────────────────────╯
#
#   ./install.sh                 mostra o que vai mudar e pergunta a cada etapa
#   ./install.sh --dry-run       só mostra o que mudaria, sem alterar nada
#   ./install.sh --yes           aplica tudo sem perguntar (mas mostra o plano)
#   ./install.sh --only kitty,zsh
#   ./install.sh --skip flatpak
#   ./install.sh --list          lista as etapas
#
# Antes de cada etapa o script calcula o que realmente vai mudar NESTA máquina
# (pacotes que faltam, configurações com o valor atual → novo, arquivos que
# serão substituídos) e pergunta. Etapas já aplicadas são puladas.
# Arquivos substituídos ganham backup (*.bak-DATA).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$HOME/.cache/assistente-fedora-$TS.log"
mkdir -p "$HOME/.cache"

STEPS=(check packages flatpak fonts cursor zsh tools kitty gnome extensions firefox vscode auth terminal)
declare -A DESC=(
  [check]="verifica Fedora, GNOME, usuário e sudo"
  [packages]="instala pacotes base e remove apps que não uso"
  [flatpak]="libera o Flathub completo e instala VLC, Extension Manager e VS Code"
  [fonts]="instala a JetBrainsMono Nerd Font"
  [cursor]="instala o cursor Bibata (branco) em todos os apps"
  [zsh]="oh-my-zsh, plugins, tema lambda-vitor e .zshrc; zsh como shell padrão"
  [tools]="ferramentas modernas: eza, dust, delta, btop, tokei, hyperfine; git com delta"
  [kitty]="config do kitty, fundo borrado do wallpaper, cor de destaque"
  [gnome]="tema escuro, atalhos, teclado/mouse, privacidade, dock"
  [extensions]="Tiling Shell, Clipboard Indicator, Blur my Shell, Compiz effect, Astra Monitor + configs"
  [firefox]="página inicial padrão, restaurar abas da sessão anterior, abas embaixo da barra de endereço"
  [vscode]="configurações do VS Code (tema Catppuccin Mocha, salvar automático) e extensões"
  [auth]="desativa login por digital (authselect)"
  [terminal]="kitty como terminal padrão; remove o Ptyxis (só se rodando no kitty)"
)

# Versões fixadas
BIBATA_VERSION="v2.0.7"
CURSOR_THEME="Bibata-Modern-Ice"
EXTENSIONS=(
  tilingshell@ferrarodomenico.com
  clipboard-indicator@tudmotu.com
  compiz-windows-effect@hermes83.github.com
  blur-my-shell@aunetx
  monitor@astraext.github.io      # Astra Monitor (CPU, GPU, memória, sensores na barra)
)
declare -A EXT_NAME=(
  [tilingshell@ferrarodomenico.com]="Tiling Shell"
  [clipboard-indicator@tudmotu.com]="Clipboard Indicator"
  [compiz-windows-effect@hermes83.github.com]="Compiz Windows Effect"
  [blur-my-shell@aunetx]="Blur my Shell"
  [monitor@astraext.github.io]="Astra Monitor"
  [hide-show-apps@vitor.local]="esconder botão 'Mostrar aplicativos'"
  [background-logo@fedorahosted.org]="logo do Fedora no fundo"
)

PKGS_INSTALL=(
  langpacks-pt_BR kitty zsh git curl bat
  liberation-fonts google-carlito-fonts hunspell-pt
  ImageMagick python3-gobject python3-cairo
  libgtop2                        # usado pelo Astra Monitor
)
# Ferramentas modernas de terminal. No .zshrc: ls→eza, du→dust, diff→delta,
# top→btop (com opções clássicas roda o comando original).
# cd/z, grep e find continuam os originais de propósito.
TOOLS_DNF=(eza du-dust git-delta btop tokei hyperfine)
PKGS_REMOVE=(
  gnome-boxes gnome-connections gnome-maps gnome-weather gnome-contacts
  gnome-tour gnome-calendar gnome-clocks mediawriter rygel decibels
  showtime snapshot simple-scan orca yelp malcontent-control
  ibus-anthy ibus-chewing ibus-hangul ibus-libpinyin ibus-libzhuyin
  'libreoffice*'
)
FLATPAKS=(org.videolan.VLC com.mattjakeman.ExtensionManager com.visualstudio.code)
declare -A FLATPAK_NAME=(
  [org.videolan.VLC]="VLC"
  [com.mattjakeman.ExtensionManager]="Extension Manager"
  [com.visualstudio.code]="VS Code"
)
GIT_CONFIG=(
  "core.pager|delta|git mostra diffs com o delta"
  "interactive.diffFilter|delta --color-only|git add -p com cores do delta"
  "delta.navigate|true|delta: navegar entre arquivos com n/N"
  "delta.line-numbers|true|delta: números de linha"
  "merge.conflictStyle|zdiff3|conflitos de merge mais legíveis"
)

# ── configurações do GNOME (tabela: schema[:caminho] | chave | valor | descrição)
# A mesma tabela serve para mostrar o plano (valor atual → novo) e para aplicar.
keyboard_options() {
  python3 - <<'PY'
from gi.repository import Gio
s = Gio.Settings.new("org.gnome.desktop.input-sources")
options = s.get_strv("xkb-options")
if "custom:types" not in options:
    options.append("custom:types")
print(repr(options))
PY
}
gnome_table() {
  local P=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
  local K=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
  cat <<EOF
org.gnome.desktop.interface|color-scheme|'prefer-dark'|tema escuro
org.gnome.desktop.interface|accent-color|'red'|cor de destaque
org.gnome.desktop.interface|enable-hot-corners|false|cantos ativos (canto superior esquerdo)
org.gnome.desktop.background|picture-uri|'file:///usr/share/backgrounds/gnome/blobs-l.svg'|papel de parede (tema claro)
org.gnome.desktop.background|picture-uri-dark|'file:///usr/share/backgrounds/gnome/blobs-d.svg'|papel de parede (tema escuro)
org.gnome.desktop.background|picture-options|'zoom'|ajuste do papel de parede
org.gnome.desktop.screensaver|picture-uri|'file:///usr/share/backgrounds/gnome/blobs-l.svg'|fundo da tela de bloqueio
org.gnome.desktop.wm.preferences|button-layout|'appmenu:minimize,maximize,close'|botões minimizar, maximizar e fechar à direita
org.gnome.desktop.input-sources|sources|[('xkb', 'br')]|layout do teclado (ABNT2)
org.gnome.desktop.input-sources|xkb-options|$(keyboard_options)|Ctrl+Alt como AltGr
org.gnome.desktop.peripherals.keyboard|numlock-state|true|NumLock ligado ao iniciar
org.gnome.desktop.peripherals.mouse|accel-profile|'flat'|aceleração do mouse
org.gnome.desktop.peripherals.mouse|speed|-0.13|velocidade do mouse
org.gnome.desktop.peripherals.touchpad|two-finger-scrolling-enabled|true|rolagem com dois dedos
org.gnome.desktop.peripherals.touchpad|tap-and-drag|false|arrastar com dois toques no touchpad
org.gnome.desktop.privacy|remember-recent-files|false|histórico de arquivos recentes (some "Recentes" do Nautilus)
org.gnome.desktop.privacy|report-technical-problems|false|envio de relatórios de problemas
org.gnome.shell|favorite-apps|@as []|apps fixados na dock (dock vazia)
org.gnome.shell.keybindings|toggle-message-tray|['<Super>m']|atalho das notificações (Super+V fica para a área de transferência)
$K:$P/custom0/|name|'Terminal'|atalho Super+T → nome
$K:$P/custom0/|command|'kitty'|atalho Super+T → comando
$K:$P/custom0/|binding|'<Super>t'|atalho Super+T → tecla
$K:$P/custom1/|name|'Arquivos'|atalho Super+E → nome
$K:$P/custom1/|command|'nautilus --new-window'|atalho Super+E → comando
$K:$P/custom1/|binding|'<Super>e'|atalho Super+E → tecla
org.gnome.settings-daemon.plugins.media-keys|custom-keybindings|['$P/custom0/', '$P/custom1/']|lista de atalhos personalizados
org.gnome.system.location|enabled|true|serviço de localização
EOF
}
cursor_table() {
  cat <<EOF
org.gnome.desktop.interface|cursor-theme|'$CURSOR_THEME'|tema do cursor
org.gnome.desktop.interface|cursor-size|24|tamanho do cursor
EOF
}
auth_table() {
  cat <<'EOF'
org.gnome.login-screen|enable-fingerprint-authentication|false|tela de login: digital
org.gnome.login-screen|enable-smartcard-authentication|false|tela de login: smartcard
org.gnome.login-screen|enable-switchable-authentication|false|tela de login: alternar método
EOF
}
extensions_table() {
  echo "org.gnome.shell|disable-user-extensions|false|extensões do usuário habilitadas"
}
terminal_table() {
  echo "org.gnome.desktop.default-applications.terminal|exec|'kitty'|terminal padrão do GNOME"
}

# ── utilidades ────────────────────────────────────────────────
c_reset=$'\e[0m'; c_bold=$'\e[1m'; c_dim=$'\e[2m'; c_red=$'\e[31m'; c_grn=$'\e[32m'
c_yel=$'\e[33m'; c_cyn=$'\e[36m'; c_acc=$'\e[38;5;208m'
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
info() { say "${c_acc}λ${c_reset} $*"; }
ok()   { say "  ${c_grn}✔${c_reset} $*"; }
warn() { say "  ${c_yel}!${c_reset} $*"; }
err()  { say "  ${c_red}✘${c_reset} $*"; }
short() { local p="${1/#$HOME/\~}"; printf '%s' "$p"; }

ASSUME_YES=0
DRY_RUN=0

# ── plano: o que cada etapa vai mudar ─────────────────────────
PLAN_N=0          # quantas mudanças a etapa vai fazer
DETAILS=()        # "ORIGEM|DESTINO" de arquivos que serão substituídos (para [d]iferenças)
plan_add()  { PLAN_N=$((PLAN_N+1)); say "${c_dim}│${c_reset}  ${c_grn}+${c_reset} $*"; }   # algo novo
plan_chg()  { PLAN_N=$((PLAN_N+1)); say "${c_dim}│${c_reset}  ${c_yel}~${c_reset} $*"; }   # algo alterado
plan_del()  { PLAN_N=$((PLAN_N+1)); say "${c_dim}│${c_reset}  ${c_red}-${c_reset} $*"; }   # algo removido
plan_note() { say "${c_dim}│  · $*${c_reset}"; }                                            # aviso, não conta

# arquivo: novo, igual (nada) ou substituído (com backup)
plan_file() {  # plan_file ORIGEM DESTINO [descrição]
  local src="$1" dst="$2" what="${3:-}"
  [[ -n $what ]] && what=" ${c_dim}($what)${c_reset}"
  if [[ ! -e $dst ]]; then
    plan_add "cria $(short "$dst")$what"
  elif ! cmp -s "$src" "$dst"; then
    plan_chg "substitui $(short "$dst")$what ${c_dim}— backup automático${c_reset}"
    DETAILS+=("$src|$dst")
  fi
}

# gsettings em lote a partir de uma tabela: modo plan (lista diferenças) ou apply
gs_tool() {  # gs_tool plan|apply < tabela
  python3 -c '
import sys, gi
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib
mode = sys.argv[1]
src = Gio.SettingsSchemaSource.get_default()
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line.strip():
        continue
    sch, key, val, label = line.split("|", 3)
    path = None
    if ":" in sch:
        sch, path = sch.split(":", 1)
    schema = src.lookup(sch, True)
    if not schema or not schema.has_key(key):
        print(f"MISSING|{label}")
        continue
    s = Gio.Settings.new_full(schema, None, path)
    cur = s.get_value(key)
    try:
        new = GLib.Variant.parse(cur.get_type(), val, None, None)
    except Exception as e:
        print(f"ERROR|{label}|{e}")
        continue
    if cur.equal(new):
        continue
    if mode == "plan":
        print(f"CHANGE|{label}|{cur.print_(False)}|{new.print_(False)}")
    else:
        s.set_value(key, new)
        print(f"SET|{label}")
Gio.Settings.sync()
' "$1"
}
plan_gs() {  # plan_gs FUNÇÃO_TABELA
  local kind label cur new
  while IFS='|' read -r kind label cur new; do
    case $kind in
      CHANGE)  plan_chg "$label: ${c_dim}$cur${c_reset} → ${c_cyn}$new${c_reset}" ;;
      MISSING) plan_note "ignorado (não existe nesta versão do GNOME): $label" ;;
      ERROR)   plan_note "valor inválido em '$label': $cur" ;;
    esac
  done < <("$1" | gs_tool plan 2>/dev/null)
}
apply_gs() {  # apply_gs FUNÇÃO_TABELA
  local kind label
  while IFS='|' read -r kind label _; do
    [[ $kind == SET ]] && ok "$label"
  done < <("$1" | gs_tool apply)
}

pkg_installed() {  # aceita padrões como 'libreoffice*'
  # aceita padrões ('libreoffice*') e nomes "virtuais" (liberation-fonts → liberation-fonts-all)
  if [[ $1 == *'*'* ]]; then [[ -n $(rpm -qa "$1") ]]
  else rpm -q --quiet "$1" || rpm -q --quiet --whatprovides "$1"; fi
}

backup() {  # faz backup de um arquivo existente antes de sobrescrever
  local f="$1"
  [[ -e $f && ! -L $f ]] && cp -a "$f" "$f.bak-$TS" && warn "backup: $(short "$f.bak-$TS")"
  return 0
}

put() {  # put ORIGEM DESTINO — copia com backup se o conteúdo mudou
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f $dst ]] && cmp -s "$src" "$dst"; then ok "já atualizado: $(short "$dst")"; return 0; fi
  backup "$dst"
  cp "$src" "$dst" && ok "instalado: $(short "$dst")"
}

# Descobre o emulador de terminal que está rodando este script
# (sobe a árvore de processos até achar um terminal conhecido).
parent_terminal() {
  local pid=$$ comm
  while [[ $pid -gt 1 ]]; do
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ') || break
    case "$comm" in
      kitty|ptyxis|ptyxis-agent|gnome-terminal-*|gnome-terminal|konsole|alacritty|wezterm*|foot|xterm|tilix|console|kgx)
        echo "$comm"; return 0 ;;
    esac
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') || break
  done
  echo "desconhecido"
}

firefox_profiles() {
  local d
  for d in "$HOME"/.config/mozilla/firefox/*/ "$HOME"/.mozilla/firefox/*/; do
    [[ -f $d/prefs.js || -f $d/times.json ]] && printf '%s\n' "${d%/}"
  done
  return 0
}

kitty_conf_rendered() {  # kitty.conf do repositório com o $HOME desta máquina
  local out; out=$(mktemp)
  sed "s|__HOME__|$HOME|g" "$REPO/config/kitty/kitty.conf" > "$out"
  echo "$out"
}

ext_settings_current() {  # configurações atuais das extensões (mesmo filtro do repositório)
  dconf dump /org/gnome/shell/extensions/ 2>/dev/null \
    | grep -vE '^(last-version|last-version-name-installed|next-history-clear|settings-version|overridden-settings)='
}

# VS Code: Flatpak (padrão deste setup) ou instalação nativa
vscode_user_dir() {
  if flatpak info com.visualstudio.code &>/dev/null; then echo "$HOME/.var/app/com.visualstudio.code/config/Code/User"
  elif command -v code >/dev/null; then echo "$HOME/.config/Code/User"; fi
}
vscode_ext_dir() {
  if flatpak info com.visualstudio.code &>/dev/null; then echo "$HOME/.var/app/com.visualstudio.code/data/vscode/extensions"
  else echo "$HOME/.vscode/extensions"; fi
}
vscode_cli() {
  if flatpak info com.visualstudio.code &>/dev/null; then flatpak run com.visualstudio.code "$@"; else code "$@"; fi
}
vscode_missing_exts() {  # extensões da lista que ainda não estão instaladas
  local id dir; dir=$(vscode_ext_dir)
  while read -r id; do
    [[ -z $id || $id == \#* ]] && continue
    compgen -G "$dir/${id,,}-*" >/dev/null || echo "$id"
  done < "$REPO/config/vscode/extensions.txt"
}

power_profile() {
  busctl get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
    org.freedesktop.UPower.PowerProfiles ActiveProfile 2>/dev/null | sed -E 's/^s "(.*)"$/\1/'
}

# ── planos (só leem o sistema; nada é alterado aqui) ──────────
plan_packages() {
  local p missing=() present=()
  for p in "${PKGS_REMOVE[@]}"; do pkg_installed "$p" && present+=("$p"); done
  for p in "${PKGS_INSTALL[@]}"; do pkg_installed "$p" || missing+=("$p"); done
  (( ${#present[@]} )) && plan_del "remover ${#present[@]} apps: ${present[*]}"
  (( ${#missing[@]} )) && plan_add "instalar: ${missing[*]}"
  return 0
}

plan_flatpak() {
  command -v flatpak >/dev/null || { plan_note "flatpak não está instalado"; return 0; }
  if ! grep -qx flathub <<<"$(flatpak remotes --columns=name)"; then
    plan_add "adicionar o repositório Flathub"
  elif grep -q '/' <<<"$(flatpak remotes --columns=name,filter | awk '$1=="flathub"')"; then
    plan_chg "Flathub: liberar o catálogo completo (hoje está filtrado pelo Fedora)"
  fi
  local a missing=()
  for a in "${FLATPAKS[@]}"; do flatpak info "$a" &>/dev/null || missing+=("${FLATPAK_NAME[$a]:-$a}"); done
  (( ${#missing[@]} )) && plan_add "instalar: ${missing[*]}"
  local n
  n=$(python3 - "$REPO/config/vlc-mimeapps.list" "$HOME/.config/mimeapps.list" <<'EOF'
import sys, os
want = dict(l.strip().split("=", 1) for l in open(sys.argv[1]) if "=" in l)
cur, sec = {}, None
if os.path.exists(sys.argv[2]):
    for l in open(sys.argv[2]):
        l = l.strip()
        if l.startswith("["): sec = l
        elif sec == "[Default Applications]" and "=" in l:
            k, v = l.split("=", 1); cur[k] = v
print(sum(1 for k, v in want.items() if cur.get(k) != v))
EOF
)
  (( n > 0 )) && plan_chg "VLC como player padrão em $n formatos de áudio/vídeo ${c_dim}(~/.config/mimeapps.list)${c_reset}"
  return 0
}

plan_fonts() {
  grep -qi 'JetBrainsMono Nerd Font' <<<"$(fc-list : family)" || plan_add "baixar e instalar a JetBrainsMono Nerd Font em ~/.local/share/fonts"
  return 0
}

plan_cursor() {
  local t
  for t in Bibata-Modern-Ice Bibata-Modern-Classic; do
    [[ -d $HOME/.icons/$t ]] || plan_add "baixar o cursor $t ($BIBATA_VERSION) em ~/.icons"
    [[ -d $HOME/.icons/$t/cursors_scalable ]] || plan_add "gerar a versão SVG do $t (exigida pelo GNOME 51)"
  done
  grep -qs "Inherits=$CURSOR_THEME" "$HOME/.icons/default/index.theme" || plan_chg "cursor padrão dos apps XWayland → $CURSOR_THEME ${c_dim}(~/.icons/default)${c_reset}"
  grep -qs "gtk-cursor-theme-name=$CURSOR_THEME" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" \
    && [[ $(grep -ls "gtk-cursor-theme-name=$CURSOR_THEME" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" | wc -l) -eq 2 ]] \
    || plan_chg "cursor nos apps GTK 3 e 4 → $CURSOR_THEME ${c_dim}(settings.ini)${c_reset}"
  grep -qs "XCURSOR_THEME=$CURSOR_THEME" "$HOME/.config/environment.d/cursor.conf" || plan_chg "variáveis da sessão XCURSOR_THEME/XCURSOR_SIZE ${c_dim}(~/.config/environment.d)${c_reset}"
  if command -v flatpak >/dev/null && ! grep -q "XCURSOR_THEME=$CURSOR_THEME" <<<"$(flatpak override --user --show 2>/dev/null)"; then
    plan_chg "cursor nos apps Flatpak ${c_dim}(flatpak override --user)${c_reset}"
  fi
  plan_gs cursor_table
}

plan_zsh() {
  [[ -d $HOME/.oh-my-zsh ]] || plan_add "instalar o oh-my-zsh em ~/.oh-my-zsh"
  local n
  for n in zsh-autosuggestions zsh-syntax-highlighting; do
    [[ -d $HOME/.oh-my-zsh/custom/plugins/$n ]] || plan_add "plugin $n"
  done
  plan_file "$REPO/config/zsh/lambda-vitor.zsh-theme" "$HOME/.oh-my-zsh/custom/themes/lambda-vitor.zsh-theme" "tema do prompt"
  plan_file "$REPO/config/zsh/zshrc" "$HOME/.zshrc" "aliases, plugins, cd inteligente"
  local sh; sh=$(getent passwd "$USER" | cut -d: -f7)
  [[ $sh == */zsh ]] || plan_chg "shell padrão: ${c_dim}$sh${c_reset} → ${c_cyn}zsh${c_reset} ${c_dim}(vale no próximo login)${c_reset}"
  return 0
}

plan_tools() {
  local p missing=() e key val desc cur
  for p in "${TOOLS_DNF[@]}"; do pkg_installed "$p" || missing+=("$p"); done
  (( ${#missing[@]} )) && plan_add "instalar: ${missing[*]}"
  for e in "${GIT_CONFIG[@]}"; do
    IFS='|' read -r key val desc <<<"$e"
    cur=$(git config --global --get "$key" 2>/dev/null || true)
    [[ $cur == "$val" ]] || plan_chg "git $key: ${c_dim}${cur:-(vazio)}${c_reset} → ${c_cyn}$val${c_reset} ${c_dim}($desc)${c_reset}"
  done
  return 0
}

plan_kitty() {
  local conf; conf=$(kitty_conf_rendered)
  plan_file "$conf" "$HOME/.config/kitty/kitty.conf" "fonte, cores, fundo, abas"
  plan_file "$REPO/bin/accent-sync" "$HOME/.local/bin/accent-sync" "cor de destaque do GNOME → kitty"
  plan_file "$REPO/bin/kitty-wallpaper" "$HOME/.local/bin/kitty-wallpaper" "wallpaper → fundo borrado"
  plan_file "$REPO/systemd/accent-sync.service" "$HOME/.config/systemd/user/accent-sync.service" "serviço"
  systemctl --user is-enabled accent-sync.service &>/dev/null || plan_add "ativar o serviço accent-sync (kitty acompanha a cor de destaque)"
  systemctl --user is-active accent-sync.service &>/dev/null || plan_add "iniciar o serviço accent-sync (wallpaper e cor de destaque)"
  [[ -f $HOME/.config/kitty/wallpaper-blur.png ]] || plan_add "gerar o fundo do terminal a partir do papel de parede atual"
  return 0
}

plan_gnome() {
  plan_file "$REPO/config/xkb/types/custom" "${XDG_CONFIG_HOME:-$HOME/.config}/xkb/types/custom" "Ctrl+Alt como AltGr (XKB)"
  plan_gs gnome_table
  local d
  [[ -d $HOME/repos ]] || plan_add "criar a pasta ~/repos"
  for d in repos Documents Downloads; do
    grep -qs "^file://$HOME/$d " "$HOME/.config/gtk-3.0/bookmarks" || plan_add "atalho no Nautilus: $d"
  done
  local pp; pp=$(power_profile)
  if [[ -n $pp && $pp != performance ]]; then
    plan_chg "perfil de energia: ${c_dim}$pp${c_reset} → ${c_cyn}performance${c_reset}"
  fi
  return 0
}

plan_extensions() {
  command -v gnome-extensions >/dev/null || { plan_note "gnome-extensions não encontrado"; return 0; }
  local uuid enabled
  for uuid in "${EXTENSIONS[@]}"; do
    [[ -s $HOME/.local/share/gnome-shell/extensions/$uuid/metadata.json && -s $HOME/.local/share/gnome-shell/extensions/$uuid/extension.js ]] || plan_add "baixar a extensão ${EXT_NAME[$uuid]} (extensions.gnome.org)"
    local status
    status=$(LC_ALL=C gnome-extensions info "$uuid" 2>/dev/null) || status=""
    if [[ -z $status && -s $HOME/.local/share/gnome-shell/extensions/$uuid/metadata.json ]]; then
      plan_chg "${EXT_NAME[$uuid]}: instalada em disco, mas ainda não reconhecida pelo GNOME; verificar ativação"
    fi
    if [[ $status == *"State: ERROR"* || $status == *"State: OUT OF DATE"* ]]; then
      plan_chg "verificar ${EXT_NAME[$uuid]}: erro ou incompatibilidade no GNOME"
    fi
  done
  plan_file "$REPO/config/extensions/hide-show-apps@vitor.local/extension.js" \
    "$HOME/.local/share/gnome-shell/extensions/hide-show-apps@vitor.local/extension.js" "${EXT_NAME[hide-show-apps@vitor.local]}"
  enabled=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null)
  for uuid in "${EXTENSIONS[@]}" hide-show-apps@vitor.local background-logo@fedorahosted.org; do
    [[ $enabled == *"'$uuid'"* ]] || plan_add "ativar ${EXT_NAME[$uuid]}"
  done
  local cur; cur=$(mktemp)
  ext_settings_current > "$cur"
  if ! cmp -s "$cur" "$REPO/config/extensions/settings.dconf"; then
    plan_chg "configurações das extensões ${c_dim}(Blur my Shell, Astra Monitor, Clipboard Super+V, layouts do Tiling Shell)${c_reset}"
    DETAILS+=("$REPO/config/extensions/settings.dconf|$cur")
  fi
  plan_gs extensions_table
}

plan_firefox() {
  local d profiles
  profiles=$(firefox_profiles)
  if [[ -z $profiles ]]; then
    command -v firefox >/dev/null && plan_add "criar o perfil do Firefox (abre em segundo plano por alguns segundos) e configurar"
    return 0
  fi
  while read -r d; do
    plan_file "$REPO/config/firefox/user.js" "$d/user.js" "página inicial, restaurar sessão"
    plan_file "$REPO/config/firefox/userChrome.css" "$d/chrome/userChrome.css" "abas embaixo da barra de endereço"
  done <<<"$profiles"
  (( PLAN_N )) && pgrep -x firefox >/dev/null && plan_note "o Firefox está aberto: as mudanças valem depois de reiniciá-lo (Ctrl+Q)"
  return 0
}

plan_vscode() {
  local dir; dir=$(vscode_user_dir)
  [[ -n $dir ]] || { plan_note "VS Code não está instalado (rode a etapa flatpak)"; return 0; }
  plan_file "$REPO/config/vscode/settings.json" "$dir/settings.json" "tema, salvar automático"
  local id
  while read -r id; do [[ -n $id ]] && plan_add "instalar a extensão $id"; done < <(vscode_missing_exts)
  return 0
}

plan_auth() {
  grep -q with-fingerprint <<<"$(authselect current 2>/dev/null)" && plan_chg "login por digital: ${c_dim}ligado${c_reset} → ${c_cyn}desligado${c_reset} ${c_dim}(authselect, usa sudo)${c_reset}"
  plan_gs auth_table
}

plan_terminal() {
  local f
  for f in xdg-terminals.list gnome-xdg-terminals.list; do
    [[ $(cat "$HOME/.config/$f" 2>/dev/null) == kitty.desktop ]] || plan_chg "kitty como terminal padrão ${c_dim}(~/.config/$f)${c_reset}"
  done
  plan_gs terminal_table
  if rpm -q --quiet ptyxis; then
    local term; term=$(parent_terminal)
    if [[ $term == kitty ]]; then
      plan_del "remover o Ptyxis (terminal padrão do Fedora)"
    else
      plan_note "o Ptyxis NÃO será removido: este script está rodando no '$term'."
      plan_note "depois, abra o kitty (Super+T) e rode: $(short "$REPO")/install.sh --only terminal"
    fi
  fi
  return 0
}

# ── etapas (aplicam as mudanças) ──────────────────────────────
step_check() {
  [[ $EUID -ne 0 ]] || { err "não rode como root; rode como seu usuário (o script usa sudo quando precisa)"; return 1; }
  grep -q '^ID=fedora' /etc/os-release || { err "isto não parece ser Fedora"; return 1; }
  local ver; ver=$(. /etc/os-release; echo "$VERSION_ID")
  ok "Fedora $ver"
  [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* ]] || warn "GNOME não detectado (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-vazio})"
  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || warn "sem sessão gráfica/D-Bus: etapas do GNOME podem falhar"
  ok "rodando no terminal: $(parent_terminal)"
  if (( DRY_RUN )); then ok "modo --dry-run: nada será alterado"; return 0; fi
  sudo -v || { err "sudo necessário"; return 1; }
  ok "sudo ok"
}

step_packages() {
  local present=() p
  for p in "${PKGS_REMOVE[@]}"; do pkg_installed "$p" && present+=("$p"); done
  if (( ${#present[@]} )); then
    sudo dnf remove -y "${present[@]}" 2>&1 | tee -a "$LOG" | tail -3
  fi
  sudo dnf install -y "${PKGS_INSTALL[@]}" 2>&1 | tee -a "$LOG" | tail -3
}

step_flatpak() {
  command -v flatpak >/dev/null || { err "flatpak não instalado"; return 1; }
  local remotes
  remotes=$(flatpak remotes --system --columns=name) || return $?
  # remote-add pode buscar o .flatpakrepo mesmo com --if-not-exists.
  if ! grep -qx flathub <<<"$remotes"; then
    sudo flatpak remote-add --system --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || return $?
  fi
  sudo flatpak remote-modify --system --enable --no-filter flathub || return $?
  ok "Flathub completo liberado"
  # Não truncar: avisos após o erro podem esconder a causa da falha.
  local rc
  if sudo flatpak install --system -y --noninteractive flathub "${FLATPAKS[@]}" 2>&1 | tee -a "$LOG"; then
    :
  else
    rc=$?
    err "instalação Flatpak falhou; saída completa em $(short "$LOG")"
    warn "se houve falha de rede/DNS, restabeleça a conexão e rode: ./install.sh --only flatpak"
    return "$rc"
  fi
  # VLC como player padrão de áudio e vídeo (mescla com o mimeapps.list existente)
  python3 - "$REPO/config/vlc-mimeapps.list" "$HOME/.config/mimeapps.list" <<'EOF'
import sys, os
new = dict(l.strip().split("=", 1) for l in open(sys.argv[1]) if "=" in l)
path = sys.argv[2]
lines = open(path).read().splitlines() if os.path.exists(path) else []
out, in_def, seen_def = [], False, False
for l in lines:
    if l.startswith("["):
        if in_def:  # fim da seção: acrescenta o que faltou
            out += [f"{k}={v}" for k, v in new.items()]; new = {}
        in_def = l.strip() == "[Default Applications]"; seen_def |= in_def
    elif in_def and "=" in l and l.split("=", 1)[0] in new:
        k = l.split("=", 1)[0]; out.append(f"{k}={new.pop(k)}"); continue
    out.append(l)
if in_def:
    out += [f"{k}={v}" for k, v in new.items()]; new = {}
if not seen_def:
    out += ["", "[Default Applications]"] + [f"{k}={v}" for k, v in new.items()]
os.makedirs(os.path.dirname(path), exist_ok=True)
open(path, "w").write("\n".join(out) + "\n")
EOF
  ok "VLC definido como player padrão"
}

step_fonts() {
  local dir="$HOME/.local/share/fonts/JetBrainsMonoNF"
  if grep -qi 'JetBrainsMono Nerd Font' <<<"$(fc-list : family)"; then ok "JetBrainsMono Nerd Font já instalada"; return 0; fi
  mkdir -p "$dir"
  curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz | tar -xJ -C "$dir"
  fc-cache -f >/dev/null
  ok "JetBrainsMono Nerd Font instalada"
}

step_cursor() {
  local t tmp
  mkdir -p "$HOME/.icons" "$HOME/.local/share/icons"
  for t in Bibata-Modern-Ice Bibata-Modern-Classic; do
    if [[ ! -d $HOME/.icons/$t ]]; then
      tmp=$(mktemp -d)
      curl -fsSL "https://github.com/ful1e5/Bibata_Cursor/releases/download/$BIBATA_VERSION/$t.tar.xz" | tar -xJ -C "$tmp"
      mv "$tmp/$t" "$HOME/.icons/$t"; rm -rf "$tmp"
      ok "baixado $t"
    fi
    [[ -e $HOME/.local/share/icons/$t ]] || ln -s "$HOME/.icons/$t" "$HOME/.local/share/icons/$t"
    # O GNOME 51 só desenha cursores no formato SVG (cursors_scalable/); o Bibata
    # só traz Xcursor. Sem isso o cursor só aparece em apps X11 como o kitty.
    if [[ ! -d $HOME/.icons/$t/cursors_scalable ]]; then
      python3 "$REPO/bin/cursor-scalable" "$HOME/.icons/$t"
    fi
  done
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$REPO/bin/cursor-scalable" "$HOME/.local/bin/cursor-scalable"
  # tema "default" usado por apps XWayland
  mkdir -p "$HOME/.icons/default"
  printf '[Icon Theme]\nName=Default\nInherits=%s\n' "$CURSOR_THEME" > "$HOME/.icons/default/index.theme"
  # GTK 3 e 4
  local v f
  for v in 3.0 4.0; do
    f="$HOME/.config/gtk-$v/settings.ini"; mkdir -p "$(dirname "$f")"
    [[ -f $f ]] || printf '[Settings]\n' > "$f"
    sed -i '/^gtk-cursor-theme-name=/d; /^gtk-cursor-theme-size=/d' "$f"
    printf 'gtk-cursor-theme-name=%s\ngtk-cursor-theme-size=24\n' "$CURSOR_THEME" >> "$f"
  done
  # variáveis da sessão (valem no próximo login)
  mkdir -p "$HOME/.config/environment.d"
  printf 'XCURSOR_THEME=%s\nXCURSOR_SIZE=24\n' "$CURSOR_THEME" > "$HOME/.config/environment.d/cursor.conf"
  # Flatpak
  if command -v flatpak >/dev/null; then
    flatpak override --user --filesystem=~/.icons:ro --filesystem=xdg-data/icons:ro \
      --env=XCURSOR_THEME="$CURSOR_THEME" --env=XCURSOR_SIZE=24 \
      --env=XCURSOR_PATH="/run/host/user-share/icons:/run/host/share/icons:$HOME/.icons"
  fi
  apply_gs cursor_table
  ok "cursor $CURSOR_THEME configurado (relogue para valer em tudo)"
}

step_zsh() {
  command -v zsh >/dev/null || { err "zsh não instalado (rode a etapa packages)"; return 1; }
  if [[ ! -d $HOME/.oh-my-zsh ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "oh-my-zsh instalado"
  fi
  local C="$HOME/.oh-my-zsh/custom" r n
  for r in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do
    n=${r#*/}
    [[ -d $C/plugins/$n ]] || { git clone -q --depth=1 "https://github.com/$r" "$C/plugins/$n" && ok "plugin $n"; }
  done
  put "$REPO/config/zsh/lambda-vitor.zsh-theme" "$C/themes/lambda-vitor.zsh-theme"
  put "$REPO/config/zsh/zshrc" "$HOME/.zshrc"
  if [[ $(getent passwd "$USER" | cut -d: -f7) != */zsh ]]; then
    sudo usermod -s "$(command -v zsh)" "$USER" && ok "zsh agora é o shell padrão (vale no próximo login)"
  fi
}

step_tools() {
  local p missing=() e key val desc
  for p in "${TOOLS_DNF[@]}"; do pkg_installed "$p" || missing+=("$p"); done
  (( ${#missing[@]} )) && { sudo dnf install -y "${missing[@]}" 2>&1 | tee -a "$LOG" | tail -3; }
  if command -v delta >/dev/null; then   # só configura o git se o delta existir
    for e in "${GIT_CONFIG[@]}"; do
      IFS='|' read -r key val desc <<<"$e"
      git config --global "$key" "$val"
    done
    ok "git configurado com o delta"
  else
    warn "delta não encontrado: git mantido sem alterações"
  fi
}

step_kitty() {
  command -v kitty >/dev/null || { err "kitty não instalado (rode a etapa packages)"; return 1; }
  local conf; conf=$(kitty_conf_rendered)
  put "$conf" "$HOME/.config/kitty/kitty.conf"; rm -f "$conf"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$REPO/bin/accent-sync"     "$HOME/.local/bin/accent-sync"
  install -m 755 "$REPO/bin/kitty-wallpaper" "$HOME/.local/bin/kitty-wallpaper"
  ok "instalados: ~/.local/bin/accent-sync, ~/.local/bin/kitty-wallpaper"
  "$HOME/.local/bin/accent-sync" && ok "cor de destaque aplicada"
  mkdir -p "$HOME/.config/systemd/user"
  put "$REPO/systemd/accent-sync.service" "$HOME/.config/systemd/user/accent-sync.service"
  if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable accent-sync.service 2>/dev/null && systemctl --user restart accent-sync.service 2>/dev/null && ok "serviço accent-sync ativo" \
      || warn "não consegui ativar o accent-sync agora; rode: systemctl --user enable --now accent-sync"
  fi
  "$HOME/.local/bin/kitty-wallpaper" || warn "não consegui gerar o fundo; rode depois: kitty-wallpaper"
}

step_gnome() {
  put "$REPO/config/xkb/types/custom" "${XDG_CONFIG_HOME:-$HOME/.config}/xkb/types/custom"
  apply_gs gnome_table
  mkdir -p "$HOME/repos"
  local bm="$HOME/.config/gtk-3.0/bookmarks" d
  mkdir -p "$(dirname "$bm")"; touch "$bm"
  for d in repos Documents Downloads; do
    grep -q "^file://$HOME/$d " "$bm" || { echo "file://$HOME/$d $d" >> "$bm"; ok "atalho no Nautilus: $d"; }
  done
  if [[ $(power_profile) != performance ]]; then
    if busctl set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
         org.freedesktop.UPower.PowerProfiles ActiveProfile s performance 2>/dev/null; then
      ok "perfil de energia: desempenho"
    else
      warn "não consegui ativar o perfil Desempenho (máquina sem suporte?)"
    fi
  fi
}

step_extensions() {
  command -v gnome-extensions >/dev/null || { err "gnome-extensions não encontrado"; return 1; }
  local shell_ver uuid info url tmp failures=0 pending=0
  shell_ver=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
  for uuid in "${EXTENSIONS[@]}"; do
    [[ -s $HOME/.local/share/gnome-shell/extensions/$uuid/metadata.json && -s $HOME/.local/share/gnome-shell/extensions/$uuid/extension.js ]] && continue
    info=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$shell_ver") \
      || { err "${EXT_NAME[$uuid]}: falha ao consultar versão para GNOME $shell_ver"; failures=$((failures+1)); continue; }
    url=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["download_url"])' "$info") \
      || { err "${EXT_NAME[$uuid]}: resposta inválida"; failures=$((failures+1)); continue; }
    tmp=$(mktemp --suffix=.zip)
    curl -fsSL "https://extensions.gnome.org$url" -o "$tmp" && gnome-extensions install --force "$tmp" \
      && ok "${EXT_NAME[$uuid]} instalada" || { err "${EXT_NAME[$uuid]}: falha ao instalar"; failures=$((failures+1)); }
    rm -f "$tmp"
  done
  # extensão local que esconde o botão "Mostrar aplicativos"
  local dst="$HOME/.local/share/gnome-shell/extensions/hide-show-apps@vitor.local"
  mkdir -p "$dst"
  cp "$REPO/config/extensions/hide-show-apps@vitor.local/"* "$dst/"
  # ativa todas (o GNOME carrega extensões novas no próximo login)
  python3 - "${EXTENSIONS[@]}" hide-show-apps@vitor.local background-logo@fedorahosted.org <<'EOF'
import subprocess, sys, ast
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True).stdout.strip()
cur = [] if cur.startswith("@as") else ast.literal_eval(cur)
for u in sys.argv[1:]:
    if u not in cur:
        cur.append(u)
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(cur)], check=True)
EOF
  apply_gs extensions_table
  for uuid in "${EXTENSIONS[@]}" hide-show-apps@vitor.local; do
    local activation
    if activation=$(gnome-extensions enable "$uuid" 2>&1); then
      local status
      status=$(LC_ALL=C gnome-extensions info "$uuid" 2>/dev/null) || status=""
      if [[ $status == *"State: ERROR"* || $status == *"State: OUT OF DATE"* ]]; then
        err "${EXT_NAME[$uuid]}: erro ao carregar; veja: gnome-extensions info '$uuid'"
        failures=$((failures+1))
      elif [[ $status == *"State: ACTIVE"* || $status == *"State: ENABLED"* ]]; then
        ok "${EXT_NAME[$uuid]}: ativa no GNOME"
      else
        warn "${EXT_NAME[$uuid]}: ativação solicitada, mas execução ainda não confirmada"
        [[ -z $status ]] || say "$status"
        pending=$((pending+1))
      fi
    else
      warn "${EXT_NAME[$uuid]}: arquivos instalados e ativação salva, mas o GNOME não confirmou o carregamento"
      [[ -z $activation ]] || say "$activation"
      pending=$((pending+1))
    fi
  done
  dconf load /org/gnome/shell/extensions/ < "$REPO/config/extensions/settings.dconf" || return $?
  ok "configurações das extensões aplicadas"
  (( failures == 0 )) || return 1
  if (( pending )); then
    warn "saia da sessão GNOME e entre novamente (fechar o terminal não basta)"
    warn "se continuar sem aparecer: gnome-extensions list; journalctl --user -b _COMM=gnome-shell --no-pager -n 80"
    return 3
  fi
  return 0
}

step_firefox() {
  local profiles d
  profiles=$(firefox_profiles)
  if [[ -z $profiles ]] && command -v firefox >/dev/null; then
    if pgrep -x firefox >/dev/null; then
      warn "Firefox aberto e sem perfil detectado; feche-o e rode: ./install.sh --only firefox"
      return 0
    fi
    info "criando perfil do Firefox (abre em segundo plano por alguns segundos)"
    timeout 12 firefox --headless about:blank >/dev/null 2>&1 || true
    profiles=$(firefox_profiles)
  fi
  [[ -n $profiles ]] || { warn "nenhum perfil do Firefox encontrado; abra o Firefox uma vez e rode: ./install.sh --only firefox"; return 0; }
  while read -r d; do
    put "$REPO/config/firefox/user.js"        "$d/user.js"
    put "$REPO/config/firefox/userChrome.css" "$d/chrome/userChrome.css"
  done <<<"$profiles"
  pgrep -x firefox >/dev/null && warn "reinicie o Firefox (Ctrl+Q) para aplicar"
  return 0
}

step_vscode() {
  local dir; dir=$(vscode_user_dir)
  [[ -n $dir ]] || { err "VS Code não está instalado (rode a etapa flatpak)"; return 1; }
  put "$REPO/config/vscode/settings.json" "$dir/settings.json"
  local id
  while read -r id; do
    [[ -n $id ]] || continue
    vscode_cli --install-extension "$id" >/dev/null 2>&1 && ok "extensão $id" || err "falha ao instalar a extensão $id"
  done < <(vscode_missing_exts)
}

step_auth() {
  if grep -q with-fingerprint <<<"$(authselect current 2>/dev/null)"; then
    sudo authselect disable-feature with-fingerprint && sudo authselect apply-changes && ok "login por digital desativado"
  fi
  apply_gs auth_table
}

step_terminal() {
  mkdir -p "$HOME/.config"
  echo "kitty.desktop" > "$HOME/.config/xdg-terminals.list"
  echo "kitty.desktop" > "$HOME/.config/gnome-xdg-terminals.list"
  apply_gs terminal_table
  ok "kitty definido como terminal padrão"
  # Remover o Ptyxis SÓ se este script estiver rodando dentro do kitty.
  # Se estiver rodando no Ptyxis (ou outro terminal), removê-lo derrubaria o
  # terminal no meio da instalação — então pulamos (o plano já avisou).
  rpm -q --quiet ptyxis || return 0
  [[ $(parent_terminal) == kitty ]] || return 0
  sudo dnf remove -y ptyxis 2>&1 | tee -a "$LOG" | tail -3
}

# ── execução ──────────────────────────────────────────────────
usage() { sed -n '8,19p' "$0" | sed 's/^# \{0,1\}//'; }

show_details() {
  local pair src dst
  if (( ${#DETAILS[@]} == 0 )); then
    say "${c_dim}│  (nenhum arquivo será substituído nesta etapa — só itens novos ou configurações)${c_reset}"
    return
  fi
  for pair in "${DETAILS[@]}"; do
    src=${pair%%|*}; dst=${pair#*|}
    say "${c_dim}│${c_reset}"
    say "${c_dim}│${c_reset}  ${c_bold}$(short "$dst")${c_reset}  ${c_dim}(${c_red}- atual${c_reset}${c_dim} / ${c_grn}+ novo${c_reset}${c_dim})${c_reset}"
    diff -u "$dst" "$src" | tail -n +3 | head -60 | while IFS= read -r l; do
      case $l in
        +*) printf '%s  %s%s%s\n' "${c_dim}│${c_reset}" "$c_grn" "$l" "$c_reset" ;;
        -*) printf '%s  %s%s%s\n' "${c_dim}│${c_reset}" "$c_red" "$l" "$c_reset" ;;
        @@*) printf '%s  %s%s%s\n' "${c_dim}│${c_reset}" "$c_cyn" "$l" "$c_reset" ;;
        *)  printf '%s  %s\n' "${c_dim}│${c_reset}" "$l" ;;
      esac
    done
    (( $(diff -u "$dst" "$src" | wc -l) > 62 )) && say "${c_dim}│  … (diferença cortada; arquivo completo em $(short "$src"))${c_reset}"
  done
}

# Mostra o plano da etapa e pergunta. Retorno: 0 aplicar, 1 pular, 2 sair.
confirm_step() {
  local s="$1" r
  PLAN_N=0; DETAILS=()
  say "${c_dim}╭─${c_reset} ${c_bold}${c_acc}$s${c_reset} ${c_dim}— ${DESC[$s]}${c_reset}"
  "plan_$s"
  if (( PLAN_N == 0 )); then
    say "${c_dim}╰─${c_reset} ${c_grn}✔ já está tudo aplicado nesta máquina${c_reset}"
    return 1
  fi
  if (( DRY_RUN )); then
    say "${c_dim}╰─ $PLAN_N mudança(s) — não aplicadas (--dry-run)${c_reset}"
    return 1
  fi
  if (( ASSUME_YES )); then
    say "${c_dim}╰─${c_reset} aplicando $PLAN_N mudança(s) (--yes)"
    return 0
  fi
  while true; do
    read -r -p "${c_dim}╰─${c_reset} Aplicar $PLAN_N mudança(s)? [${c_bold}S${c_reset}]im  [n]ão  [d]iferenças  [q]sair: " r </dev/tty
    case ${r,,} in
      ""|s|sim|y|yes) return 0 ;;
      n|nao|não|no)   say "  ${c_yel}↷${c_reset} etapa pulada"; return 1 ;;
      d)              show_details ;;
      q|sair)         return 2 ;;
    esac
  done
}

ONLY=""; SKIP=""
while (( $# )); do
  case "$1" in
    -y|--yes)     ASSUME_YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --only)       ONLY="$2"; shift ;;
    --only=*)     ONLY="${1#*=}" ;;
    --skip)       SKIP="$2"; shift ;;
    --skip=*)     SKIP="${1#*=}" ;;
    --list)       for s in "${STEPS[@]}"; do printf '  %-11s %s\n' "$s" "${DESC[$s]}"; done; exit 0 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "opção desconhecida: $1"; usage; exit 1 ;;
  esac
  shift
done

selected=()
for s in "${STEPS[@]}"; do
  [[ -n $ONLY && ",$ONLY," != *",$s,"* && $s != check ]] && continue
  [[ -n $SKIP && ",$SKIP," == *",$s,"* ]] && continue
  selected+=("$s")
done

say "${c_bold}${c_acc}λ assistente-fedora${c_reset}  ${c_dim}log: $(short "$LOG")${c_reset}"
say "${c_dim}legenda:  ${c_grn}+${c_reset}${c_dim} novo   ${c_yel}~${c_reset}${c_dim} alterado (atual → novo)   ${c_red}-${c_reset}${c_dim} removido   · aviso${c_reset}"
(( DRY_RUN )) && say "${c_yel}modo --dry-run: só mostra o que mudaria; nada será alterado${c_reset}"
say ""

# verificação inicial (sempre roda)
info "${c_bold}check${c_reset} — ${DESC[check]}"
( set -e; step_check ) || { err "abortando: pré-requisitos não atendidos"; exit 1; }
say ""

# mantém o sudo vivo durante a execução
if (( ! DRY_RUN )); then
  ( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
  SUDO_KEEPALIVE=$!
  trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT
fi

applied=(); skipped=(); uptodate=(); failed=(); pending=()
for s in "${selected[@]}"; do
  [[ $s == check ]] && continue
  confirm_step "$s"; rc=$?
  case $rc in
    0) ( set -e; "step_$s" ); rc=$?
       if (( rc == 3 )) && [[ $s == extensions ]]; then
         pending+=("$s")
       elif (( rc != 0 )); then
         err "etapa '$s' falhou (código $rc)"; failed+=("$s")
       else
         applied+=("$s")
       fi ;;
    1) (( PLAN_N == 0 )) && uptodate+=("$s") || skipped+=("$s") ;;
    2) say "  saindo a pedido do usuário"; break ;;
  esac
  say ""
done

say "${c_bold}resumo${c_reset}"
(( ${#applied[@]} ))  && say "  ${c_grn}✔ aplicadas:${c_reset}    ${applied[*]}"
(( ${#uptodate[@]} )) && say "  ${c_grn}✔ já estavam ok:${c_reset} ${uptodate[*]}"
(( ${#skipped[@]} ))  && say "  ${c_yel}↷ puladas:${c_reset}      ${skipped[*]}"
(( ${#pending[@]} )) && say "  ${c_yel}! carregamento pendente no GNOME:${c_reset} ${pending[*]} — saia da sessão, entre novamente e rode ./install.sh --only extensions"
if (( ${#failed[@]} )); then
  say "  ${c_red}✘ com falha:${c_reset}    ${failed[*]}"
  say "  rode de novo só essas etapas:  ./install.sh --only $(IFS=,; echo "${failed[*]}")"
fi
(( ${#applied[@]} )) && say "→ saia da sessão e entre de novo para valer: shell zsh, cursor e extensões."
exit 0
