# λ assistente-fedora

Pós-instalação do **Fedora Workstation (GNOME)**: transforma uma instalação limpa
no meu setup — terminal kitty + zsh com o tema `lambda-vitor`, cursor Bibata,
extensões do GNOME, atalhos, Firefox e limpeza de apps que não uso.

Testado no Fedora 45 / GNOME 51.

## Uso

```bash
git clone git@github.com:Vitorxd12/assistente-fedora.git
cd assistente-fedora
./install.sh
```

Rode como **seu usuário** (não como root), numa sessão gráfica do GNOME.
O script pede a senha do `sudo` quando precisa.

| Comando | O que faz |
|---|---|
| `./install.sh` | roda tudo (pergunta antes de remover pacotes) |
| `./install.sh --yes` | roda tudo sem perguntar |
| `./install.sh --list` | lista as etapas |
| `./install.sh --only kitty,zsh` | roda só essas etapas |
| `./install.sh --skip flatpak` | roda tudo menos essas |

No fim, **saia da sessão e entre de novo** — shell padrão, cursor e extensões
só valem a partir do próximo login.

## ⚠️ O terminal

O Fedora vem com o **Ptyxis** como terminal. A etapa `terminal` só remove o
Ptyxis **se o script estiver rodando dentro do kitty** — remover o terminal em
que o script está rodando derrubaria a instalação no meio.

Fluxo recomendado numa instalação nova:

1. Abra o Ptyxis e rode `./install.sh` (instala o kitty e configura tudo; o
   Ptyxis é mantido e o script avisa).
2. Abra o kitty (**Super+T**) e rode `./install.sh --only terminal` para
   remover o Ptyxis.

## Etapas

| Etapa | O que faz |
|---|---|
| `check` | verifica Fedora, GNOME, usuário e sudo |
| `packages` | instala kitty, zsh, git, fontes, pt-BR; remove Boxes, Mapas, Clima, Contatos, Agenda, Relógios, LibreOffice, Orca, Ajuda, controle parental, teclados asiáticos… |
| `flatpak` | libera o Flathub completo; instala VLC, Extension Manager, VS Code; VLC como player padrão |
| `fonts` | JetBrainsMono Nerd Font |
| `cursor` | Bibata Modern Ice (branco) para GNOME, GTK, XWayland e Flatpak — gera a versão SVG (`cursors_scalable/`) que o GNOME 51 exige |
| `zsh` | oh-my-zsh + autosuggestions + syntax-highlighting, tema `lambda-vitor`, `.zshrc`; zsh como shell padrão |
| `kitty` | `kitty.conf`, fundo = wallpaper do GNOME borrado, cor de destaque do sistema no kitty |
| `gnome` | modo escuro, cor vermelha, wallpaper, botões min/max, teclado ABNT2, mouse sem aceleração, sem arquivos recentes, dock vazia, atalhos, favoritos do Nautilus (repos, Documents, Downloads), perfil de energia Desempenho |
| `extensions` | Tiling Shell, Clipboard Indicator, Blur my Shell (Liquid Glass na barra, visão geral e menus; some quando uma janela encosta na barra), Compiz Windows Effect, Astra Monitor (CPU, GPU, memória e sensores na barra, modo compacto) + extensão local que tira o botão "Mostrar aplicativos" |
| `firefox` | página inicial padrão (em vez da do Fedora) e reabrir abas da sessão anterior |
| `auth` | desativa login por digital e smartcard |
| `terminal` | kitty como terminal padrão; remove o Ptyxis (só dentro do kitty) |

## Atalhos configurados

| Atalho | Ação |
|---|---|
| Super+T | abre o kitty |
| Super+E | abre o Nautilus |
| Super+V | histórico da área de transferência |
| Super+M | notificações |

## Terminal

- Prompt numa linha: `λ vitor  ~/pasta  branch ❯`, nas cores de destaque do GNOME
  (a pasta usa a mesma cor, escurecida). O `❯` fica vermelho quando o último
  comando falha.
- Ao digitar `cd `, as pastas aparecem embaixo; Tab escolhe.
- `z pasta` pula para pastas já visitadas; ↑/↓ buscam no histórico pelo que
  já foi digitado; Esc Esc põe `sudo`; `x arquivo.zip` extrai qualquer formato.
- Fundo: o papel de parede do GNOME borrado. Trocou o wallpaper? Rode
  `kitty-wallpaper` (ou `kitty-wallpaper 30` para mais blur).

## Estrutura

```
install.sh                    script principal (etapas)
bin/accent-sync               cor de destaque do GNOME → kitty
bin/kitty-wallpaper           wallpaper do GNOME → fundo borrado do kitty
bin/cursor-scalable           converte cursores Xcursor para o formato SVG do GNOME 51
systemd/accent-sync.service   mantém a cor sincronizada
config/zsh/                   .zshrc e tema lambda-vitor
config/kitty/kitty.conf
config/firefox/user.js
config/vlc-mimeapps.list      formatos abertos pelo VLC
config/extensions/            configurações das extensões + extensão local
```

Logs de cada execução ficam em `~/.cache/assistente-fedora-DATA.log`.
