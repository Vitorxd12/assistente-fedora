# VLC Redesign

A etapa `flatpak` instala o RPM Fedora do VLC Redesign, configura-o como
aplicativo padrão de áudio e vídeo e remove o VLC oficial se estiver instalado
como Flatpak (instalações de usuário e sistema) ou RPM. A remoção do Flatpak
preserva os dados do perfil antigo.

O RPM instala o app em `/opt/vlc-redesign` e cria a entrada de menu
`org.kuchisofts.VLCRedesign.desktop`. O instalador baixa o arquivo da release do
projeto e confere o SHA-256 fixado em `install.sh` antes de chamar o DNF. As
versões e hashes publicados precisam ser atualizados no script quando o projeto
publicar um RPM novo.

Em 12/11/2026, a release mais recente do projeto é 0.6.2, mas o RPM Fedora
publicado é o 0.6.0; o pacote 0.6.2 disponível para Linux é o AppImage. O
assistente usa o RPM nativo do Fedora, que instala a entrada de menu e o
comando `vlc-redesign`.

O arquivo de vídeo que motivou a troca era H.264 e estava íntegro. A reprodução
com decodificação por software funcionou; por isso, o assistente mantém
`avcodec-hw=none` em `~/.config/vlc/vlcrc`. Isso usa a CPU em vez da decodificação
por hardware e pode aumentar o consumo em vídeos pesados.

Para reaplicar a migração, rode `./install.sh --only flatpak`. Para voltar ao
VLC oficial, instale-o novamente pelo DNF ou Flathub e escolha-o em Aplicativos
Padrão. O perfil antigo do Flatpak não é apagado.
