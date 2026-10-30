# Fonte Git do SpeedTest para Noctalia

Este repositório distribui o plugin `vinicius/speedtest` para Noctalia v5.4.0 ou mais recente.

![Painel do SpeedTest no Noctalia](screenshots/speedtest-panel.png)

Adicione a fonte e habilite o plugin:

```sh
noctalia msg plugins source add vinicius-speedtest git https://github.com/kinshyyy/noctalia-speedtest.git
noctalia msg plugins enable vinicius/speedtest
```

As atualizações podem ser buscadas com:

```sh
noctalia msg plugins update vinicius-speedtest
```

O código do plugin fica em `speedtest/`, conforme o ID `vinicius/speedtest`. Consulte [`speedtest/README.md`](speedtest/README.md) para detalhes de instalação e configuração.
