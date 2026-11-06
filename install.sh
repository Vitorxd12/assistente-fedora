#!/usr/bin/env bash
# ╭──────────────────────────────────────────────────────────────╮
# │  assistente-fedora — pós-instalação do Fedora Workstation    │
# │  Reaplica: pacotes, flatpaks, terminal (kitty + zsh), cursor,│
# │  GNOME, extensões e Firefox.                                 │
# ╰──────────────────────────────────────────────────────────────╯
#
#   ./install.sh                 roda tudo (pergunta antes de remover pacotes)
#   ./install.sh --yes           roda tudo sem perguntar
#   ./install.sh --only kitty,zsh
#   ./install.sh --skip flatpak
#   ./install.sh --list          lista as etapas
#
# Pode ser rodado várias vezes: cada etapa verifica o que já existe e
# faz backup (*.bak-DATA) antes de sobrescrever qualquer arquivo.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
LOG="$HOME/.cache/assistente-fedora-$TS.log"
mkdir -p "$HOME/.cache"

STEPS=(check packages flatpak fonts cursor zsh kitty gnome extensions firefox auth terminal)
declare -A DESC=(
  [check]="verifica Fedora, GNOME, usuário e sudo"
  [packages]="instala pacotes base e remove apps que não uso"
  [flatpak]="libera o Flathub completo e instala VLC, Extension Manager e VS Code"
  [fonts]="instala a JetBrainsMono Nerd Font"
  [cursor]="instala o cursor Bibata (branco) em todos os apps"
  [zsh]="oh-my-zsh, plugins, tema lambda-vitor e .zshrc; zsh como shell padrão"
  [kitty]="config do kitty, fundo borrado do wallpaper, cor de destaque"
  [gnome]="tema escuro, atalhos, teclado/mouse, privacidade, dock"
  [extensions]="Tiling Shell, Clipboard Indicator, Blur my Shell, Compiz effect, Astra Monitor + configs"
  [firefox]="página inicial padrão e restaurar abas da sessão anterior"
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

PKGS_INSTALL=(
  langpacks-pt_BR kitty zsh git curl bat
  liberation-fonts google-carlito-fonts hunspell-pt
  ImageMagick python3-gobject python3-cairo
  libgtop2                        # usado pelo Astra Monitor
)
PKGS_REMOVE=(
  gnome-boxes gnome-connections gnome-maps gnome-weather gnome-contacts
  gnome-tour gnome-calendar gnome-clocks mediawriter rygel decibels
  showtime snapshot simple-scan orca yelp malcontent-control
  ibus-anthy ibus-chewing ibus-hangul ibus-libpinyin ibus-libzhuyin
  'libreoffice*'
)
FLATPAKS=(org.videolan.VLC com.mattjakeman.ExtensionManager com.visualstudio.code)

# ── utilidades ────────────────────────────────────────────────
c_reset=$'\e[0m'; c_bold=$'\e[1m'; c_red=$'\e[31m'; c_grn=$'\e[32m'; c_yel=$'\e[33m'; c_acc=$'\e[38;5;208m'
say()  { printf '%s\n' "$*" | tee -a "$LOG"; }
info() { say "${c_acc}λ${c_reset} $*"; }
ok()   { say "  ${c_grn}✔${c_reset} $*"; }
warn() { say "  ${c_yel}!${c_reset} $*"; }
err()  { say "  ${c_red}✘${c_reset} $*"; }

ASSUME_YES=0
ask() {  # ask "pergunta" → 0 se sim
  (( ASSUME_YES )) && return 0
  local r; read -r -p "  ? $1 [s/N] " r </dev/tty
  [[ ${r,,} == s* || ${r,,} == y* ]]
}

backup() {  # faz backup de um arquivo existente antes de sobrescrever
  local f="$1"
  [[ -e $f && ! -L $f ]] && cp -a "$f" "$f.bak-$TS" && warn "backup: $f.bak-$TS"
  return 0
}

put() {  # put ORIGEM DESTINO — copia com backup se o conteúdo mudou
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -f $dst ]] && cmp -s "$src" "$dst"; then ok "já atualizado: $dst"; return 0; fi
  backup "$dst"
  cp "$src" "$dst" && ok "instalado: $dst"
}

gset() {  # gset schema chave valor — ignora schemas inexistentes
  if gsettings writable "$1" "$2" &>/dev/null; then
    gsettings set "$1" "$2" "$3"
  else
    warn "configuração inexistente nesta versão: $1 $2"
  fi
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

running_in_kitty() { [[ $(parent_terminal) == kitty ]]; }

# ── etapas ────────────────────────────────────────────────────
step_check() {
  [[ $EUID -ne 0 ]] || { err "não rode como root; rode como seu usuário (o script usa sudo quando precisa)"; return 1; }
  grep -q '^ID=fedora' /etc/os-release || { err "isto não parece ser Fedora"; return 1; }
  local ver; ver=$(. /etc/os-release; echo "$VERSION_ID")
  ok "Fedora $ver"
  [[ ${XDG_CURRENT_DESKTOP:-} == *GNOME* ]] || warn "GNOME não detectado (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-vazio})"
  [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || warn "sem sessão gráfica/D-Bus: etapas do GNOME podem falhar"
  ok "rodando no terminal: $(parent_terminal)"
  sudo -v || { err "sudo necessário"; return 1; }
  ok "sudo ok"
}

step_packages() {
  local present=() p
  for p in "${PKGS_REMOVE[@]}"; do
    if [[ $p == *'*'* ]]; then
      if rpm -qa "$p" | grep -q .; then present+=("$p"); fi
    else
      if rpm -q --quiet "$p"; then present+=("$p"); fi
    fi
  done
  if (( ${#present[@]} )); then
    info "pacotes a remover: ${present[*]}"
    if ask "remover esses pacotes?"; then
      sudo dnf remove -y "${present[@]}" 2>&1 | tee -a "$LOG" | tail -3
    else
      warn "remoção pulada"
    fi
  else
    ok "nada para remover"
  fi
  info "instalando pacotes base"
  sudo dnf install -y "${PKGS_INSTALL[@]}" 2>&1 | tee -a "$LOG" | tail -3
}

step_flatpak() {
  command -v flatpak >/dev/null || { err "flatpak não instalado"; return 1; }
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  sudo flatpak remote-modify --enable --no-filter flathub && ok "Flathub completo liberado"
  sudo flatpak install -y --noninteractive flathub "${FLATPAKS[@]}" 2>&1 | tee -a "$LOG" | tail -3
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
  if fc-list : family | grep -qi 'JetBrainsMono Nerd Font'; then ok "JetBrainsMono Nerd Font já instalada"; return 0; fi
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
  gset org.gnome.desktop.interface cursor-theme "$CURSOR_THEME"
  gset org.gnome.desktop.interface cursor-size 24
  ok "cursor $CURSOR_THEME configurado (relogue para valer em tudo)"
}

step_zsh() {
  command -v zsh >/dev/null || { err "zsh não instalado (rode a etapa packages)"; return 1; }
  if [[ ! -d $HOME/.oh-my-zsh ]]; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
      "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "oh-my-zsh instalado"
  else
    ok "oh-my-zsh já instalado"
  fi
  local C="$HOME/.oh-my-zsh/custom" r n
  for r in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting; do
    n=${r#*/}
    if [[ -d $C/plugins/$n ]]; then ok "plugin $n já existe"
    else git clone -q --depth=1 "https://github.com/$r" "$C/plugins/$n" && ok "plugin $n"; fi
  done
  put "$REPO/config/zsh/lambda-vitor.zsh-theme" "$C/themes/lambda-vitor.zsh-theme"
  put "$REPO/config/zsh/zshrc" "$HOME/.zshrc"
  if [[ $(getent passwd "$USER" | cut -d: -f7) != */zsh ]]; then
    sudo usermod -s "$(command -v zsh)" "$USER" && ok "zsh agora é o shell padrão (vale no próximo login)"
  else
    ok "zsh já é o shell padrão"
  fi
}

step_kitty() {
  command -v kitty >/dev/null || { err "kitty não instalado (rode a etapa packages)"; return 1; }
  local tmp; tmp=$(mktemp)
  sed "s|__HOME__|$HOME|g" "$REPO/config/kitty/kitty.conf" > "$tmp"
  put "$tmp" "$HOME/.config/kitty/kitty.conf"; rm -f "$tmp"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$REPO/bin/accent-sync"    "$HOME/.local/bin/accent-sync"    && ok "instalado ~/.local/bin/accent-sync"
  install -m 755 "$REPO/bin/kitty-wallpaper" "$HOME/.local/bin/kitty-wallpaper" && ok "instalado ~/.local/bin/kitty-wallpaper"
  # cor de destaque → kitty (gera accent.conf)
  "$HOME/.local/bin/accent-sync" && ok "cor de destaque aplicada"
  # serviço que acompanha mudanças da cor de destaque
  mkdir -p "$HOME/.config/systemd/user"
  put "$REPO/systemd/accent-sync.service" "$HOME/.config/systemd/user/accent-sync.service"
  if systemctl --user daemon-reload 2>/dev/null; then
    systemctl --user enable --now accent-sync.service 2>/dev/null && ok "serviço accent-sync ativo" \
      || warn "não consegui ativar o accent-sync agora; rode: systemctl --user enable --now accent-sync"
  fi
  # fundo do terminal = wallpaper do GNOME borrado
  "$HOME/.local/bin/kitty-wallpaper" || warn "não consegui gerar o fundo; rode depois: kitty-wallpaper"
}

step_gnome() {
  # aparência
  gset org.gnome.desktop.interface color-scheme 'prefer-dark'
  gset org.gnome.desktop.interface accent-color 'red'
  gset org.gnome.desktop.interface enable-hot-corners false
  gset org.gnome.desktop.background picture-uri      'file:///usr/share/backgrounds/gnome/blobs-l.svg'
  gset org.gnome.desktop.background picture-uri-dark 'file:///usr/share/backgrounds/gnome/blobs-d.svg'
  gset org.gnome.desktop.background picture-options 'zoom'
  gset org.gnome.desktop.screensaver picture-uri 'file:///usr/share/backgrounds/gnome/blobs-l.svg'
  # janelas
  gset org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'
  # teclado e mouse
  gset org.gnome.desktop.input-sources sources "[('xkb', 'br')]"
  gset org.gnome.desktop.peripherals.keyboard numlock-state true
  gset org.gnome.desktop.peripherals.mouse accel-profile 'flat'
  gset org.gnome.desktop.peripherals.mouse speed ' -0.13'   # espaço evita ser lido como opção
  gset org.gnome.desktop.peripherals.touchpad two-finger-scrolling-enabled true
  # privacidade (remember-recent-files=false também tira "Recentes" do Nautilus)
  gset org.gnome.desktop.privacy remember-recent-files false
  gset org.gnome.desktop.privacy report-technical-problems false
  # dock vazia
  gset org.gnome.shell favorite-apps "@as []"
  # Super+V fica para a área de transferência; notificações em Super+M
  gset org.gnome.shell.keybindings toggle-message-tray "['<Super>m']"
  # atalhos personalizados: Super+T kitty, Super+E arquivos
  local P=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings
  local S=org.gnome.settings-daemon.plugins.media-keys.custom-keybinding
  gsettings set "$S:$P/custom0/" name 'Terminal'
  gsettings set "$S:$P/custom0/" command 'kitty'
  gsettings set "$S:$P/custom0/" binding '<Super>t'
  gsettings set "$S:$P/custom1/" name 'Arquivos'
  gsettings set "$S:$P/custom1/" command 'nautilus --new-window'
  gsettings set "$S:$P/custom1/" binding '<Super>e'
  gset org.gnome.settings-daemon.plugins.media-keys custom-keybindings "['$P/custom0/', '$P/custom1/']"
  # serviço de localização ligado
  gset org.gnome.system.location enabled true
  # atalhos na barra lateral do Nautilus
  mkdir -p "$HOME/repos"
  local bm="$HOME/.config/gtk-3.0/bookmarks" d
  mkdir -p "$(dirname "$bm")"; touch "$bm"
  for d in repos Documents Downloads; do
    grep -q "^file://$HOME/$d " "$bm" || echo "file://$HOME/$d $d" >> "$bm"
  done
  ok "atalhos do Nautilus: repos, Documents, Downloads"
  # perfil de energia: Desempenho
  if busctl set-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
       org.freedesktop.UPower.PowerProfiles ActiveProfile s performance 2>/dev/null; then
    ok "perfil de energia: desempenho"
  else
    warn "não consegui ativar o perfil Desempenho (máquina sem suporte?)"
  fi
  ok "configurações do GNOME aplicadas"
}

step_extensions() {
  command -v gnome-extensions >/dev/null || { err "gnome-extensions não encontrado"; return 1; }
  local shell_ver uuid info url tmp
  shell_ver=$(gnome-shell --version | grep -oE '[0-9]+' | head -1)
  for uuid in "${EXTENSIONS[@]}"; do
    if [[ -d $HOME/.local/share/gnome-shell/extensions/$uuid ]]; then ok "$uuid já instalada"; continue; fi
    info=$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$shell_ver") \
      || { err "$uuid: sem versão para GNOME $shell_ver"; continue; }
    url=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["download_url"])' "$info") \
      || { err "$uuid: resposta inválida"; continue; }
    tmp=$(mktemp --suffix=.zip)
    curl -fsSL "https://extensions.gnome.org$url" -o "$tmp" && gnome-extensions install --force "$tmp" \
      && ok "$uuid instalada" || err "$uuid: falha ao instalar"
    rm -f "$tmp"
  done
  # extensão local que esconde o botão "Mostrar aplicativos"
  local dst="$HOME/.local/share/gnome-shell/extensions/hide-show-apps@vitor.local"
  mkdir -p "$dst"
  cp "$REPO/config/extensions/hide-show-apps@vitor.local/"* "$dst/" && ok "hide-show-apps@vitor.local instalada"
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
  gset org.gnome.shell disable-user-extensions false
  ok "extensões ativadas"
  # configurações das extensões (Blur my Shell, Clipboard Super+V, layouts do Tiling Shell...)
  dconf load /org/gnome/shell/extensions/ < "$REPO/config/extensions/settings.dconf" && ok "configurações das extensões aplicadas"
}

step_firefox() {
  local profiles=() d
  find_profiles() {
    profiles=()
    for d in "$HOME"/.config/mozilla/firefox/*/ "$HOME"/.mozilla/firefox/*/; do
      if [[ -f $d/prefs.js || -f $d/times.json ]]; then profiles+=("$d"); fi
    done
    return 0
  }
  find_profiles
  if (( ${#profiles[@]} == 0 )) && command -v firefox >/dev/null; then
    if pgrep -x firefox >/dev/null; then
      warn "Firefox aberto e sem perfil detectado; feche-o e rode: ./install.sh --only firefox"
      return 0
    fi
    info "criando perfil do Firefox (abre em segundo plano por alguns segundos)"
    timeout 12 firefox --headless about:blank >/dev/null 2>&1 || true
    find_profiles
  fi
  (( ${#profiles[@]} )) || { warn "nenhum perfil do Firefox encontrado; abra o Firefox uma vez e rode: ./install.sh --only firefox"; return 0; }
  for d in "${profiles[@]}"; do put "$REPO/config/firefox/user.js" "${d%/}/user.js"; done
  pgrep -x firefox >/dev/null && warn "reinicie o Firefox (Ctrl+Q) para aplicar"
  return 0
}

step_auth() {
  if authselect current 2>/dev/null | grep -q with-fingerprint; then
    sudo authselect disable-feature with-fingerprint && sudo authselect apply-changes && ok "login por digital desativado"
  else
    ok "login por digital já está desativado"
  fi
  gset org.gnome.login-screen enable-fingerprint-authentication false
  gset org.gnome.login-screen enable-smartcard-authentication false
  gset org.gnome.login-screen enable-switchable-authentication false
}

step_terminal() {
  # kitty como terminal padrão (Nautilus "abrir no terminal", apps que usam xdg-terminal-exec)
  mkdir -p "$HOME/.config"
  echo "kitty.desktop" > "$HOME/.config/xdg-terminals.list"
  echo "kitty.desktop" > "$HOME/.config/gnome-xdg-terminals.list"
  gset org.gnome.desktop.default-applications.terminal exec 'kitty' 2>/dev/null || true
  ok "kitty definido como terminal padrão"

  # Remover o Ptyxis SÓ se este script estiver rodando dentro do kitty.
  # Se estiver rodando no Ptyxis (ou outro terminal), removê-lo derrubaria o
  # terminal no meio da instalação — então pulamos e avisamos.
  if ! rpm -q --quiet ptyxis; then ok "Ptyxis já removido"; return 0; fi
  local term; term=$(parent_terminal)
  if [[ $term != kitty ]]; then
    warn "rodando no terminal '$term', não no kitty → NÃO vou remover o Ptyxis agora."
    warn "abra o kitty (Super+T) e rode:  $REPO/install.sh --only terminal"
    return 0
  fi
  if ask "remover o Ptyxis (terminal padrão do Fedora)?"; then
    sudo dnf remove -y ptyxis 2>&1 | tee -a "$LOG" | tail -3
  fi
}

# ── execução ──────────────────────────────────────────────────
usage() { sed -n '8,16p' "$0" | sed 's/^# \{0,1\}//'; }

ONLY=""; SKIP=""
while (( $# )); do
  case "$1" in
    -y|--yes)  ASSUME_YES=1 ;;
    --only)    ONLY="$2"; shift ;;
    --only=*)  ONLY="${1#*=}" ;;
    --skip)    SKIP="$2"; shift ;;
    --skip=*)  SKIP="${1#*=}" ;;
    --list)    for s in "${STEPS[@]}"; do printf '  %-11s %s\n' "$s" "${DESC[$s]}"; done; exit 0 ;;
    -h|--help) usage; exit 0 ;;
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

say "${c_bold}${c_acc}λ assistente-fedora${c_reset}  —  log: $LOG"
say "etapas: ${selected[*]}"
say ""

# mantém o sudo vivo durante a execução
( while true; do sudo -n true 2>/dev/null; sleep 50; kill -0 $$ 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null' EXIT

failed=()
for s in "${selected[@]}"; do
  info "${c_bold}$s${c_reset} — ${DESC[$s]}"
  ( set -e; "step_$s" ); rc=$?
  if (( rc != 0 )); then
    err "etapa '$s' falhou (código $rc)"
    failed+=("$s")
    [[ $s == check ]] && { err "abortando: pré-requisitos não atendidos"; exit 1; }
  fi
  say ""
done

if (( ${#failed[@]} )); then
  say "${c_yel}concluído com falhas em: ${failed[*]}${c_reset}"
  say "rode de novo só essas etapas:  ./install.sh --only $(IFS=,; echo "${failed[*]}")"
else
  say "${c_grn}tudo pronto!${c_reset}"
fi
say "→ saia da sessão e entre de novo para valer: shell zsh, cursor e extensões."
