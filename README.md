# Quiz Sala

Competição de perguntas por equipes em uma sala compartilhada.

## Implementado na primeira versão

**Elixir — núcleo executável de domínio.** Processo GenServer de sala de quiz, com placar serializado, validação de perguntas e uma resposta por equipe e pergunta. Inclui demonstração local e testes ExUnit.

## Como executar

Instale Elixir 1.18 com Erlang/OTP. O arquivo usa somente biblioteca padrão, GenServer ou ExUnit. Os comandos abaixo partem da raiz do repositório.

```sh
elixir main.exs --demo
```

## Testes

```sh
elixir main.exs --self-test
```

Os testes cobrem invariantes e entradas inválidas. A preparação local não dispõe deste runtime; o workflow em `.github/workflows/ci.yml` executa a validação no GitHub Actions. O resultado de cada execução está na aba Actions, associado ao commit.

## Organização e limites

Código e exemplos: `main.exs`. Os dados de exemplo são fictícios. As funções de domínio são separadas da leitura de argumentos no mesmo arquivo para manter a primeira versão pequena e revisável.

A sala existe em memória e se encerra com o processo. A demonstração usa perguntas fictícias. Não há interface de sala, rede, autenticação, temporizador ou Phoenix Channels ainda.

A proposta completa de evolução está em `ARQUITETURA.md`. As tecnologias propostas nessa arquitetura não devem ser interpretadas como dependências já implementadas.

## Próximas entregas

- [ ] Criar sala e perguntas — ampliar o núcleo atual até o fluxo completo.
- [ ] Receber respostas das equipes — ampliar o núcleo atual até o fluxo completo.
- [ ] Atualizar placar em tempo real — ampliar o núcleo atual até o fluxo completo.

Licença: ainda não definida.

## Documentação de desenvolvimento

O [guia de validação e evolução](docs/GUIA_DE_VALIDACAO.md) registra o estado atual, os testes e os próximos incrementos deste projeto.
