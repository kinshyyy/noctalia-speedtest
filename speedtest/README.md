# SpeedTest para Noctalia

Plugin local para Noctalia v5.4.0 ou mais recente, com painel, widget de barra, atalho no Controle e serviço de watch. O painel traz um velocímetro semicircular inspirado no Speedtest da Ookla, com escala progressiva, ponteiro e arco animados durante download e upload, além de teste simples/completo, servidor escolhido, lista de servidores, estatísticas, limpeza de histórico e instalação/remoção do atalho `.desktop`. As últimas métricas ficam disponíveis ao reabrir o painel.

O script `speedtest.sh` já vem dentro desta pasta do plugin. O painel e o serviço localizam o arquivo pela pasta real do plugin, sem depender de `/home/vinicius` ou do local onde o pacote foi extraído. O `speedtest-go` é instalado pelo script quando não há um motor compatível no sistema, então não é uma dependência obrigatória para carregar o plugin.

## Instalação local

Copie esta pasta para `$XDG_DATA_HOME/noctalia/plugins/speedtest` (ou `~/.local/share/noctalia/plugins/speedtest` quando `XDG_DATA_HOME` não estiver definido). Em seguida, habilite **SpeedTest** em Configurações → Plugins e adicione `vinicius/speedtest:bar` à barra. O atalho do Controle também abre o painel.

## Configuração

Nas configurações do plugin, você pode definir o ID do servidor, mostrar ou ocultar os dados ISP/IP, ativar o histórico, selecionar a pasta do histórico e configurar o intervalo do modo watch. As opções do widget permitem escolher o ícone, ocultar o rótulo e mostrar o download/upload temporariamente após um teste, com duração configurável de 1 a 120 segundos. As opções de estatísticas e limpeza usam a mesma pasta de histórico configurada.

O modo watch roda em segundo plano enquanto estiver ativado e para quando você o desliga ou encerra o Noctalia. O helper incluído preserva o motor e as operações do script original; ele usa `speedtest-go` se estiver instalado e mantém a instalação automática do programa caso não esteja.
