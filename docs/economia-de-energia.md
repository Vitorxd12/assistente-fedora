# Economia automática na bateria

Requer G-Helper instalado e configurado, GNOME, Python 3/PyGObject e permissões
nativas do G-Helper já funcionando. Não instala pacotes ou aplicativos.

Feche somente o G-Helper e execute `./install.sh --only energy`. Depois abra-o
novamente. Sem G-Helper configurado a etapa é pulada. A etapa `gnome` deixou
de forçar Desempenho, para não contradizer os perfis automáticos.

## Comportamento

| Controle | Bateria | Tomada |
|---|---|---|
| G-Helper/firmware | Silencioso | Turbo nativo |
| Brilho da tela | preserva o ajuste manual | preserva o ajuste manual |
| CPU Boost | desliga temporariamente | habilitado |
| Inatividade | apaga a tela após até 5 minutos | restaura a preferência anterior |
| Teclado | no máximo nível 1; mantém apagado se já estava apagado | nível máximo suportado |
| Taxa de atualização | 60 Hz e overdrive desligado | maior taxa suportada e overdrive, pelo recurso nativo screen_auto |

Cor GNOME, saturação e tom do teclado são preservados. A redução de CPU Boost
pode diminuir desempenho em tarefas pesadas; não aplica undervolt, watts,
governor manual ou curva de fan. O firmware continua responsável pela refrigeração.
Não altera configurações de Wi-Fi, Bluetooth, GPU/MUX, kernel ou TuneD.
O perfil gráfico Eco continua manual; nunca ligar Optimized/gpu_auto para isso.
O ajuste nativo `aspm=0` impede que a seleção Silencioso/Equilibrado do G-Helper
reescreva a política global PCIe ASPM. A política atual do kernel é preservada;
não são tocados os ajustes específicos de rede do assistente.

## Implementação

O comando por modo nativo `mode_command_N` chama
`~/.local/bin/battery-saver --apply`. O programa consulta OnBattery do UPower,
ajusta apenas a flag de boost da CPU e a preferência GNOME de inatividade, depois encerra. Sem daemon, polling,
timer systemd, sudo ou mudança no código do G-Helper. O observador de energia
existente do G-Helper dispara a seleção AC/DC (pode levar alguns segundos).
G-Helper precisa estar aberto na bandeja/autostart. Se for encerrado, não há
observador alternativo: os ajustes AC são aplicados ao voltar a executá-lo na tomada.

Comandos por modo já configurados pelo usuário não são sobrescritos: a etapa
para com erro, para permitir integração consciente. Hooks repetidos são
idempotentes; guardam o valor original antes de escrever. Falhas de permissão
não elevam privilégios e mantêm a informação de restauração para outra tentativa.

Backups de preferências e valores AC em `~/.local/state/battery-saver/`.
Para conferir sem modificar nada: `~/.local/bin/battery-saver --status`.

## Remoção

Feche o G-Helper e rode `~/.local/bin/battery-saver --restore`; reabra o
G-Helper. Isso restaura as preferências gerenciadas que você não modificou
depois, além do boost e inatividade salvos. Após sucesso, o arquivo
`~/.local/bin/battery-saver` e o diretório de estado podem ser removidos.
Não execute a etapa energy novamente se não quiser reativá-la.

O auxiliar não lê nem escreve o brilho da tela. Snapshots de brilho deixados
por versões anteriores são descartados sem alterar o ajuste atual.

## Referências

- [GNOME: consumo e bateria](https://help.gnome.org/gnome-help/power-batterylife.html)
- [GNOME: brilho](https://help.gnome.org/gnome-help/display-brightness.html)
- [G-Helper Linux: recursos e código](https://github.com/utajum/g-helper-linux)
- [Kernel: backlight WMI/EC](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/nvidia-wmi-ec-backlight.c)

Teste isolado, sem hardware: `python3 -B tests/test_battery_saver.py`.

## Validação

Os testes isolados cobrem bateria/tomada, hooks repetidos, restauração de CPU
e inatividade, falhas de permissão, preservação de comandos e descarte de
snapshots antigos de brilho sem alterar a tela.
