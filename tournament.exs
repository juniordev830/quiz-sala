defmodule QuizTournament do
  @moduledoc """
  Tournament coordinator for classroom quizzes.

  Teams register before play. A round exposes a selected subset of the question
  bank, and each team can submit one answer to each question. Answers are kept
  private until the round closes. The scoreboard is deterministic and ties are
  resolved by correct answers, then by the normalized team name.
  """
  use GenServer

  @max_questions 500
  @max_team_name 80
  @max_category_name 60

  def start_link(questions, opts \\ []) do
    GenServer.start_link(__MODULE__, {questions, opts})
  end

  def register(pid, name), do: GenServer.call(pid, {:register, name})
  def unregister(pid, name), do: GenServer.call(pid, {:unregister, name})
  def add_question(pid, id, question), do: GenServer.call(pid, {:add_question, id, question})
  def start_round(pid, ids), do: GenServer.call(pid, {:start_round, ids})
  def submit(pid, name, id, choice), do: GenServer.call(pid, {:submit, name, id, choice})
  def pause(pid), do: GenServer.call(pid, :pause)
  def resume(pid), do: GenServer.call(pid, :resume)
  def close_round(pid), do: GenServer.call(pid, :close_round)
  def leaderboard(pid), do: GenServer.call(pid, :leaderboard)
  def status(pid), do: GenServer.call(pid, :status)
  def history(pid), do: GenServer.call(pid, :history)
  def category_stats(pid), do: GenServer.call(pid, :category_stats)
  def team_report(pid, name), do: GenServer.call(pid, {:team_report, name})
  def export_csv(pid), do: GenServer.call(pid, :export_csv)
  def export_answers_csv(pid), do: GenServer.call(pid, :export_answers_csv)
  def question_ids(pid), do: GenServer.call(pid, :question_ids)

  @impl true
  def init({questions, opts}) do
    with {:ok, bank} <- normalize_bank(questions),
         {:ok, max_teams} <- validate_max_teams(opts) do
      {:ok,
       %{
         bank: bank,
         max_teams: max_teams,
         teams: %{},
         used_questions: MapSet.new(),
         current: nil,
         rounds: [],
         events: [],
         next_round: 1
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  def normalize_bank(questions) when is_map(questions) do
    cond do
      map_size(questions) == 0 -> {:error, :empty_bank}
      map_size(questions) > @max_questions -> {:error, :too_many_questions}
      true ->
        Enum.reduce_while(questions, {:ok, %{}}, fn {id, value}, {:ok, acc} ->
          case normalize_question(id, value) do
            {:ok, question} -> {:cont, {:ok, Map.put(acc, id, question)}}
            error -> {:halt, error}
          end
        end)
    end
  end

  def normalize_bank(_), do: {:error, :invalid_bank}

  def normalize_question(id, answer) when is_integer(answer) do
    normalize_question(id, %{correct: answer, points: 10, category: "Geral"})
  end

  def normalize_question(id, question) when is_map(question) do
    correct = Map.get(question, :correct)
    points = Map.get(question, :points, 10)
    category = Map.get(question, :category, "Geral")

    cond do
      not is_integer(id) or id < 1 -> {:error, :invalid_question_id}
      not is_integer(correct) or correct not in 1..4 -> {:error, :invalid_correct_choice}
      not is_integer(points) or points not in 1..100 -> {:error, :invalid_points}
      not is_binary(category) -> {:error, :invalid_category}
      String.trim(category) == "" -> {:error, :invalid_category}
      String.length(category) > @max_category_name -> {:error, :invalid_category}
      true ->
        {:ok, %{correct: correct, points: points, category: String.trim(category)}}
    end
  end

  def normalize_question(_, _), do: {:error, :invalid_question}

  defp validate_max_teams(opts) when is_list(opts) do
    value = Keyword.get(opts, :max_teams, 100)

    if is_integer(value) and value in 1..500 do
      {:ok, value}
    else
      {:error, :invalid_team_limit}
    end
  end

  defp validate_max_teams(_), do: {:error, :invalid_options}

  defp normalize_team(name) when is_binary(name) do
    normalized = String.trim(name)

    cond do
      normalized == "" -> {:error, :invalid_team}
      String.length(normalized) > @max_team_name -> {:error, :invalid_team}
      not String.valid?(normalized) -> {:error, :invalid_team}
      true -> {:ok, normalized}
    end
  end

  defp normalize_team(_), do: {:error, :invalid_team}

  defp event(state, kind, data) do
    entry = %{sequence: length(state.events) + 1, kind: kind, data: data}
    %{state | events: [entry | state.events]}
  end

  defp new_team(name) do
    %{name: name, points: 0, correct: 0, wrong: 0, answered: 0, streak: 0,
      best_streak: 0, rounds: 0, by_category: %{}}
  end

  @impl true
  def handle_call({:register, raw}, _from, state) do
    with {:ok, name} <- normalize_team(raw) do
      cond do
        state.next_round != 1 -> {:reply, {:error, :registration_closed}, state}
        Map.has_key?(state.teams, name) -> {:reply, {:error, :already_registered}, state}
        map_size(state.teams) >= state.max_teams -> {:reply, {:error, :team_limit}, state}
        true ->
          updated = %{state | teams: Map.put(state.teams, name, new_team(name))}
          {:reply, {:ok, name}, event(updated, :team_registered, name)}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:unregister, raw}, _from, state) do
    with {:ok, name} <- normalize_team(raw) do
      cond do
        state.next_round != 1 -> {:reply, {:error, :registration_closed}, state}
        not Map.has_key?(state.teams, name) -> {:reply, {:error, :unknown_team}, state}
        true ->
          updated = %{state | teams: Map.delete(state.teams, name)}
          {:reply, :ok, event(updated, :team_removed, name)}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:add_question, id, question}, _from, state) do
    cond do
      state.next_round != 1 -> {:reply, {:error, :bank_locked}, state}
      Map.has_key?(state.bank, id) -> {:reply, {:error, :duplicate_question}, state}
      map_size(state.bank) >= @max_questions -> {:reply, {:error, :too_many_questions}, state}
      true ->
        case normalize_question(id, question) do
          {:ok, normalized} ->
            updated = %{state | bank: Map.put(state.bank, id, normalized)}
            {:reply, :ok, event(updated, :question_added, id)}
          error -> {:reply, error, state}
        end
    end
  end

  def handle_call({:start_round, ids}, _from, state) do
    cond do
      state.current != nil -> {:reply, {:error, :round_already_open}, state}
      map_size(state.teams) == 0 -> {:reply, {:error, :no_teams}, state}
      not is_list(ids) or ids == [] -> {:reply, {:error, :invalid_round}, state}
      not Enum.all?(ids, &is_integer/1) -> {:reply, {:error, :invalid_round}, state}
      length(ids) != length(Enum.uniq(ids)) -> {:reply, {:error, :duplicate_round_question}, state}
      Enum.any?(ids, &(not Map.has_key?(state.bank, &1))) ->
        {:reply, {:error, :unknown_question}, state}
      Enum.any?(ids, &MapSet.member?(state.used_questions, &1)) ->
        {:reply, {:error, :question_already_used}, state}
      true ->
        round = %{number: state.next_round, ids: ids, answers: %{}, paused: false}
        updated = %{state | current: round,
          used_questions: Enum.reduce(ids, state.used_questions, &MapSet.put(&2, &1))}
        {:reply, {:ok, round.number}, event(updated, :round_started, round.number)}
    end
  end

  def handle_call({:submit, raw, id, choice}, _from, state) do
    with {:ok, name} <- normalize_team(raw) do
      cond do
        state.current == nil -> {:reply, {:error, :no_active_round}, state}
        state.current.paused -> {:reply, {:error, :round_paused}, state}
        not Map.has_key?(state.teams, name) -> {:reply, {:error, :unknown_team}, state}
        not is_integer(id) or id not in state.current.ids ->
          {:reply, {:error, :question_not_in_round}, state}
        not is_integer(choice) or choice not in 1..4 ->
          {:reply, {:error, :invalid_choice}, state}
        Map.has_key?(state.current.answers, {name, id}) ->
          {:reply, {:error, :already_answered}, state}
        true ->
          current = %{state.current | answers:
            Map.put(state.current.answers, {name, id}, choice)}
          updated = %{state | current: current}
          {:reply, {:ok, :recorded}, event(updated, :answer_recorded, {name, id})}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call(:pause, _from, state) do
    cond do
      state.current == nil -> {:reply, {:error, :no_active_round}, state}
      state.current.paused -> {:reply, {:error, :already_paused}, state}
      true ->
        updated = %{state | current: %{state.current | paused: true}}
        {:reply, :ok, event(updated, :round_paused, state.current.number)}
    end
  end

  def handle_call(:resume, _from, state) do
    cond do
      state.current == nil -> {:reply, {:error, :no_active_round}, state}
      not state.current.paused -> {:reply, {:error, :not_paused}, state}
      true ->
        updated = %{state | current: %{state.current | paused: false}}
        {:reply, :ok, event(updated, :round_resumed, state.current.number)}
    end
  end

  def handle_call(:close_round, _from, state) do
    if state.current == nil do
      {:reply, {:error, :no_active_round}, state}
    else
      round = state.current
      {teams, details} = score_round(state.teams, state.bank, round)
      summary = %{number: round.number, questions: round.ids,
        details: details, submissions: map_size(round.answers)}
      updated = %{state | teams: teams, current: nil,
        rounds: [summary | state.rounds], next_round: state.next_round + 1}
      {:reply, {:ok, summary}, event(updated, :round_closed, round.number)}
    end
  end

  defp score_round(teams, bank, round) do
    Enum.reduce(Enum.sort(Map.keys(teams)), {teams, []}, fn name, {acc, details} ->
      original = Map.fetch!(acc, name)
      {team, rows} = Enum.reduce(round.ids, {original, []}, fn id, {team, rows} ->
        question = Map.fetch!(bank, id)

        case Map.fetch(round.answers, {name, id}) do
          :error ->
            {team, [%{team: name, question: id, choice: nil, correct: false,
              points: 0, category: question.category} | rows]}
          {:ok, choice} ->
            correct = choice == question.correct
            streak = if correct, do: team.streak + 1, else: 0
            bonus = if correct, do: min(streak - 1, 3) * 2, else: 0
            earned = if correct, do: question.points + bonus, else: 0
            category = Map.get(team.by_category, question.category,
              %{answered: 0, correct: 0, points: 0})
            category = %{answered: category.answered + 1,
              correct: category.correct + if(correct, do: 1, else: 0),
              points: category.points + earned}
            team = %{team | points: team.points + earned,
              correct: team.correct + if(correct, do: 1, else: 0),
              wrong: team.wrong + if(correct, do: 0, else: 1),
              answered: team.answered + 1, streak: streak,
              best_streak: max(team.best_streak, streak),
              by_category: Map.put(team.by_category, question.category, category)}
            row = %{team: name, question: id, choice: choice,
              correct: correct, points: earned, category: question.category}
            {team, [row | rows]}
        end
      end)
      team = %{team | rounds: team.rounds + 1}
      {Map.put(acc, name, team), details ++ Enum.reverse(rows)}
    end)
  end

  def handle_call(:leaderboard, _from, state) do
    sorted = state.teams |> Map.values()
      |> Enum.sort_by(fn team -> {-team.points, -team.correct, team.name} end)
    {_, ranked} = Enum.reduce(sorted, {0, []}, fn team, {position, rows} ->
      rank = position + 1
      {rank, [%{rank: rank, name: team.name, points: team.points,
        correct: team.correct, answered: team.answered,
        best_streak: team.best_streak} | rows]}
    end)
    {:reply, Enum.reverse(ranked), state}
  end

  def handle_call(:status, _from, state) do
    status = %{teams: map_size(state.teams), questions: map_size(state.bank),
      used_questions: MapSet.size(state.used_questions),
      completed_rounds: length(state.rounds),
      active_round: if(state.current, do: state.current.number, else: nil),
      paused: if(state.current, do: state.current.paused, else: false),
      submissions: if(state.current, do: map_size(state.current.answers), else: 0)}
    {:reply, status, state}
  end

  def handle_call(:history, _from, state) do
    {:reply, Enum.reverse(state.rounds), state}
  end

  def handle_call(:question_ids, _from, state) do
    {:reply, state.bank |> Map.keys() |> Enum.sort(), state}
  end

  def handle_call({:team_report, raw}, _from, state) do
    with {:ok, name} <- normalize_team(raw) do
      case Map.fetch(state.teams, name) do
        {:ok, team} -> {:reply, {:ok, team}, state}
        :error -> {:reply, {:error, :unknown_team}, state}
      end
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call(:category_stats, _from, state) do
    result = Enum.reduce(state.teams, %{}, fn {_name, team}, categories ->
      Enum.reduce(team.by_category, categories, fn {category, row}, acc ->
        previous = Map.get(acc, category, %{answered: 0, correct: 0, points: 0})
        Map.put(acc, category, %{answered: previous.answered + row.answered,
          correct: previous.correct + row.correct,
          points: previous.points + row.points})
      end)
    end)
    {:reply, result, state}
  end

  def handle_call(:export_csv, _from, state) do
    sorted = state.teams |> Map.values()
      |> Enum.sort_by(fn team -> {-team.points, -team.correct, team.name} end)
    rows = Enum.map(sorted, fn team ->
      [team.name, team.points, team.correct, team.wrong,
       team.answered, team.best_streak, team.rounds]
    end)
    {:reply, csv(["team", "points", "correct", "wrong", "answered",
      "best_streak", "rounds"], rows), state}
  end

  def handle_call(:export_answers_csv, _from, state) do
    rows = state.rounds |> Enum.reverse() |> Enum.flat_map(fn round ->
      Enum.map(round.details, fn row ->
        [round.number, row.team, row.question, row.choice,
         row.correct, row.points, row.category]
      end)
    end)
    {:reply, csv(["round", "team", "question", "choice", "correct",
      "points", "category"], rows), state}
  end

  defp csv(header, rows) do
    ([header | rows]
     |> Enum.map(fn fields -> Enum.map_join(fields, ",", &escape_csv/1) end)
     |> Enum.join("\n")) <> "\n"
  end

  defp escape_csv(nil), do: ""
  defp escape_csv(value) do
    text = to_string(value)
    # Spreadsheet formula injection is blocked even for quoted CSV fields.
    safe = if String.starts_with?(String.trim_leading(text), ["=", "+", "-", "@"]),
      do: "'" <> text, else: text
    if String.contains?(safe, [",", "\"", "\r", "\n"]) do
      "\"" <> String.replace(safe, "\"", "\"\"") <> "\""
    else
      safe
    end
  end
end
