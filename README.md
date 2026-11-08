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


## Torneios por rodadas (nova implementação)

O módulo `tournament.exs` complementa o GenServer original sem alterar sua API.
Ele permite cadastrar até 500 perguntas, configurar até 500 equipes, iniciar rodadas
com perguntas não repetidas, receber respostas concorrentes, pausar/retomar a
rodada, fechar e apurar os resultados. O placar só é atualizado ao fechar a rodada,
evitando divulgar respostas corretas durante a competição.

```sh
elixir -r tournament.exs -e '
{:ok, pid} = QuizTournament.start_link(%{
  1 => %{correct: 2, points: 10, category: "História"},
  2 => %{correct: 4, points: 20, category: "Ciências"}
})
{:ok, "Azul"} = QuizTournament.register(pid, "Azul")
{:ok, "Verde"} = QuizTournament.register(pid, "Verde")
{:ok, 1} = QuizTournament.start_round(pid, [1, 2])
{:ok, :recorded} = QuizTournament.submit(pid, "Azul", 1, 2)
{:ok, _} = QuizTournament.close_round(pid)
IO.inspect(QuizTournament.leaderboard(pid))
IO.puts(QuizTournament.export_csv(pid))
'
```

As pontuações usam o valor da pergunta e bônus de sequência de até 6 pontos
por resposta correta. Erros zeram a sequência; questões não respondidas não
são contabilizadas como erros. O relatório por categoria e o histórico de rodadas
permitem acompanhar o desempenho de cada equipe.

### Testes e CI

```sh
elixir main.exs --self-test
elixir tournament_test.exs
```

O workflow executa **ambas** as suítes em Elixir 1.18. A suíte adicional cobre
validação, limites, concorrência, segurança da exportação CSV, pontuação,
placar, histórico e isolamento entre salas. CSV neutraliza células que poderiam
ser interpretadas como fórmulas por planilhas.

### Limites atuais

O estado permanece em memória: reiniciar o processo encerra a competição.
Não há autenticação, cronômetro persistente, banco de dados ou comunicação
via WebSocket. Esses itens exigem implementação própria e não são anunciados
como recursos já entregues.
