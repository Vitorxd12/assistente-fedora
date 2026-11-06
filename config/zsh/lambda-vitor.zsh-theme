# lambda-vitor — tema powerline com o λ do Half-Life
# Requer uma Nerd Font (JetBrainsMono Nerd Font)

setopt PROMPT_SUBST

# glifos
typeset -g LV_L=$''      # cápsula esquerda arredondada
typeset -g LV_R=$''      # cápsula direita arredondada
typeset -g LV_SEP=$''    # seta powerline
typeset -g LV_BRANCH=$''
typeset -g LV_FOLDER=$''
typeset -g LV_CLOCK=$''
typeset -g LV_LAMBDA='λ'

# cores (256)
typeset -g LV_ORANGE=208   # fallback; sobrescrito pela cor de destaque do GNOME
typeset -g LV_ACCENT_FG='#ffffff'

# lê a cor de destaque do sistema (GNOME) a cada prompt
lv_accent() {
  local name
  name=$(gsettings get org.gnome.desktop.interface accent-color 2>/dev/null)
  name=${name//\'/}
  case $name in
    blue)   LV_ORANGE='#3584e4' ;;  teal)   LV_ORANGE='#2190a4' ;;
    green)  LV_ORANGE='#3a944a' ;;  yellow) LV_ORANGE='#c88800' ;;
    orange) LV_ORANGE='#ed5b00' ;;  red)    LV_ORANGE='#e62d42' ;;
    pink)   LV_ORANGE='#d56199' ;;  purple) LV_ORANGE='#9141ac' ;;
    slate)  LV_ORANGE='#6f8396' ;;  *)      LV_ORANGE=208 ;;
  esac
  [[ $name == yellow ]] && LV_ACCENT_FG='#1a1b26' || LV_ACCENT_FG='#ffffff'
  # pasta: mesma cor do sistema, ~45% mais escura
  if [[ $LV_ORANGE == \#* ]]; then
    local r=$(( 16#${LV_ORANGE:1:2} * 55 / 100 ))
    local g=$(( 16#${LV_ORANGE:3:2} * 55 / 100 ))
    local b=$(( 16#${LV_ORANGE:5:2} * 55 / 100 ))
    LV_DIR=$(printf '#%02x%02x%02x' $r $g $b)
  else
    LV_DIR=24
  fi
}
typeset -g LV_DARK=235
typeset -g LV_DIR=24
typeset -g LV_GIT_OK=71
typeset -g LV_GIT_DIRTY=178

lv_build() {
  local branch bg marks="" st ab ahead behind
  local line="%F{$LV_ORANGE}$LV_L%K{$LV_ORANGE}%F{$LV_ACCENT_FG}%B $LV_LAMBDA vitor %b"
  line+="%K{$LV_DIR}%F{$LV_ORANGE}$LV_SEP%F{#ffffff} $LV_FOLDER %3~ "
  branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
  if [[ -n $branch ]]; then
    bg=$LV_GIT_OK
    st=$(git status --porcelain 2>/dev/null)
    if [[ -n $st ]]; then
      bg=$LV_GIT_DIRTY
      print -r -- "$st" | grep -q '^??' && marks+=" ?"
      print -r -- "$st" | grep -q '^[MADRC]' && marks+=" +"
      print -r -- "$st" | grep -q '^.[MD]' && marks+=" !"
    fi
    ab=$(git rev-list --left-right --count @{u}...HEAD 2>/dev/null)
    if [[ -n $ab ]]; then
      behind=${ab%%[[:space:]]*}; ahead=${ab##*[[:space:]]}
      (( ahead > 0 )) && marks+=" ⇡$ahead"
      (( behind > 0 )) && marks+=" ⇣$behind"
    fi
    line+="%K{$bg}%F{$LV_DIR}$LV_SEP%F{$LV_DARK} $LV_BRANCH ${branch//\%/%%}$marks "
    line+="%k%F{$bg}$LV_R%f"
  else
    line+="%k%F{$LV_DIR}$LV_R%f"
  fi
  LV_LINE1="$line"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd lv_accent
add-zsh-hook precmd lv_build

PROMPT='${LV_LINE1} %(?.%F{$LV_ORANGE}.%F{196})❯%f '

RPROMPT='%(?..%F{196}✘ %?%f  )%F{240}$LV_CLOCK %*%f'
