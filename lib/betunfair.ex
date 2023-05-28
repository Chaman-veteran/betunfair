defmodule BetUnfair do
  @moduledoc """
  Documentation for `BetUnfair`.
  """
  use GenServer
  ## Variations in the API were made iff we added the error  ##
  ## support for higher robustness                           ##

  # GenServer is used for markets :
  # each market runs with a unique pid & server
  # in order to increase scalability of market places
  # The users are linked to the whole system and as such
  # are "stored" using the main module along with the Process module

  @type user_id :: String.t()
  @type bet_id :: %{user: user_id(), market: market_id()}
  @type users :: %{user_id() => %{user: String.t(), balance: integer(), bets: [bet_id()]}}
  # A market is defined by the participants to a bet
  @type market_id :: pid()
  @type market :: %{ name: String.t(),
                     description: String.t(),
                     status: :active |
                             :frozen |
                             :cancelled |
                             {:settled, result::bool()}}
  @type bet :: %{ bet_type: :back | :lay,
                  market_id: market_id(),
                  user_id: user_id(),
                  odds: integer(),
                  original_stake: integer(), # original stake
                  remaining_stake: integer(), # non-matched stake
                  matched_bets: [bet_id()], # list of matched bets
                  status: :active |
                          :cancelled |
                          :market_cancelled |
                          {:market_settled, boolean()}}
  @type market_place :: %{market: market, backs: [bet_id()], lays: [bet_id()]}

  ################################
  #### EXCHANGES INTERACTIONS ####
  ################################

  @doc """
  Start of the exchange place.
  If an exchange name does not already exist it is created.
  If it exists the existing data (markets, bets) is recovered.

  ## Parameters
    - name, which is the name of the market created

  ## Examples

      iex> Betunfair.start_link("Madrid-Barca")
      {:ok, %{}}

  """
  @spec start_link(name :: String.t()) :: {:ok, market_place()}
  def start_link(name) do
    if Process.get(name) == :nil do
      market_create(name, :nil)
    else
      # TODO : recover the existing data of the market that was stopped
    end
  end

  @doc """
  Stops the running exchange place.
  shuts down a running exchange in an orderly
  fashion (preserving exchange data).

  ## Examples

      iex> Betunfair.stop()
      :ok

  """
  @spec stop() :: :ok
  def stop() do
    ## TODO : preserving exchange data ##
    GenServer.stop(Process.get(:market_server))
    :ok
  end

  @doc """
  Terminates cleanly the running exchange place given.

  ## Parameters
    - market, the initial state of the market

  ## Examples

      iex> Betunfair.clean("Madrid-Barca")
      :ok

  """
  @spec clean(name :: String.t()):: :ok
  def clean(name) do
    {market_id, _} = Process.get(name)
    market_cancel(market_id)
    GenServer.stop(market_id)
    Process.delete(name)
    :ok
  end

  ##########################
  #### USER INTERACTION ####
  ##########################

  @doc """
  Adds a user to the exchange.
  The id parameter must be unique
  (e.g., a DNI/passport number, email, username).
  Fails, for instance, if a user with the same id already exists.
  Returns a user identifier (you may choose its representation)

  ## Parameters
    - id, the string that identifies the user
    - name, the name of the

  ## Examples

      iex> Betunfair.create_user("Alice","Alice99")
      {:ok, "Alice"}
      iex> Betunfair.create_user("Alice","Alice01")
      {:error, "Alice"}

  """
  @spec user_create(id :: String.t(), name :: String.t()) :: {:ok | :error, user_id()}
  def user_create(id, name) do
    users = Process.get(:users, %{})
    if Map.has_key?(users,id) do
      # The user already exists
      {:error, id}
    else
      updated_users = Map.put(users, id, %{name: name, balance: 0, bets: []})
      Process.put(:users, updated_users)
      {:ok, id}
    end
  end

  @doc """
  Adds amount (should be positive) to the user account.

  ## Parameters
    - id, the string that identifies the user
    - amount, the amount to deposit

  ## Examples

      iex> Betunfair.user_deposit("Alice",15)
      :ok
      iex> Betunfair.create_user("Alice",-1)
      :error

  """
  @spec user_deposit(id :: user_id(), amount :: integer()):: :ok | :error
  def user_deposit(id, amount) do
    users = Process.get(:users)
    if Map.has_key?(users, id) and amount >= 0 do
      {:ok, user} = Map.fetch(users, id)
      new_amount = user[:balance] +amount
      updated_users = Map.replace(users, id, %{name: user[:name], balance: new_amount, bets: user[:bets]})
      Process.put(:users, updated_users)
      :ok
    else
      # The user do not exist
      :error
    end
  end

  @doc """
  Withdraw amount to the user account.
  The amount should be positive,
  and the account balance must be at least amount.

  ## Parameters
    - id, the string that identifies the user
    - amount, the amount to withdraw

  ## Examples

      iex> Betunfair.user_deposit("Alice",15)
      :ok
      iex> Betunfair.create_user("Alice",-1)
      :error
      iex> Betunfair.create_user("Alice",20)
      :ok

  """
  @spec user_withdraw(id :: user_id(), amount :: integer()):: :ok | :error
  def user_withdraw(id, amount) do
    users = Process.get(:users)
    if Map.has_key?(users, id) do
      {:ok, user} = Map.fetch(users, id)
      if amount > user[:balance] do
        :error
      else
        new_amount = user[:balance]-amount
        updated_users = Map.replace(users, id, %{name: user[:name], balance: new_amount, bets: user[:bets]})
        Process.put(:users, updated_users)
        :ok
      end
    else
      # The user do not exist
      :error
    end
  end

  @doc """
  Retrieves information about a user.

  ## Parameters
    - id, the string that identifies the user

  ## Examples

      iex> Betunfair.user_get("Alice", 15)
      {:ok, %{"Alice", "Alice01", 15}}

  """
  @spec user_get(id :: user_id()) ::
          {:ok, %{name: String.t(), id: user_id(), balance: integer()}} | {:error}
  def user_get(id) do
    users = Process.get(:users)
    if Map.has_key?(users,id) do
      {:ok, user} = Map.fetch(users, id)
      {:ok, %{name: user[:name], id: id, balance: user[:balance]}}
    else
      {:error}
    end
  end

  @doc """
  Returns an enumerable containing all bets of the user.

  ## Parameters
    - id, the string that identifies the user

  ## Examples

      iex> Betunfair.user_get("Alice",15)
      ["Madrid wins over Barca", "Paris wins over Marseille"]

  """
  @spec user_bets(id :: user_id()) :: Enumerable.t(bet_id())
  def user_bets(id) do
    users = Process.get(:users)
    if Map.has_key?(users, id) do
      {:ok, user} = Map.fetch(users, id)
      user[:bets]
    else
      []
    end
  end

  ############################
  #### MARKET INTERACTION ####
  ############################

  defp filter([],_) do
    []
  end
  defp filter([head | tail], p) do
    if p.(head) do
      [head | filter(tail, p)]
    else
      filter(tail,p)
    end
  end

  @doc """
  Creates a market with the unique name,
  and a potentially longer description.
  All market created are on by default.

  ## Parameters
    - name, the name of the market
    - description, a description of it

  ## Examples

      iex> Betunfair.market_create("Madrid-Barca", "Market place for Madrid-Barca bets result")
      {:ok, #PID<_>}

  """
  @spec market_create(name :: String.t(), description :: String.t()) :: {:ok, market_id()}
  def market_create(name, description) do
    {:ok, market_pid} = GenServer.start_link(BetUnfair, {name, description})
    Process.put(:market_server, market_pid)
    # process : %{market_id => {market_pid, on?}}
    Process.put(name, {market_pid, :on})
    {:ok, market_pid}
  end

  @doc """
  GenServer function associated to market_create.
  Initialize the GenServer state.
  """
  @spec init({name :: String.t(), description :: String.t()}) :: {:ok, market_place()}
  def init({name, description}) do
    market_info = %{name: name, description: description, status: :active}
    {:ok, %{market: market_info, backs: [], lays: []}}
  end

  @doc """
  Returns all markets.

  ## Examples

      iex> Betunfair.market_list()
      {:ok, [#PID<_>]}

  """
  @spec market_list() :: {:ok, [market_id()]}
  def market_list() do
    valide_market = &(&1 != :users &&  &1 != :market_server)
    list_markets = filter(Process.get_keys(), valide_market)
    {:ok, list_markets}
  end

  @doc """
  Returns all active markets.

  ## Examples

      iex> Betunfair.market_list_active()
      {:ok, [#PID<_>]}

  """
  @spec market_list_active() :: {:ok, [market_id()]}
  def market_list_active() do
    list_markets = Process.get()
    valide_market = &(elem(&1,1) == :on)
    list_active_markets = filter(list_markets, valide_market)
    {:ok, list_active_markets}
  end

  @doc """
  Cancels a non-terminated market.
  Returns all stakes in matched or unmatched market bets to users.

  ## Examples

      iex> Betunfair.market_cancel(#PID<_>)
      :ok

  """
  @spec market_cancel(id :: market_id()):: :ok
  def market_cancel(id) do
    market = Process.get(id)
    if market == :nil do
      :ok
    else
      # Returning all stakes to users
      GenServer.call(market, :market_cancel)
      receive do reply -> reply end
    end
  end

  @doc """
  Stops all betting in the market; stakes
  in non-matched bets are returned to users.

  ## Examples

      iex> Betunfair.market_freeze(#PID<_>)
      :ok

  """
  @spec market_freeze(id :: market_id()):: :ok
  def market_freeze(id) do
    market = Process.get(id)
    if market == :nil do
      :ok
    else
      GenServer.call(market, :market_freeze)
      receive do reply -> reply end
    end
  end

  @doc """
  The market (event) has been resolved with argument result.
  Winnings are distributed to winning users according to stakes and odds.

  ## Examples

      iex> Betunfair.market_settle(#PID<_>, True)
      :ok

  """
  @spec market_settle(id :: market_id(), result :: boolean()):: :ok
  def market_settle(id, result) do
    market = Process.get(id)
    if market == :nil do
      :error
    else
      GenServer.call(market, {:market_settle, result})
      receive do reply -> reply end
    end
  end

  @doc """
  All bets (matched or unmatched) for the market are returned.

  ## Examples

      iex> Betunfair.market_bets(#PID<_>)
      {:ok, ["Madrid - Barca"]}

  """
  @spec market_bets(id :: market_id()) :: {:ok, Enumerable.t(bet_id())}
  def market_bets(id) do
    market = Process.get(id)
    if market == :nil do
      {:ok, []}
    else
      GenServer.call(market, :market_bets)
      receive do reply -> reply end
    end
  end

  @doc """
  All pending (non matched) backing bets for the market are returned.
  Note that the bets are returned as a tuple {odds,bet_id},
  and that the elements should be returned in ascending order
  (i.e., bets with smaller odds first).

  ## Examples

      iex> Betunfair.market_bets(#PID<_>)
      {:ok, ["Madrid - Barca"]}

  """
  @spec market_pending_backs(id :: market_id()) :: {:ok, Enumerable.t({integer(), bet_id()})}
  def market_pending_backs(id) do
    market = Process.get(id)
    if market == :nil do
      {:ok, []}
    else
      GenServer.call(market, :market_pending_backs)
      receive do reply -> reply end
    end
  end

  @doc """
  All pending lay bets for the market are returned.
  Note that the bets are returned as a tuple {odds,bet_id},
  and that the elements should be returned in descending order
  (i.e., bets with larger odds first).

  ## Examples

      iex> Betunfair.market_bets(#PID<_>)
      {:ok, ["Madrid - Barca"]}

  """
  @spec market_pending_lays(id :: market_id()) :: {:ok, Enumerable.t({integer(), bet_id()})}
  def market_pending_lays(id) do
    market = Process.get(id)
    if market == :nil do
      {:ok, []}
    else
      GenServer.call(market, :market_pending_lays)
      receive do reply -> reply end
    end
  end

  @doc """
  Returns an enumerable containing all market's info.

  ## Parameters
    - id, the string that identifies the market

  ## Examples

      iex> Betunfair.market_get("Madrid wins over Barca")
      {:ok,
            %{ name: "Madrid wins over Barca"
             , description: "Friendly match the 26/05,
                              bet predicting that Madrid wins over Barca"
             , status: :active
             }
      }

  """
  @spec market_get(id :: user_id()) ::
  {:ok | :error, %{name: string(), description: string(),
                    status: :active | :frozen | :cancelled | {:settled, result::bool()}}}
  def market_get(id) do
    market = Process.get(id)
    if market == :nil do
      {:error, %{}}
    else
      GenServer.call(market, :market_get)
      receive do reply -> reply end
    end
  end

  @doc """
  Try to match backing and lay bets in the specified market.

  ## Parameters
    - id, the string that identifies the market

  ## Examples

      iex> Betunfair.market_match("Madrid wins over Barca")
      :ok

  """
  @spec market_match(id :: market_id()):: :ok
  def market_match(id) do
    market = Process.get(id)
    if market == :nil do
      :ok
    else
      GenServer.call(market, :market_match)
      receive do _reply -> :ok end
    end
  end

  ##########################
  #### BETS INTERACTION ####
  ##########################
 # ------------------------- BETS -------------------------

  @spec bet_back(user_id :: user_id(), market_id :: market_id(),
  stake :: integer(), odds :: integer()) :: {:ok, bet_id()}
  # creates a backing bet by the specified user and for the market specified.
  def bet_back(user_id, market_id, stake, odds) do
    bet_id = {user_id, market_id} # store the bet_id as tuple
    bet = Process.get(:bet, %{})
    if Map.has_key?(bet,bet_id) do
      {:error, bet_id} # if bet exists, error is returned
    else
      updated_bet = Map.put(bet, %{:back, market_id, user_id, odds, stake,
      _remaining_stake, [], _status})
      Process.put(:bet, updated_bet)
      {:ok,bet_id} # else, the bet is created

  end

  @spec bet_lay(user_id :: user_id(),market_id :: market_id(),
  stake :: integer(),odds :: integer()) :: {:ok, bet_id()}
  # creates a lay bet by the specified user and for the market specified.
  def bet_lay(user_id, market_id, stake, odds) do
    bet_id = {user_id, market_id} # store the bet_id as tuple
    bet = Process.get(:bet, %{})
    if Map.has_key?(bet,bet_id) do
      {:error, bet_id} # if bet exists, error is returned
    else
      updated_bet = Map.put(bet, %{:lay, market_id, user_id, odds, stake,
      _remaining_stake, [_bet_id], _status})
      Process.put(:bet, updated_bet)
      {:ok,bet_id} # else, the bet is created

  end

  @spec bet_cancel(id :: bet_id()) :: :ok
  # cancels the parts of a bet that has not been matched yet.
  def bet_cancel(id) do
    case Process.get(id) do
      :nil ->
        :ok # if there is no bet to cancel, ok
      _ ->
        bet = Process.get(:bet)
        if Map.has_key?(bet,id) && Enum.member?(market_pednding_backs(Map.get(bet,elem(id,1))),id)do
          Map.put(bet, :status, :cancelled)
          user_deposit(elem(id,0),Map.get(bet,:original_stake))
            receive do reply -> reply end
            # if there is a bet, we cancel it and return the stake to the user.
        else
          :error # else, error

  end

  @spec bet_cancel_whole(id :: bet_id()) :: :ok
  # cancels the parts of a bet that has not been matched yet.
  def bet_cancel_whole(id) do
    case Process.get(id) do
      :nil ->
        :ok # if there is no bet to cancel, ok
      _ ->
        bet = Process.get(:bet)
        if Map.has_key?(bet,id) && Enum.member?(market_bets(Map.get(bet,elem(id,1))),id)do
          Map.put(bet, :status, :cancelled)
          user_deposit(elem(id,0),Map.get(bet,:original_stake))
            receive do reply -> reply end
            # if there is a bet, we cancel it and return the stake to the user.
        else
          :error # else, error

  end

  @spec bet_get(id :: bet_id()) ::{:ok,
           %{bet_type: :back | :lay, market_id: market_id(), user_id: user_id(),
             odds: integer(),
             original_stake: integer(),  # original stake
             remaining_stake: integer(), # non-matched stake
             matched_bets: [bet_id()], # list of matched bets
             status:
               :active | :cancelled | :market_cancelled | {:market_settled, boolean()}}}
  def bet_get(id) do
    bet = Process.get(:bet)
    if Map.has_key?(bet, id) do
      {:ok,bet_to_get}= Map.fetch(bet,id)
      {:ok,&{bet_type: bet_to_get[:bet_type],bet_to_get[:odds],
      bet_to_get[:original_stake], bet_to_get[:remaining_stake],
      bet_to_get[:matched_bets[id]], bet_to_get[:status]}}

  end

  ######################
  #### HANDLE CALLS ####
  ######################

  def handle_call({:market_settle, result}, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = backs ++ lays
    List.foldl(list_bets, :nil, fn bet_id, _acc -> bet_settle(bet_id,result) end)
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             satus: {:settled, result}}
    {:reply, :ok, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_freeze, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = backs ++ lays
    List.foldl(list_bets, :nil, fn bet_id, _acc -> bet_cancel(bet_id) end)
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             satus: :frozen}
    {:reply, :ok, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_cancel, _from, %{market: market_info, backs: backs, lays: lays}) do
    # We could use map but it may be executed in //
    # and if so, it could give weird results
    # (one bet cancel may overwrite another that's in //)
    list_bets = backs ++ lays
    List.foldl(list_bets, [], fn bet_id, _acc -> bet_cancel_all(bet_id) end)
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             satus: :cancelled}
    {:reply, :ok, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_bets, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = Enum.map(backs++lays, fn bet_id -> bet_id end)
    {:reply, {:ok, list_bets}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_pending_backs, _from, %{market: market_info, backs: backs, lays: lays}) do
    # Remark : Sorting after constructing the list gives better performances
    # if we do a bubblesort-like for sorting while constructing it we have a O(n^2)
    # complexity while it's O(n+nlog(n)) = O(nlog(n)) for sorting after creating it.
    get_bets = List.foldl(backs, [], BetUnfair.extract_info_bet/2)
    {:reply, {:ok, List.keysort(get_bets,0)}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_pending_lays, _from, %{market: market_info, backs: backs, lays: lays}) do
    get_bets = List.foldl(lays, [], BetUnfair.extract_info_bet/2)
    {:reply, {:ok, List.keysort(get_bets,0)}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_get, _from, %{market: market_info, backs: backs, lays: lays}) do
    {:reply, {:ok, market_info}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_match, _from, {market_info, bets}) do
    ## TODO : match the bets in this market if possible ##
  end

  def extract_info_bet(bet_id, acc) do
    bet_infos = elem(bet_get(bet_id),1)
    if bet_infos[:matched_bets] != [] do
      [{bet_infos[:odds], bet_id} | acc]
    else
      acc
    end
  end
end
