# Quiz Sala: guia técnico

## Escopo real

Demonstração Elixir com GenServer de sala e pontuação; não há servidor multiplayer publicado.

## Arquivos relacionados

`main.exs` e `ARQUITETURA.md`.

## Procedimento de validação

`elixir main.exs --demo` e `elixir main.exs --self-test` com Elixir/Erlang adequados.

Se algo não puder ser executado, registrar como pendente, sem afirmar sucesso. Preservar resultados reais de CI vinculados aos commits relevantes.

## Casos para revisão

Conferir resposta duplicada, pontuação de equipe inexistente, pergunta malformada, reinício de sala e mensagens simultâneas ao processo.

## Próxima evolução

Ao evoluir para multiplayer, definir autorização de sala, persistência e recuperação de processo sem prometer que o GenServer sozinho fornece isso.

## Para submeter uma mudança

- [ ] Especificar problema e comportamento esperado.
- [ ] Anexar evidência de teste ou reprodução real.
- [ ] Revisar acessibilidade, privacidade e licenças quando aplicável.
- [ ] Submeter em branch separada e revisar antes de merge.
