defmodule QuizRoom do
  use GenServer
  def start_link(answers), do: GenServer.start_link(__MODULE__, answers)
  def answer(pid, team, question, choice), do: GenServer.call(pid, {:answer, team, question, choice})
  def scoreboard(pid), do: GenServer.call(pid, :scoreboard)
  def leaderboard(pid, limit \\ 10), do: GenServer.call(pid, {:leaderboard, limit})
  def status(pid), do: GenServer.call(pid, :status)
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
  @impl true
  def handle_call(:status, _from, state) do
    reply = %{questions: map_size(state.answers), teams: map_size(state.scores),
              answers_received: MapSet.size(state.seen)}
    {:reply, reply, state}
  end
  @impl true
  def handle_call({:leaderboard, limit}, _from, state) do
    if not is_integer(limit) or limit not in 1..100 do
      {:reply, {:error, :invalid_limit}, state}
    else
      ranking = state.scores
        |> Enum.sort_by(fn {team, score} -> {-score, team} end)
        |> Enum.take(limit)
      {:reply, {:ok, ranking}, state}
    end
  end
  def handle_call({:answer, team, question, choice}, _from, state) do
    key = {team, question}
    cond do
      not is_binary(team) or byte_size(team) not in 1..80 or String.trim(team) == "" or not is_integer(choice) or choice not in 1..4 -> {:reply, {:error, :invalid_answer}, state}
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
    test "leaderboard sorts by points then by team and respects limit" do
      {:ok, pid} = QuizRoom.start_link(%{1 => 2, 2 => 1})
      assert QuizRoom.answer(pid, "Zeta", 1, 2) == {:ok, 10}
      assert QuizRoom.answer(pid, "Alfa", 1, 2) == {:ok, 10}
      assert QuizRoom.answer(pid, "Beta", 1, 4) == {:ok, 0}
      assert QuizRoom.leaderboard(pid, 2) == {:ok, [{"Alfa", 10}, {"Zeta", 10}]}
      assert QuizRoom.leaderboard(pid, 0) == {:error, :invalid_limit}
      assert QuizRoom.status(pid) == %{questions: 2, teams: 3, answers_received: 3}
    end
    test "empty team does not count as a participant" do
      {:ok, pid} = QuizRoom.start_link(%{1 => 2})
      assert QuizRoom.answer(pid, "   ", 1, 2) == {:error, :invalid_answer}
      assert QuizRoom.status(pid).answers_received == 0
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
