defmodule BetUnfairTest do
  use ExUnit.Case
  # #doctest BetUnfair
  # @moduledoc """
  # The tests here are firstly meant for logical and
  # robustness purpose.
  # Tests for the scalability of the programs are
  # at the end of this file.
  # """

  test "EXCHANGES INTERACTIONS" do
    assert is_ok(elem(BetUnfair.start_link("test_stop"),0))
    assert is_ok(BetUnfair.stop())
    assert is_ok(elem(BetUnfair.start_link("test_clean"),0))
    assert is_ok(BetUnfair.clean("test_clean"))
  end

  test "user_create_deposit_get" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert is_error(BetUnfair.user_create("u1","Francisco Gonzalez"))
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_error(BetUnfair.user_deposit(u1,-1))
    assert is_error(BetUnfair.user_deposit(u1,0))
    assert is_error(BetUnfair.user_deposit("u11",0))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
  end

  test "user_bet1" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,b} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,%{bet_type: :back, remaining_stake: 1000, odds: 150, status: :active}} = BetUnfair.bet_get(b)
    assert {:ok,markets} = BetUnfair.market_list()
    assert 1 = length(markets)
    assert {:ok,markets} = BetUnfair.market_list_active()
    assert 1 = length(markets)
  end

  test "user_persist" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,b} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,%{bet_type: :back, remaining_stake: 1000, odds: 150, status: :active}} = BetUnfair.bet_get(b)
    assert is_ok(BetUnfair.stop())
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,%{balance: 1000}} = BetUnfair.user_get(u1)
    assert {:ok,markets} = BetUnfair.market_list()
    assert 1 = length(markets)
    assert {:ok,markets} = BetUnfair.market_list_active()
    assert 1 = length(markets)
  end

  test "match_bets1" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,bl1} = BetUnfair.bet_lay(u2,m1,500,140)
    assert {:ok,bl2} = BetUnfair.bet_lay(u2,m1,500,150)
    assert {:ok,%{balance: 1000}} = BetUnfair.user_get(u2)
    assert {:ok, backs} = BetUnfair.market_pending_backs(m1)
    assert [^bb1,^bb2] = Enum.to_list(backs) |> Enum.map(fn (e) -> elem(e,1) end)
    assert {:ok,lays} = BetUnfair.market_pending_lays(m1)
    assert [^bl2,^bl1] = Enum.to_list(lays) |> Enum.map(fn (e) -> elem(e,1) end)
    assert is_ok(BetUnfair.market_match(m1))
    assert {:ok,%{remaining_stake: 0}} = BetUnfair.bet_get(bb1)
    assert {:ok,%{remaining_stake: 0}} = BetUnfair.bet_get(bl2)
  end

  test "match_bets2" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,1000,140)
    assert {:ok,bl2} = BetUnfair.bet_lay(u2,m1,1000,150)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert {:ok,%{remaining_stake: 0}} = BetUnfair.bet_get(bb1)
    assert {:ok,%{remaining_stake: 500}} = BetUnfair.bet_get(bl2)
  end

  test "match_bets3" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert {:ok,%{remaining_stake: 800}} = BetUnfair.bet_get(bb1)
    assert {:ok,%{remaining_stake: 0}} = BetUnfair.bet_get(bl2)
    assert {:ok,user_bets} = BetUnfair.user_bets(u1)
    assert 2 = length(user_bets)
  end

  test "match_bets4" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_cancel(m1))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u2)
  end

  test "match_bets5" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_settle(m1,true))
    assert {:ok,%{balance: 2100}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 1900}} = BetUnfair.user_get(u2)
  end

  test "match_bets6" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_settle(m1,false))
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 2200}} = BetUnfair.user_get(u2)
  end

  test "match_bets7" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_freeze(m1))
    assert is_error(BetUnfair.bet_lay(u2,m1,100,150))
    assert is_ok(BetUnfair.market_settle(m1,false))
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 2200}} = BetUnfair.user_get(u2)
  end

  test "match_bets8" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,200,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,200,153)
    assert {:ok,%{balance: 1600}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_settle(m1,true))
    assert {:ok,%{balance: 2100}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 1900}} = BetUnfair.user_get(u2)
  end

  test "match_bets9" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,200,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,200,153)
    assert {:ok,%{balance: 1600}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_settle(m1,false))
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 2200}} = BetUnfair.user_get(u2)
  end

  test "match_bets10" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,800,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,800,153)
    assert {:ok,%{balance: 400}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_settle(m1,true))
    assert {:ok,%{balance: 2200}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
  end

  test "match_bets11" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,200,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,200,150)
    assert {:ok,%{balance: 1600}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,_bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,_bl2} = BetUnfair.bet_lay(u2,m1,800,150)
    assert {:ok,%{balance: 1100}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.market_settle(m1,false))
    assert {:ok,%{balance: 1600}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 2400}} = BetUnfair.user_get(u2)
  end

  test "bet_cancel1" do
    assert :ok = BetUnfair.clean("testdb")
    assert {:ok,_} = BetUnfair.start_link("testdb")
    assert {:ok,u1} = BetUnfair.user_create("u1","Francisco Gonzalez")
    assert {:ok,u2} = BetUnfair.user_create("u2","Maria Fernandez")
    assert is_ok(BetUnfair.user_deposit(u1,2000))
    assert is_ok(BetUnfair.user_deposit(u2,2000))
    assert {:ok,%{balance: 2000}} = BetUnfair.user_get(u1)
    assert {:ok,m1} = BetUnfair.market_create("rmw","Real Madrid wins")
    assert {:ok,bb1} = BetUnfair.bet_back(u1,m1,1000,150)
    assert {:ok,bb2} = BetUnfair.bet_back(u1,m1,1000,153)
    assert {:ok,%{balance: 0}} = BetUnfair.user_get(u1)
    assert true = (bb1 != bb2)
    assert {:ok,bl1} = BetUnfair.bet_lay(u2,m1,100,140)
    assert {:ok,bl2} = BetUnfair.bet_lay(u2,m1,100,150)
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_match(m1))
    assert is_ok(BetUnfair.bet_cancel(bl1))
    assert is_ok(BetUnfair.bet_cancel(bb2))
    assert {:ok,%{balance: 1000}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 1900}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.bet_cancel(bl2))
    assert is_ok(BetUnfair.bet_cancel(bb1))
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 1900}} = BetUnfair.user_get(u2)
    assert is_ok(BetUnfair.market_settle(m1,false))
    assert {:ok,%{balance: 1800}} = BetUnfair.user_get(u1)
    assert {:ok,%{balance: 2200}} = BetUnfair.user_get(u2)
  end

  defp is_error(:error),do: true
  defp is_error({:error,_}), do: true
  defp is_error(_), do: false

  defp is_ok(:ok), do: true
  defp is_ok({:ok,_}), do: true
  defp is_ok(_), do: false

  ## The tests here are only meant for scalabilitypurpose.  ##
  ## Tests for the logical purpose of the programs are      ##
  ## not present in this file.                              ##

  def spawn_n_users(0) do
  end
  def spawn_n_users(n) do
    BetUnfair.user_create(Integer.to_string(n), Integer.to_string(n*10+n))
    spawn_n_users(n-1)
  end

  def spawn_n_deposits(0) do
  end
  def spawn_n_deposits(n) do
    BetUnfair.user_deposit(Integer.to_string(n), Enum.random(100..3000))
    spawn_n_deposits(n-1)
  end

  def users_bets(0, _) do
  end
  def users_bets(n, nb_markets) do
    type_bet = Enum.random([:back, :lay])
    market_chose = Integer.to_string(Enum.random(1..nb_markets))
    u = Integer.to_string(n)
    stake = Enum.random(1..300)
    if type_bet == :back do
      odds = Enum.random(100..200)
      BetUnfair.bet_back(u,market_chose,stake,odds)
    else
      odds = Enum.random(180..280)
      BetUnfair.bet_back(u,market_chose,stake,odds)
    end
    users_bets(n-1, nb_markets)
  end

  def create_markets(0) do
  end
  def create_markets(m) do
    BetUnfair.market_create(Integer.to_string(m), Integer.to_string(m*10+m))
    create_markets(m-1)
  end

  def match_markets(0) do
  end
  def match_markets(m) do
    BetUnfair.market_match(Integer.to_string(m))
    match_markets(m-1)
  end

  def settle_markets(0) do
  end
  def settle_markets(m)do
    BetUnfair.market_settle(Integer.to_string(m), Enum.random([true, false]))
    settle_markets(m-1)
  end

  test "benchmark_test1" do
    n = 50 # n should be >= 50
    m = Kernel.trunc(n/50)
    assert {:ok,_} = BetUnfair.start_link("testdb")
    spawn_n_users(n)
    spawn_n_deposits(n)
    create_markets(m)
    users_bets(n,m)
    match_markets(m)
  end
end
# 100000 -> 18
# 10000 ->  0.7
# 1000 ->   0.3
