defmodule QuizRoom do
  use GenServer
  def start_link(answers), do: GenServer.start_link(__MODULE__, answers)
  def answer(pid, team, question, choice), do: GenServer.call(pid, {:answer, team, question, choice})
  def scoreboard(pid), do: GenServer.call(pid, :scoreboard)
  @impl true
  def init(answers) when is_map(answers) and map_size(answers) > 0 do
    if Enum.all?(answers, fn {id, answer} -> is_integer(id) and is_integer(answer) and answer in 1..4 end) do
      {:ok, %{answers: answers, seen: MapSet.new(), scores: %{}}}
    else
      {:stop, :invalid_questions}
    end
  end
  @impl true
  def handle_call(:scoreboard, _from, state), do: {:reply, state.scores, state}
  def handle_call({:answer, team, question, choice}, _from, state) do
    key = {team, question}
    cond do
      not is_binary(team) or byte_size(team) not in 1..80 or not is_integer(choice) or choice not in 1..4 -> {:reply, {:error, :invalid_answer}, state}
      not Map.has_key?(state.answers, question) -> {:reply, {:error, :unknown_question}, state}
      MapSet.member?(state.seen, key) -> {:reply, {:error, :already_answered}, state}
      not Map.has_key?(state.scores, team) and map_size(state.scores) >= 100 -> {:reply, {:error, :room_full}, state}
      true ->
        points = if state.answers[question] == choice, do: 10, else: 0
        next = %{state | seen: MapSet.put(state.seen, key), scores: Map.update(state.scores, team, points, &(&1 + points))}
        {:reply, {:ok, points}, next}
    end
  end
end
if System.argv() == ["--self-test"] do
  ExUnit.start()
  defmodule QuizRoomTest do
    use ExUnit.Case
    test "a team can score only once per question" do
      {:ok, pid} = QuizRoom.start_link(%{1 => 2})
      assert QuizRoom.answer(pid, "Azul", 1, 2) == {:ok, 10}
      assert QuizRoom.answer(pid, "Azul", 1, 2) == {:error, :already_answered}
      assert QuizRoom.scoreboard(pid) == %{"Azul" => 10}
    end
    test "invalid questions do not consume an answer" do
      {:ok, pid} = QuizRoom.start_link(%{1 => 2})
      assert QuizRoom.answer(pid, "A", 9, 2) == {:error, :unknown_question}
      assert QuizRoom.answer(pid, "A", 1, 0) == {:error, :invalid_answer}
      assert QuizRoom.answer(pid, "A", 1, 1) == {:ok, 0}
    end
  end
else
  case System.argv() do
    ["--demo"] ->
      {:ok, pid} = QuizRoom.start_link(%{1 => 2, 2 => 1})
      IO.inspect(QuizRoom.answer(pid, "Equipe Azul", 1, 2), label: "Resposta")
      IO.inspect(QuizRoom.answer(pid, "Equipe Verde", 1, 1), label: "Resposta")
      IO.inspect(QuizRoom.scoreboard(pid), label: "Placar")
    _ -> IO.puts(:stderr, "Uso: elixir main.exs --demo | --self-test"); System.halt(2)
  end
end
