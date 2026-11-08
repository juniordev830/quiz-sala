Code.require_file("tournament.exs", __DIR__)
ExUnit.start()

defmodule QuizTournamentTest do
  use ExUnit.Case, async: true

  defp room(bank \\ %{1 => 2, 2 => 1, 3 => 4, 4 => 3}, opts \\ []) do
    {:ok, pid} = QuizTournament.start_link(bank, opts)
    pid
  end

  defp register(pid, names) do
    Enum.each(names, fn name -> assert {:ok, _} = QuizTournament.register(pid, name) end)
    pid
  end

  defp play(pid, ids) do
    assert {:ok, _} = QuizTournament.start_round(pid, ids)
    pid
  end

  describe "question bank validation" do
    test "requires a nonempty question map" do
      assert {:error, :empty_bank} = QuizTournament.normalize_bank(%{})
      assert {:error, :invalid_bank} = QuizTournament.normalize_bank([])
    end

    test "rejects question ids that are not positive integers" do
      assert {:error, :invalid_question_id} = QuizTournament.normalize_bank(%{0 => 2})
      assert {:error, :invalid_question_id} = QuizTournament.normalize_bank(%{"1" => 2})
      assert {:error, :invalid_question_id} = QuizTournament.normalize_bank(%{-5 => 2})
    end

    test "validates the four possible answers" do
      for choice <- [0, 5, -1, 2.5, nil, "1"] do
        assert {:error, :invalid_correct_choice} =
          QuizTournament.normalize_bank(%{1 => choice})
      end
    end

    test "validates points and categories" do
      for points <- [0, 101, -10, 1.5, nil] do
        assert {:error, :invalid_points} =
          QuizTournament.normalize_bank(%{1 => %{correct: 1, points: points}})
      end
      assert {:error, :invalid_category} =
        QuizTournament.normalize_bank(%{1 => %{correct: 1, category: " "}})
      assert {:error, :invalid_category} =
        QuizTournament.normalize_bank(%{1 => %{correct: 1, category: 12}})
    end

    test "normalizes defaults and trims categories" do
      assert {:ok, bank} = QuizTournament.normalize_bank(%{
        1 => 2, 2 => %{correct: 3, points: 20, category: " História "}
      })
      assert bank[1] == %{correct: 2, points: 10, category: "Geral"}
      assert bank[2] == %{correct: 3, points: 20, category: "História"}
    end

    test "enforces a finite question limit" do
      too_many = Map.new(1..501, &{&1, 1})
      assert {:error, :too_many_questions} = QuizTournament.normalize_bank(too_many)
    end

    test "enforces a finite team limit" do
      assert {:error, :invalid_team_limit} =
        QuizTournament.start_link(%{1 => 2}, max_teams: 0)
      assert {:error, :invalid_team_limit} =
        QuizTournament.start_link(%{1 => 2}, max_teams: 501)
      assert {:error, :invalid_team_limit} =
        QuizTournament.start_link(%{1 => 2}, max_teams: "100")
    end
  end

  describe "registration" do
    test "registers normalized names" do
      pid = room()
      assert {:ok, "Azul"} = QuizTournament.register(pid, " Azul ")
      assert {:error, :already_registered} = QuizTournament.register(pid, "Azul")
      assert QuizTournament.status(pid).teams == 1
    end

    test "rejects blank, oversized and nonstring names" do
      pid = room()
      for name <- ["", "  ", String.duplicate("a", 81), nil, 22] do
        assert {:error, :invalid_team} = QuizTournament.register(pid, name)
      end
      assert QuizTournament.status(pid).teams == 0
    end

    test "honors configured team capacity" do
      pid = room(%{1 => 2}, max_teams: 2)
      assert {:ok, "A"} = QuizTournament.register(pid, "A")
      assert {:ok, "B"} = QuizTournament.register(pid, "B")
      assert {:error, :team_limit} = QuizTournament.register(pid, "C")
    end

    test "unregisters only known teams before a round" do
      pid = room() |> register(["A"])
      assert {:error, :unknown_team} = QuizTournament.unregister(pid, "B")
      assert :ok = QuizTournament.unregister(pid, "A")
      assert QuizTournament.status(pid).teams == 0
    end

    test "locks team membership once a round begins" do
      pid = room() |> register(["A"]) |> play([1])
      assert {:error, :registration_closed} = QuizTournament.register(pid, "B")
      assert {:error, :registration_closed} = QuizTournament.unregister(pid, "A")
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert {:error, :registration_closed} = QuizTournament.register(pid, "B")
    end
  end

  describe "round management" do
    test "cannot start without registered teams" do
      assert {:error, :no_teams} = QuizTournament.start_round(room(), [1])
    end

    test "rejects empty and malformed rounds" do
      pid = room() |> register(["A"])
      for ids <- [[], nil, 1, ["1"], [1, "2"]] do
        assert {:error, :invalid_round} = QuizTournament.start_round(pid, ids)
      end
    end

    test "rejects duplicates and unknown questions" do
      pid = room() |> register(["A"])
      assert {:error, :duplicate_round_question} =
        QuizTournament.start_round(pid, [1, 1])
      assert {:error, :unknown_question} =
        QuizTournament.start_round(pid, [1, 99])
    end

    test "cannot overlap rounds or reuse questions" do
      pid = room() |> register(["A"])
      assert {:ok, 1} = QuizTournament.start_round(pid, [1])
      assert {:error, :round_already_open} = QuizTournament.start_round(pid, [2])
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert {:error, :question_already_used} = QuizTournament.start_round(pid, [1])
      assert {:ok, 2} = QuizTournament.start_round(pid, [2])
    end

    test "tracks active and completed rounds" do
      pid = room() |> register(["A"])
      assert QuizTournament.status(pid).active_round == nil
      assert {:ok, 1} = QuizTournament.start_round(pid, [1, 2])
      assert QuizTournament.status(pid).active_round == 1
      assert QuizTournament.status(pid).used_questions == 2
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert QuizTournament.status(pid).completed_rounds == 1
      assert QuizTournament.status(pid).active_round == nil
    end

    test "supports pause and resume with explicit errors" do
      pid = room() |> register(["A"])
      assert {:error, :no_active_round} = QuizTournament.pause(pid)
      assert {:error, :no_active_round} = QuizTournament.resume(pid)
      play(pid, [1])
      assert {:error, :not_paused} = QuizTournament.resume(pid)
      assert :ok = QuizTournament.pause(pid)
      assert QuizTournament.status(pid).paused
      assert {:error, :already_paused} = QuizTournament.pause(pid)
      assert {:error, :round_paused} = QuizTournament.submit(pid, "A", 1, 2)
      assert :ok = QuizTournament.resume(pid)
      refute QuizTournament.status(pid).paused
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
    end

    test "closes a paused round without losing submitted answers" do
      pid = room() |> register(["A"]) |> play([1])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert :ok = QuizTournament.pause(pid)
      assert {:ok, summary} = QuizTournament.close_round(pid)
      assert summary.submissions == 1
      assert QuizTournament.status(pid).paused == false
    end

    test "can add questions before play and locks bank afterward" do
      pid = room()
      assert :ok = QuizTournament.add_question(pid, 8,
        %{correct: 4, points: 25, category: "Música"})
      assert 8 in QuizTournament.question_ids(pid)
      assert {:error, :duplicate_question} = QuizTournament.add_question(pid, 8, 4)
      assert {:error, :invalid_points} =
        QuizTournament.add_question(pid, 9, %{correct: 2, points: -1})
      register(pid, ["A"])
      play(pid, [8])
      assert {:error, :bank_locked} = QuizTournament.add_question(pid, 9, 1)
    end
  end

  describe "answer submission" do
    test "does not accept submissions outside rounds" do
      pid = room() |> register(["A"])
      assert {:error, :no_active_round} = QuizTournament.submit(pid, "A", 1, 2)
    end

    test "checks team, question and choice" do
      pid = room() |> register(["A"]) |> play([1])
      assert {:error, :unknown_team} = QuizTournament.submit(pid, "B", 1, 2)
      assert {:error, :question_not_in_round} = QuizTournament.submit(pid, "A", 2, 1)
      for choice <- [0, 5, "2", nil] do
        assert {:error, :invalid_choice} = QuizTournament.submit(pid, "A", 1, choice)
      end
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
    end

    test "one submission per team and question" do
      pid = room() |> register(["A", "B"]) |> play([1, 2])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert {:error, :already_answered} = QuizTournament.submit(pid, "A", 1, 1)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "B", 1, 2)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 2, 1)
      assert QuizTournament.status(pid).submissions == 3
    end

    test "answers are not scored before round closure" do
      pid = room() |> register(["A"]) |> play([1])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert hd(QuizTournament.leaderboard(pid)).points == 0
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert hd(QuizTournament.leaderboard(pid)).points == 10
    end

    test "unanswered questions do not count as wrong answers" do
      pid = room() |> register(["A"]) |> play([1, 2])
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert {:ok, team} = QuizTournament.team_report(pid, "A")
      assert team.answered == 0
      assert team.wrong == 0
      assert team.rounds == 1
    end
  end

  describe "scoring and analytics" do
    test "awards base points and bounded streak bonuses" do
      pid = room(%{1 => 1, 2 => 1, 3 => 1, 4 => 1, 5 => 1})
      register(pid, ["A"])
      play(pid, [1, 2, 3, 4, 5])
      for id <- 1..5 do
        assert {:ok, :recorded} = QuizTournament.submit(pid, "A", id, 1)
      end
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert {:ok, team} = QuizTournament.team_report(pid, "A")
      assert team.points == 68
      assert team.correct == 5
      assert team.best_streak == 5
    end

    test "wrong answers break streaks" do
      pid = room(%{1 => 1, 2 => 1, 3 => 1}) |> register(["A"]) |> play([1, 2, 3])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 1)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 2, 2)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 3, 1)
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert {:ok, team} = QuizTournament.team_report(pid, "A")
      assert team.points == 20
      assert team.wrong == 1
      assert team.streak == 1
    end

    test "custom points and categories are reflected in reports" do
      bank = %{1 => %{correct: 2, points: 30, category: "História"},
        2 => %{correct: 4, points: 15, category: "Geografia"}}
      pid = room(bank) |> register(["A"]) |> play([1, 2])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 2, 4)
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert {:ok, team} = QuizTournament.team_report(pid, "A")
      assert team.points == 47
      assert team.by_category["História"].points == 30
      assert team.by_category["Geografia"].points == 17
      assert QuizTournament.category_stats(pid)["Geografia"].correct == 1
    end

    test "orders leaderboard by points, correct answers and name" do
      pid = room() |> register(["Z", "B", "A"]) |> play([1, 2])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "B", 1, 2)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "Z", 1, 1)
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert Enum.map(QuizTournament.leaderboard(pid), & &1.name) == ["A", "B", "Z"]
      assert Enum.map(QuizTournament.leaderboard(pid), & &1.rank) == [1, 2, 3]
    end

    test "category totals include all teams" do
      bank = %{1 => %{correct: 2, category: "Matemática"}}
      pid = room(bank) |> register(["A", "B"]) |> play([1])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert {:ok, :recorded} = QuizTournament.submit(pid, "B", 1, 1)
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert QuizTournament.category_stats(pid)["Matemática"] ==
        %{answered: 2, correct: 1, points: 10}
    end

    test "history retains closed round order and answer details" do
      pid = room() |> register(["A"])
      play(pid, [1])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert {:ok, first} = QuizTournament.close_round(pid)
      play(pid, [2])
      assert {:ok, second} = QuizTournament.close_round(pid)
      assert Enum.map(QuizTournament.history(pid), & &1.number) == [1, 2]
      assert first.submissions == 1
      assert second.submissions == 0
      assert hd(first.details).correct == true
      assert hd(second.details).choice == nil
    end

    test "unknown team reports return an error" do
      pid = room()
      assert {:error, :unknown_team} = QuizTournament.team_report(pid, "Missing")
      assert {:error, :invalid_team} = QuizTournament.team_report(pid, "")
    end
  end

  describe "CSV exports" do
    test "exports a stable header even without registered teams" do
      pid = room()
      assert QuizTournament.export_csv(pid) ==
        "team,points,correct,wrong,answered,best_streak,rounds\n"
      assert QuizTournament.export_answers_csv(pid) ==
        "round,team,question,choice,correct,points,category\n"
    end

    test "escapes commas and double quotes" do
      pid = room() |> register(["A,\"B\""]) |> play([1])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A,\"B\"", 1, 2)
      assert {:ok, _} = QuizTournament.close_round(pid)
      csv = QuizTournament.export_csv(pid)
      assert String.contains?(csv, "\"A,\"\"B\"\"\"")
      assert String.contains?(QuizTournament.export_answers_csv(pid), "\"A,\"\"B\"\"\"")
    end

    test "neutralizes spreadsheet formulas in names" do
      pid = room() |> register(["=1+1", "@SUM(A1)", "+SUM(A1)"])
      csv = QuizTournament.export_csv(pid)
      assert String.contains?(csv, "'=1+1")
      assert String.contains?(csv, "'@SUM(A1)")
      assert String.contains?(csv, "'+SUM(A1)")
    end

    test "exports each answer and omits hidden correct choice" do
      pid = room() |> register(["A"]) |> play([1])
      assert {:ok, :recorded} = QuizTournament.submit(pid, "A", 1, 2)
      assert {:ok, _} = QuizTournament.close_round(pid)
      lines = String.split(QuizTournament.export_answers_csv(pid), "\n", trim: true)
      assert length(lines) == 2
      assert Enum.at(lines, 1) == "1,A,1,2,true,10,Geral"
    end
  end

  describe "concurrent and independent rooms" do
    test "different rooms do not share state" do
      one = room() |> register(["A"]) |> play([1])
      two = room() |> register(["B"]) |> play([2])
      assert {:ok, :recorded} = QuizTournament.submit(one, "A", 1, 2)
      assert QuizTournament.status(two).submissions == 0
      assert {:ok, _} = QuizTournament.close_round(one)
      assert QuizTournament.status(two).completed_rounds == 0
    end

    test "concurrent submissions are serialized" do
      pid = room() |> register(["A"]) |> play([1])
      responses = 1..12 |> Task.async_stream(fn _ ->
        QuizTournament.submit(pid, "A", 1, 2)
      end, max_concurrency: 12) |> Enum.map(fn {:ok, value} -> value end)
      assert Enum.count(responses, &(&1 == {:ok, :recorded})) == 1
      assert Enum.count(responses, &(&1 == {:error, :already_answered})) == 11
      assert QuizTournament.status(pid).submissions == 1
    end

    test "round close is safe against repeated calls" do
      pid = room() |> register(["A"]) |> play([1])
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert {:error, :no_active_round} = QuizTournament.close_round(pid)
      assert QuizTournament.status(pid).completed_rounds == 1
    end

    test "large valid room remains within configured bounds" do
      pid = room(Map.new(1..50, &{&1, rem(&1, 4) + 1}), max_teams: 20)
      Enum.each(1..20, fn n ->
        assert {:ok, _} = QuizTournament.register(pid, "Equipe #{n}")
      end)
      assert {:error, :team_limit} = QuizTournament.register(pid, "Extra")
      assert {:ok, 1} = QuizTournament.start_round(pid, Enum.to_list(1..50))
      assert {:ok, _} = QuizTournament.close_round(pid)
      assert QuizTournament.status(pid).completed_rounds == 1
      assert length(QuizTournament.leaderboard(pid)) == 20
    end
  end
end
