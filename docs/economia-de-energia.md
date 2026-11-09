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
| Tela | reduz cerca de 30% do brilho salvo, com piso de 4% | restaura o brilho anterior à bateria |
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
ajusta apenas brilho real em `/sys/class/backlight`, a flag de boost da CPU
e a preferência GNOME de inatividade, depois encerra. Sem daemon, polling,
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
depois, além do brilho, boost e inatividade salvos. Após sucesso, o arquivo
`~/.local/bin/battery-saver` e o diretório de estado podem ser removidos.
Não execute a etapa energy novamente se não quiser reativá-la.

## Limitação do brilho em Eco neste ASUS

Foi necessário recarregar, com autorização, `nvidia_wmi_ec_backlight`:
o boot Eco anterior havia bloqueado o módulo. Ele controla o backlight pelo EC,
independentemente do driver gráfico NVIDIA. Não foi criada mudança de boot.
Se `/sys/class/backlight` estiver vazio, o auxiliar não inventa brilho via gamma:
aplica as outras economias e informa a ausência em `--status`.

## Referências

- [GNOME: consumo e bateria](https://help.gnome.org/gnome-help/power-batterylife.html)
- [GNOME: brilho](https://help.gnome.org/gnome-help/display-brightness.html)
- [G-Helper Linux: recursos e código](https://github.com/utajum/g-helper-linux)
- [Kernel: backlight WMI/EC](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/nvidia-wmi-ec-backlight.c)

Teste isolado, sem hardware: `python3 -B tests/test_battery_saver.py`.

## Validação nesta instalação (2026-11-09)

Dez testes isolados passaram: bateria/tomada, hooks repetidos, brilho já
baixo, turbo já desligado, início em AC, dispositivo ausente, falha de
permissão e preservação de comandos existentes. Sintaxe bash e git diff
--check passaram. O --dry-run reconhece a etapa já aplicada.

No hardware em bateria: perfil quiet, CPU no_turbo=1, tela 60 Hz, brilho relativo ao valor salvo (sem reduções acumuladas) e teclado no nível 1. O teste físico foi concluído às 16:04:49–16:04:55: retirada do carregador
aplicou Silencioso/quiet, 60 Hz e teclado nível 1; reconexão aplicou
Turbo/performance, 144 Hz e teclado nível 3. O auxiliar executou nos dois
sentidos sem erro; estado final CPU no_turbo=0 e brilho restaurado a 8%.
Snapshots anteriores preservados para reversão da automação. A política AC
foi atualizada a pedido do usuário: Turbo, CPU Boost e teclado no máximo; a tela
restaura o brilho anterior, sem forçar 100%.
Os dois testes adicionais cobrem desempenho na tomada e reversão sem perder backup.
Arquivos config/system/rtw88.conf e wifi-powersave-off.conf intactos. GPU em
Eco (MUX=1, dgpu_disable=1); sem automação de GPU ou novo serviço residente.

Exemplo de brilho: 60% na tomada → 42% na bateria → 60% ao reconectar.
Hooks repetidos não escurecem a tela progressivamente. Uma redução manual
adicional na bateria é respeitada até reconectar.

### Recuperação do processo nesta sessão

No primeiro teste, G-Helper não estava rodando; por isso não observava AC/DC.
Não foi encontrado coredump recente que determinasse a causa do encerramento.
Foi reaberto numa unidade transitória de usuário ghelper-session.service,
fora do grupo do terminal, com Restart=on-failure. Não foi instalado arquivo
permanente de serviço; nos próximos logins vale o autostart nativo.
Após parar o processo de forma sincronizada, performance_0=2, performance_1=1
e o modo atual AC=1 foram confirmados antes de reabrir. A troca física
funcionou sem reinícios do processo. G-Helper continua necessário em execução.
