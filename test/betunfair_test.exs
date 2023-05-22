defmodule BetUnfairTest do
  use ExUnit.Case
  #doctest BetUnfair
  @moduledoc """
  The tests here are only meant for logical and
  robustness purpose.
  Tests for the scalability of the programs are
  not present in this file.
  """

  test "EXCHANGES INTERACTIONS" do
    assert elem(BetUnfair.start_link("test_stop"),0) == :ok
    assert BetUnfair.stop() == :ok
    assert elem(BetUnfair.start_link("test_clean"),0) == :ok
    assert BetUnfair.clean("test_clean") == :ok
  end

  test "USER INTERACTION" do
    BetUnfair.start_link("test_users")
    assert BetUnfair.user_create("Alice", "Alice99") == {:ok, "Alice"}
    assert BetUnfair.user_create("Alice", "Alice01") == {:error, "Alice"}
    assert BetUnfair.user_get("Alice") == {:ok, {"Alice99", "Alice", 0, []}}
    assert BetUnfair.user_get("Bob") == {:error}
    assert BetUnfair.user_deposit("Alice", -10) == :error
    assert BetUnfair.user_deposit("Alice", 10) == :ok
    assert BetUnfair.user_create("Bob", "B0B") == {:ok, "Bob"}
    assert BetUnfair.user_get("Bob") ==  {:ok, {"B0B", "Bob", 0, []}}
    assert BetUnfair.user_withdraw("Alice", 5) == :ok
    assert BetUnfair.user_withdraw("Bob", 2) == :error
    assert BetUnfair.user_get("Bob") == {:ok, {"B0B", "Bob", 0, []}}
    assert BetUnfair.user_get("Alice") == {:ok, {"Alice99", "Alice", 5, []}}
    assert BetUnfair.user_bets("Alice") == []
    BetUnfair.clean("test_users")
  end
end
