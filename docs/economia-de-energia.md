# Remover automações de energia

A etapa `energy` agora desativa as automações antigas do assistente que o
G-Helper executava ao alternar entre bateria e tomada. Ela não instala nem
configura um monitor ou uma automação nova; o G-Helper continua instalado e
seus perfis escolhidos manualmente continuam funcionando.

Feche o G-Helper e rode:

```bash
./install.sh --only energy
```

A etapa remove somente os comandos `mode_command_N` que apontam exatamente
para `~/.local/bin/battery-saver --apply`. Outros comandos personalizados do
G-Helper são preservados. Preferências que o assistente alterou são restauradas
se ainda mantiverem o valor instalado por ele; alterações posteriores do usuário
são preservadas. Valores de CPU e inatividade guardados para restauração também
são revertidos quando disponíveis. Preferências AC/bateria que já existiam antes
da automação do assistente voltam ao estado anterior.

Para verificar sem alterar nada, a etapa mostra seu plano antes de perguntar.
O utilitário `bin/battery-saver` também oferece `--restore-check` e `--restore`;
ele existe apenas para limpar instalações antigas e não contém mais comandos
para configurar ou executar ações em mudanças de energia.
