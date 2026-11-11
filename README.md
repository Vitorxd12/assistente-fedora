# λ assistente-fedora

Pós-instalação do **Fedora Workstation (GNOME)**: transforma uma instalação limpa
no meu setup — terminal kitty + zsh com o tema `lambda-vitor`, cursor Bibata,
extensões do GNOME, papel de parede sincronizado com a cor de destaque, atalhos,
Firefox e limpeza de apps que não uso.

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
| `./install.sh` | mostra o que vai mudar e pergunta a cada etapa |
| `./install.sh --dry-run` | só mostra o que mudaria nesta máquina, sem alterar nada |
| `./install.sh --yes` | aplica tudo sem perguntar (o plano continua aparecendo) |
| `./install.sh --list` | lista as etapas |
| `./install.sh --only kitty,zsh` | roda só essas etapas |
| `./install.sh --only wallpaper,extensions` | instala o wallpaper dinâmico e os botões personalizados |
| `./install.sh --skip flatpak` | roda tudo menos essas |

### Como é cada etapa

Antes de mexer em qualquer coisa, o script calcula o que realmente vai mudar
**nesta máquina** e pergunta:

```
╭─ gnome — tema escuro, atalhos, teclado, privacidade, dock
│  ~ tema escuro: 'default' → 'prefer-dark'
│  ~ cor de destaque: 'blue' → 'red'
│  ~ apps fixados na dock (dock vazia): ['org.mozilla.firefox.desktop', …] → @as []
│  + atalho no Nautilus: repos
╰─ Aplicar 4 mudança(s)? [S]im  [n]ão  [d]iferenças  [q]sair:
```

- `+` novo · `~` alterado (valor atual → novo) · `-` removido · `·` aviso
- **d** mostra o antes/depois de cada arquivo que será substituído
- etapas que já estão aplicadas são puladas sem perguntar
- arquivos substituídos ganham backup (`arquivo.bak-DATA`)
- no fim aparece um resumo: aplicadas, já estavam ok, puladas, com falha

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
| `packages` | instala kitty, zsh, git, fontes, pt-BR; remove Boxes, Mapas, Clima, Contatos, Agenda, Relógios, LibreOffice, leitor de tela Orca, Ajuda, controle parental, teclados asiáticos… |
| `flatpak` | libera o Flathub completo; instala VLC, Extension Manager, VS Code; VLC como player padrão |
| `orca` | instala o [Orca da Stably](https://github.com/stablyai/orca), orquestrador de agentes, com ícone oficial no menu; versão 1.4.256 para x86_64, download verificado por SHA-256 e arquivos em `~/.local/opt/orca`, sem sudo ou FUSE |
| `fonts` | JetBrainsMono Nerd Font |
| `cursor` | Bibata Modern Ice (branco) para GNOME, GTK, XWayland e Flatpak — gera a versão SVG (`cursors_scalable/`) que o GNOME 51 exige |
| `zsh` | oh-my-zsh + autosuggestions + syntax-highlighting, tema `lambda-vitor`, `.zshrc`; zsh como shell padrão |
| `tools` | ferramentas modernas: eza, dust, delta, btop, tokei, hyperfine; git usando o delta |
| `kitty` | `kitty.conf`, fundo = wallpaper do GNOME borrado, cor de destaque do sistema no kitty |
| `gnome` | modo escuro, cor roxa padrão, relógio em 24 horas, botões min/max, teclado ABNT2, sem arquivos recentes, dock vazia, atalhos, favoritos do Nautilus (repos, Documents, Downloads); preserva o perfil de energia |
| `energy` | com G-Helper já configurado: Silencioso na bateria, turbo temporariamente desligado, tela inativa em até 5 minutos, teclado em nível baixo e atualização automática; na tomada usa Turbo, CPU Boost, teclado no máximo e restaura a inatividade. Não altera GPU, rede, Bluetooth, fans ou TuneD |
| `wallpaper` | papel de parede Blobs claro/escuro acompanha a cor de destaque; o vermelho mantém o SVG original e `--uninstall` restaura os wallpapers anteriores |
| `extensions` | Tiling Shell, Clipboard Indicator, Blur my Shell (Liquid Glass na barra, visão geral e menus, com escurecimento leve; some quando uma janela encosta na barra), Compiz Windows Effect, Astra Monitor (CPU, GPU, memória e sensores na barra, modo compacto), gestos do touchpad, esconde Mostrar aplicativos, dá botões e arrasto ao kitty sem barra de título e adiciona às Configurações Rápidas o seletor de cor de destaque e o botão **Tela sempre ligada** |
| `firefox` | página inicial padrão (em vez da do Fedora), reabrir abas da sessão anterior abas embaixo da barra de endereço e botões da janela na barra de cima (`userChrome.css`) |
| `vscode` | configurações do VS Code (tema Catppuccin Mocha, salvar automático) e extensões (`config/vscode/extensions.txt`) |
| `bluetooth` | só em placas Realtek rtw88 (ex.: RTL8821CE, Wi-Fi e Bluetooth no mesmo chip): desliga a economia de energia profunda/ASPM do driver e o power save do Wi-Fi, que travam o firmware e fazem o fone Bluetooth (LDAC) cortar. Vale após reiniciar |
| `auth` | desativa login por digital e smartcard |
| `terminal` | kitty como terminal padrão; remove o Ptyxis (só dentro do kitty) |

Para instalar só o orquestrador: `./install.sh --only orca`.
Para visualizar as mudanças: `./install.sh --only orca --dry-run`.
O leitor de tela Orca removido na etapa `packages` é um aplicativo diferente.
A etapa preserva backups dos arquivos substituídos e não abre o aplicativo.

## Atalhos configurados

| Atalho | Ação |
|---|---|
| Super+T | abre o kitty |
| Super+E | abre o Nautilus |
| Super+D | mostra a área de trabalho; novamente restaura as janelas |
| Super+V | histórico da área de transferência |
| Super+M | notificações |

## Terminal

- Prompt numa linha: `λ nome  ~/pasta  branch ❯`, nas cores de destaque do GNOME
  (a pasta usa a mesma cor, escurecida). O `❯` fica vermelho quando o último
  comando falha. Ao aplicar a etapa `zsh`, o instalador pergunta qual nome
  mostrar; ele fica salvo em
  `~/.config/assistente-fedora/prompt-name`. Com `--yes`, usa o nome já salvo
  ou, na primeira execução, o nome da conta do Linux.
- Ao digitar `cd `, as pastas aparecem embaixo; Tab escolhe.
- `cd nome` funciona de qualquer lugar: se a pasta não existe ali, pula para
  a pasta mais usada com esse nome (ex.: `cd tecsus` da home).
- `z pasta` pula para pastas já visitadas; ↑/↓ buscam no histórico pelo que
  já foi digitado; Esc Esc põe `sudo`; `x arquivo.zip` extrai qualquer formato.
- Comandos modernos com os nomes de sempre: `ls` → eza, `cat` → bat,
  `du` → dust, `diff` → delta, `top` → btop. Com as opções
  clássicas (`du -sh`, `diff -u`) roda o comando original; para
  forçar o original, use `\comando` (ex.: `\ls`). `cd`/`z`, `grep` e `find`
  continuam os originais.
- Fundo: o papel de parede do GNOME borrado. O serviço `accent-sync` acompanha
  mudanças do wallpaper, tema claro/escuro e cor de destaque automaticamente;
  cada atualização cria um novo arquivo de fundo para o Kitty recarregá-lo.
  Para gerar manualmente, rode `kitty-wallpaper` (ou `kitty-wallpaper 30` para mais blur).
- Gestos no GNOME/Wayland: três dedos para cima/baixo ajustam o volume;
  quatro dedos para os lados trocam as áreas de trabalho, e para cima/baixo
  abrem/fecham a visão geral e a grade de aplicativos (Touchpad Gesture Customization).

## Estrutura

```
install.sh                    script principal (etapas)
bin/install-orca              instala o orquestrador Orca e seu ícone oficial
bin/accent-sync               cor de destaque do GNOME → kitty
bin/kitty-wallpaper           wallpaper do GNOME → fundo borrado do kitty
bin/gnome-accent-wallpaper    cor de destaque do GNOME → wallpaper Blobs
bin/cursor-scalable           converte cursores Xcursor para o formato SVG do GNOME 51
systemd/accent-sync.service   mantém a cor sincronizada
config/zsh/                   .zshrc e tema lambda-vitor
config/kitty/kitty.conf
config/firefox/              user.js e userChrome.css
config/vlc-mimeapps.list      formatos abertos pelo VLC
config/vscode/                settings.json e lista de extensões
config/system/                arquivos de /etc (driver rtw88 e power save do Wi-Fi)
config/extensions/            configurações das extensões + extensão local
config/extensions/accent-quick-settings@vitor.local/ seletor de cor e botões do menu rápido
```

Logs de cada execução ficam em `~/.cache/assistente-fedora-DATA.log`.
