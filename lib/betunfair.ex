defmodule Betunfair do
  @moduledoc """
  Documentation for `Betunfair`.
  """
  use GenServer
  use Agent

  ## Variations in the API were made iff we added the error  ##
  ## support for higher robustness                           ##

  # GenServer is used for markets :
  # each market runs with a unique pid & server
  # in order to increase scalability of market places
  # The users are linked to the whole system and as such
  # are "stored" using the main module along with the Process module

  @type user_id :: String.t()
  @type market_id :: pid()
  @type bet_id :: %{user: user_id(), market: market_id(), counter: integer()}
  @type users :: %{user_id() => %{user: String.t(), balance: integer(), bets: [bet_id()]}}
  # A market is defined by the participants to a bet
  @type market :: %{ name: String.t(),
                     description: String.t(),
                     status: :active |
                             :frozen |
                             :cancelled |
                             {:settled, result::bool()}}
  @type bet :: %{ id: bet_id(),
                  bet_type: :back | :lay,
                  market_id: market_id(),
                  user_id: user_id(),
                  odds: integer(),
                  original_stake: integer(), # original stake
                  stake: integer(), # non-matched stake
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
  If it exists the existing data (markets, bets, users) is recovered.
  If an exchange place is already running, it's returning :error.

  ## Parameters
    - name, which is the name of the market created

  ## Examples

      iex> Betunfair.start_link("Madrid-Barca")
      {:ok, %{}}

  """
  @spec start_link(name :: String.t()) :: {:ok, String.t()} | :error
  def start_link(name) do
    db = Process.get(:db)
    if Process.put(:agentCreated?, true) do
      :error
    else
      Process.put(:agentCreated?, true)
      Agent.start_link(fn -> {name, %{}} end, name: MarketPlaces)
      if db == :nil or CubDB.get(db, name) == :nil do
        # It's a new exchange place, everything's already done
      else
        # We have to retrive the data
        %{users: users, counter: counter, markets: data_markets} = CubDB.get(db, name)
        Process.put(:users, users)
        Process.put(:counter, counter)
        # Fold to do them in sequence to avoid pid's table issues
        List.foldl(data_markets, :nil, fn market,_acc -> market_restart(market) end)
      end
      {:ok, name}
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
    db = Process.get(:db)
    if db == :nil do
      {:ok, db} = CubDB.start_link(data_dir: "./db_files")
      Process.put(:db, db)
    end
    db = Process.get(:db)
    ## Preserving exchange data
    {name, markets_map} = Agent.get(MarketPlaces, & &1)
    fold_data =  fn {_, {pid, _}}, acc -> [elem(GenServer.call(pid, :save_market),1) | acc] end
    data_markets = Enum.reduce(markets_map, [], fold_data)
    data_saved = %{users: Process.get(:users, %{}), counter: Process.get(:counter,0), markets: data_markets}
    CubDB.put(db, name, data_saved)

    ## Stopping the running exchange
    # Reset the users and the counter
    Process.put(:counter, 0)
    Process.put(:users, %{})
    # Stopping the GenServers
    Enum.map(markets_map, fn {_, {pid, _}} -> GenServer.stop(pid) end)
    Agent.stop(MarketPlaces)
    Process.put(:agentCreated?, false)
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
  @spec clean(name :: String.t()):: {:ok, String.t()}
  def clean(name) do
    if Process.get(:agentCreated?) do
      {name_actual, markets_map} = Agent.get(MarketPlaces, & &1)
      if name_actual == name do
        # Reset the users and the counter
        Process.put(:counter, 0)
        Process.put(:users, %{})
        # Stopping the GenServers
        Enum.map(markets_map, fn {_, {pid, _}} -> GenServer.stop(pid) end)
        Agent.stop(MarketPlaces)
        Process.put(:agentCreated?, false)
      else
        db = Process.get(:db)
        if db == :nil do
          # Nothing to clean
        else
          CubDB.delete(db, name)
        end
      end
    else
    end
    {:ok, name}
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
    if Map.has_key?(users, id) and amount > 0 do
      {:ok, user} = Map.fetch(users, id)
      new_amount = user[:balance] + amount
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
      {:ok, user[:bets]}
    else
      {:ok, []}
    end
  end

  ############################
  #### MARKET INTERACTION ####
  ############################

  @doc """
  Creates a market with the unique name,
  and a potentially longer description.
  All market created are on by default.

  ## Parameters
    - name, the name of the market
    - description, a description of it

  ## Examples

      iex> Betunfair.market_create("Madrid-Barca", "Market place for Madrid-Barca bets result")
      {:ok, "Madrid-Barca"}

  """
  @spec market_create(name :: String.t(), description :: String.t()) :: {:ok, market_id()}
  def market_create(name, description) do
    {:ok, pid} = GenServer.start_link(Betunfair, {name, description})
    Agent.update(MarketPlaces, fn {name_exchange, map} -> {name_exchange, (Map.put(map, name, {pid, :on}))} end)
    {:ok, name}
  end

  def market_restart(%{market: market_info, backs: backs, lays: lays}) do
    {:ok, pid} = GenServer.start_link(Betunfair, %{market: market_info, backs: backs, lays: lays})
    %{name: name} = market_info
    Agent.update(MarketPlaces, fn {name_exchange, map} -> {name_exchange, (Map.put(map, name, {pid, :on}))} end)
    :nil
  end

  @doc """
  GenServer function associated to market_create.
  Initialize the GenServer state.
  """
  def init({name, description}) do
    market_info = %{name: name, description: description, status: :active}
    {:ok, %{market: market_info, backs: [], lays: []}}
  end
  def init(%{market: market_info, backs: backs, lays: lays}) do
    {:ok, %{market: market_info, backs: backs, lays: lays}}
  end

  @doc """
  Returns all markets.

  ## Examples

      iex> Betunfair.market_list()
      {:ok, ["Madrid-Barca"]}

  """
  @spec market_list() :: {:ok, [market_id()]}
  def market_list() do
    list_markets = Map.keys(Agent.get(MarketPlaces, fn {_name, map} -> map end))
    {:ok, list_markets}
  end

  @doc """
  Returns all active markets.

  ## Examples

      iex> Betunfair.market_list_active()
      {:ok, ["Madrid-Barca"]}

  """
  @spec market_list_active() :: {:ok, [market_id()]}
  def market_list_active() do
    map_market = Agent.get(MarketPlaces, fn {_name, map} -> map end)
    list_active_markets = filter(Map.to_list(map_market), fn {_id, {_pid, on?}} -> on? == :on end)
    list_active_markets = Enum.map(list_active_markets, fn {id, _} -> id end)
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
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == [] do
      :ok
    else
      {market, _on?} = market_agent
      {:ok, list_bets} = GenServer.call(market, :market_cancel)
      # We could use map but it may be executed in //
      # and if so, it could give weird results
      # (one bet cancel may overwrite another that's in //)
      List.foldl(list_bets, :nil, fn bet_id, _acc -> bet_cancel_whole(bet_id) end)
      :ok
    end
  end

  @doc """
  Stops all betting in the market; stakes
  in non-matched bets are returned to users.

  ## Examples

      iex> Betunfair.market_freeze("Madrid-Barca")
      :ok

  """
  @spec market_freeze(id :: market_id()):: :ok
  def market_freeze(id) do
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == [] do
      :ok
    else
      {market, _on?} = market_agent
      {:ok, list_bets} = GenServer.call(market, :market_freeze)
      List.foldl(list_bets, :nil, fn bet_id, _acc -> bet_cancel(bet_id) end)
      :ok
    end
  end

  @doc """
  The market (event) has been resolved with argument result.
  Winnings are distributed to winning users according to stakes and odds.

  ## Examples

      iex> Betunfair.market_settle("Madrid-Barca", True)
      :ok

  """
  @spec market_settle(id :: market_id(), result :: boolean()):: :ok
  def market_settle(id, result) do
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == [] do
      :error
    else
      {market, _on?} = market_agent
      {:ok, list_bets} = GenServer.call(market, {:market_settle, result})
      List.foldl(list_bets, :nil, fn bet_id, _acc -> bet_settle(bet_id,result) end)
      :ok
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
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == [] do
      {:ok, []}
    else
      {market_pid, _on?} = market_agent
      GenServer.call(market_pid, :market_bets)
    end
  end

  @doc """
  All pending (non matched) backing bets for the market are returned.
  Note that the bets are returned as a tuple {odds,bet_id},
  and that the elements should be returned in ascending order
  (i.e., bets with smaller odds first).

  ## Examples

      iex> Betunfair.market_bets("Madrid-Barca")
      {:ok, ["Madrid - Barca"]}

  """
  @spec market_pending_backs(id :: market_id()) :: {:ok, Enumerable.t({integer(), bet_id()})}
  def market_pending_backs(id) do
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == [] do
      {:ok, []}
    else
      {market_pid, _on?} = market_agent
      GenServer.call(market_pid, :market_pending_backs)
    end
  end

  @doc """
  All pending lay bets for the market are returned.
  Note that the bets are returned as a tuple {odds,bet_id},
  and that the elements should be returned in descending order
  (i.e., bets with larger odds first).

  ## Examples

      iex> Betunfair.market_bets("Madrid-Barca")
      {:ok, ["Madrid - Barca"]}

  """
  @spec market_pending_lays(id :: market_id()) :: {:ok, Enumerable.t({integer(), bet_id()})}
  def market_pending_lays(id) do
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == [] do
      {:ok, []}
    else
      {market_pid, _on?} = market_agent
      GenServer.call(market_pid, :market_pending_lays)
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
  @spec market_get(id :: user_id()) :: {:ok | :error, market()}
  def market_get(id) do
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == :nil do
      {:error, %{}}
    else
      {market_pid, _on?} = market_agent
      GenServer.call(market_pid, :market_get)
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
    market_agent = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id)
    if market_agent == :nil do
      :ok
    else
      {market_pid, _on?} = market_agent
      GenServer.call(market_pid, :market_match)
    end
  end

  ##########################
  #### BETS INTERACTION ####
  ##########################

  @doc """
  Back a bet. In this case the backer takes a
  position of the bookie and offers the bet,
  providing a bet type :back.

  ## Parameters
    - id, the user identifier
    - market, the identifier of the market
    - odds, the odds to which the back bet is taken
    - stake, the stake of the bet

  ## Examples

      iex> Betunfair.bet_back("Alice", 2.10, 100)
      {:ok, %{...}}

  """

  @spec bet_back(user_id :: user_id(), market_id :: market_id(),
                 stake :: integer(), odds :: integer()) :: {:ok, bet_id()} | :error
  # creates a backing bet by the specified user and for the market specified
  def bet_back(user_id, market_id, stake, odds) do
    {:ok, market} = market_get(market_id)
    if market[:status] == :active do
      can_bet? = user_withdraw(user_id, stake)
      if can_bet? == :ok do
        # Create the bet_id
        counter = Process.get(:counter, 0)
        Process.put(:counter, counter+1)
        bet_id = %{user: user_id, market: market_id, counter: counter} # store the bet_id as tuple
        # Add the bet to the user informations
        users = Process.get(:users)
        {:ok, user} = Map.fetch(users, user_id)
        updated_user = %{name: user[:name], balance: user[:balance], bets: [bet_id | user[:bets]]}
        updated_users = Map.put(users, user_id, updated_user)
        Process.put(:users, updated_users)
        # Create the new bet in the market
        {market_pid, _on?} = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), market_id)
        GenServer.call(market_pid, {:new_bet, bet_id, market_id, user_id, :back, odds, stake})
      else
        :error
      end
    else
      :error
    end
  end

  @doc """
  Lay a bet. In this case a backer takes a
  position of the bookie and offers the bet,
  providing a bet type :lay.

  ## Parameters
    - id, the user identifier
    - market, the identifier of the market
    - odds, the odds to which the lay bet is taken
    - stake, the stake of the bet

  ## Examples

      iex> Betunfair.bet_lay("Alice", 0.15, 50)
      {:ok, %{...}}

  """
  @spec bet_lay(user_id :: user_id(),market_id :: market_id(),
                stake :: integer(),odds :: integer()) :: {:ok, bet_id()} | :error
  # creates a lay bet by the specified user and for the market specified.
  def bet_lay(user_id, market_id, stake, odds) do
    {:ok, market} = market_get(market_id)
    if market[:status] == :active do
      can_bet? = user_withdraw(user_id, stake)
      if can_bet? == :ok do
        # Create the bet_id
        counter = Process.get(:counter, 0)
        Process.put(:counter, counter+1)
        bet_id = %{user: user_id, market: market_id, counter: counter} # store the bet_id as tuple
        # Add the bet to the user informations
        users = Process.get(:users)
        {:ok, user} = Map.fetch(users, user_id)
        updated_user = %{name: user[:name], balance: user[:balance], bets: [bet_id | user[:bets]]}
        updated_users = Map.put(users, user_id, updated_user)
        Process.put(:users, updated_users)
        # Create the new bet in the market
        {market_pid, _on?} = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), market_id)
        GenServer.call(market_pid, {:new_bet, bet_id, market_id, user_id, :lay, odds, stake})
      else
        :error
      end
    else
      :error
    end
  end

  @doc """
  Cancels a part of a bet. Returns :ok if successfull

  ## Parameters
    - id, the bet_id

  ## Examples

      iex> Betunfair.bet_cancel(15)
      :ok

  """

  @spec bet_cancel(id :: bet_id()) :: :ok
  # cancels the parts of a bet that has not been matched yet.
  def bet_cancel(id) do
    # Returning all stakes to users
    {market_pid, _on?} = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id[:market])
    amount = GenServer.call(market_pid, {:bet_cancel, id})
    user_deposit(id[:user], amount)
    :ok
  end

  @doc """
  Cancels the whole bet. Returns :ok if successfull

  ## Parameters
    - id, the bet_id

  ## Examples

      iex> Betunfair.bet_cancel(15)
      :ok

  """
  @spec bet_cancel_whole(id :: bet_id()) :: :ok
  # cancels the parts of a bet that has not been matched yet.
  def bet_cancel_whole(id) do
    # Returning all stakes to users
    {market_pid, _on?} = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id[:market])
    amount = GenServer.call(market_pid, {:bet_cancel_whole, id})
    user_deposit(id[:user], amount)
    :ok
  end

  @doc """
  Retrieves information about the bet. Returns :ok and bet if successfull

  ## Parameters
    - id, the bet_id

  ## Examples

      iex> Betunfair.bet_get(15)
      {:ok, {15, :back , 12, 14, 105, 100, 0, matched_bets: [15],:active {:market_settled, true}}}

  """
  @spec bet_get(id :: bet_id()) ::{:ok, bet()}
  def bet_get(id) do
    {market_pid, _on?} = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id[:market])
    GenServer.call(market_pid, {:bet_get, id})
  end

  @doc """
  Settle a bet.

  ## Parameters
    - bet: The bet structure returned by `bet_place/5`
    - result: The result of the bet (true/false)

  ## Examples

      iex> user = Betunfair.user_create("John", 100)
      iex> market = Betunfair.market_create("Madrid-Barca", "Who will win?")
      iex> {:ok, _, bet} = Betunfair.bet_place(user, market, :back, 2, 10)
      iex> Betunfair.bet_settle(bet, true)
      :ok
  """
  @spec bet_settle(id :: bet_id(), result :: boolean()) :: :ok | :error
  def bet_settle(id, result) do
    {:ok, bet} = bet_get(id)
    {market_pid, _on?} = Map.get(Agent.get(MarketPlaces, fn {_name, map} -> map end), id[:market])
    {back_win, lay_win, remaining_stake} = GenServer.call(market_pid,{:bet_settle, id, result})
    if (result) do
      if (bet[:bet_type] == :back) do
        user_deposit(id[:user], back_win)
      else
        # We give back what's unused
        user_deposit(id[:user], remaining_stake)
      end
    else
      if (bet[:bet_type] == :lay) do
        user_deposit(id[:user], lay_win)
      else
        # We give back what's unused
        user_deposit(id[:user], remaining_stake)
      end
    end
    :ok
  end

  ######################
  #### HANDLE CALLS ####
  ######################

  def handle_call({:market_settle, result}, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = backs ++ lays
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             status: {:settled, result}}
    {:reply, {:ok, list_bets}, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_freeze, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = backs ++ lays
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             status: :frozen}
    {:reply, {:ok, list_bets}, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_cancel, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = backs ++ lays
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             status: :cancelled}
    {:reply, {:ok, list_bets}, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_bets, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = Enum.map(backs++lays, fn bet_id -> bet_id end)
    {:reply, {:ok, list_bets}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_pending_backs, _from, %{market: market_info, backs: backs, lays: lays}) do
    get_bets = Enum.map(backs, fn bet_id -> Betunfair.extract_info_bet(bet_id) end)
    {:reply, {:ok, get_bets}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_pending_lays, _from, %{market: market_info, backs: backs, lays: lays}) do
    get_bets = Enum.map(lays, fn bet_id -> Betunfair.extract_info_bet(bet_id) end)
    {:reply, {:ok, get_bets}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_get, _from, %{market: market_info, backs: backs, lays: lays}) do
    {:reply, {:ok, market_info}, %{market: market_info, backs: backs, lays: lays}}
  end

  # Pre-condition : backs and lays are sorted by the odds and the time they were placed
  def handle_call(:market_match, _from, %{market: market_info, backs: backs, lays: lays}) do
	  matching_algorithm(backs, lays)
    {:reply, :ok, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call({:new_bet, bet_id, market_id, user_id, bet_type, odds, stake},
                  _from, %{market: market_info, backs: backs, lays: lays}) do
    bet = Process.get(bet_id)
    # if bet doesn't exists, it is created,
    # else, error is returned
    %{status: market_status} = market_info
    if bet == :nil && market_status == :active do
      bet_infos = %{ id: bet_id,
                     bet_type: bet_type,
                     market_id: market_id,
                     user_id: user_id,
                     odds: odds,
                     original_stake: stake, # original stake
                     stake: stake, # non-matched stake
                     matched_bets: [], # list of matched bets
                     status: :active
                   }
      Process.put(bet_id, bet_infos)
	    # We insert the bet in the market's state
      if bet_type == :back do
        updated_lays = lays
        updated_backs = insert_by(bet_id, backs, fn id -> Process.get(id)[:odds] end, :asc)
        {:reply, {:ok, bet_id}, %{market: market_info, backs: updated_backs, lays: updated_lays}}
      else
        updated_backs = backs
        updated_lays = insert_by(bet_id, lays, fn id -> Process.get(id)[:odds] end, :desc)
        {:reply, {:ok, bet_id}, %{market: market_info, backs: updated_backs, lays: updated_lays}}
      end
    else
      {:reply, :error, %{market: market_info, backs: backs, lays: lays}}
	  end
  end

  def handle_call({:bet_cancel, bet_id}, _from, market_infos) do
    case Process.get(bet_id) do
      :nil ->
        {:reply, :ok, market_infos} # if there is no bet to cancel, ok
      bet ->
        # if there is a bet, we cancel it and return the stake to the user.
        updated_bet = %{ id: bet_id,
                         bet_type: bet[:bet_type],
                         market_id: bet[:market_id],
                         user_id: bet[:user_id],
                         odds: bet[:odds],
                         original_stake: bet[:original_stake]-bet[:stake], # we cancelled the other
                         stake: 0, # non-matched stake
                         matched_bets: bet[:matched_bets], # list of matched bets
                         status: :active
                      }
        Process.put(bet_id, updated_bet)
		    {:reply, bet[:stake], market_infos}
	  end
  end

  def handle_call({:bet_cancel_whole, bet_id}, _from, market_infos) do
    case Process.get(bet_id) do
      :nil ->
        {:reply, :ok, market_infos} # if there is no bet to cancel, ok
      bet ->
        # if there is a bet, we cancel it and return the stake to the user.
        updated_bet = %{ id: bet_id,
                         bet_type: bet[:bet_type],
                         market_id: bet[:market_id],
                         user_id: bet[:user_id],
                         odds: bet[:odds],
                         original_stake: bet[:original_stake], # original stake
                         stake: bet[:original_stake], # non-matched stake
                         matched_bets: [], # list of matched bets
                         status: :cancelled
                      }
        Process.put(bet_id, updated_bet)
        {:reply, bet[:original_stake], market_infos}
	  end
  end

  def handle_call({:bet_get, bet_id}, _from, market_infos) do
    bet = Process.get(bet_id)
    if bet == :nil do
      {:reply, {:error, :nil}, market_infos}
    else
      {:reply, {:ok, bet}, market_infos}
    end
  end

  def handle_call({:bet_settle, bet_id, result}, _from, market_infos) do
    bet = Process.get(bet_id)
    if bet == :nil or bet[:status] != :active do
      {:reply, {0, 0, 0}, market_infos}
    else
      updated_bet = %{ id: bet_id,
                       bet_type: bet[:bet_type],
                       market_id: bet[:market_id],
                       user_id: bet[:user_id],
                       odds: bet[:odds],
                       original_stake: bet[:original_stake], # original stake
                       stake: bet[:stake], # non-matched stake
                       matched_bets: [], # list of matched bets
                       status: {:settled, result}
                    }
      Process.put(bet_id, updated_bet)
      betted = bet[:original_stake] - bet[:stake]
      back_win = Kernel.trunc((bet[:odds]*betted)/100)+bet[:stake]
      lay_win = Kernel.trunc(betted/(bet[:odds]/100-1))+betted+bet[:stake]
      {:reply, {back_win, lay_win, bet[:stake]}, market_infos}
    end
  end

  def handle_call(:save_market, _from, market) do
    {:reply, {:ok, market}, market}
  end

  def extract_info_bet(bet_id) do
    bet_infos = Process.get(bet_id)
    if bet_infos[:matched_bets] == [] do
      {bet_infos[:odds], bet_id}
    else
      []
    end
  end

  def matching_algorithm(backs, lays) do
    case {backs, lays} do
      {[], _} -> :ok
      {_, []} -> :ok
      {[hbacks | tbacks], [hlays | tlays]} ->
        get_back = Process.get(hbacks)
        get_lay = Process.get(hlays)
        if get_back[:status] != :active || get_back[:stake] == 0 do
          matching_algorithm(tbacks, lays)
        end
        if get_lay[:status] != :active || get_lay[:stake] == 0 do
          matching_algorithm(backs, tlays)
        end
        if get_back[:odds] <= get_lay[:odds] do
          # There's a match !
          allowed_to_loose = Kernel.trunc(get_back[:stake]*get_back[:odds]/100)-get_back[:stake]
          if allowed_to_loose >= get_lay[:stake] do
            betted = Kernel.trunc(get_lay[:stake]/(get_back[:odds]/100-1))
            # We consume all of the lay stake
            updated_lay = %{ bet_type: get_lay[:bet_type],
                             market_id: get_lay[:market_id],
                             user_id: get_lay[:user_id],
                             odds: get_lay[:odds],
                             original_stake: get_lay[:original_stake], # original stake
                             stake: 0, # non-matched stake
                             matched_bets: [ hbacks | get_lay[:matched_bets]], # list of matched bets
                             status: :active
                            }
            updated_back = %{ bet_type: get_back[:bet_type],
                              market_id: get_back[:market_id],
                              user_id: get_back[:user_id],
                              odds: get_back[:odds],
                              original_stake: get_back[:original_stake], # original stake
                              stake: get_back[:stake]-betted, # non-matched stake
                              matched_bets: [ hlays | get_back[:matched_bets]], # list of matched bets
                              status: :active
                            }
            Process.put(hlays, updated_lay)
            Process.put(hbacks, updated_back)
            matching_algorithm(backs, tlays)
          else
            # We consume all of the backing stake
            consummed = Kernel.trunc(get_back[:stake]*(get_back[:odds]/100-1))
            updated_lay = %{ bet_type: get_lay[:bet_type],
                             market_id: get_lay[:market_id],
                             user_id: get_lay[:user_id],
                             odds: get_lay[:odds],
                             original_stake: get_lay[:original_stake], # original stake
                             stake: get_lay[:stake]-consummed, # non-matched stake
                             matched_bets: [ hbacks | get_lay[:matched_bets]], # list of matched bets
                             status: :active
                            }
            updated_back = %{ bet_type: get_back[:bet_type],
                              market_id: get_back[:market_id],
                              user_id: get_back[:user_id],
                              odds: get_back[:odds],
                              original_stake: get_back[:original_stake], # original stake
                              stake: 0, # non-matched stake
                              matched_bets: [ hlays | get_back[:matched_bets]], # list of matched bets
                              status: :active
                            }
            Process.put(hlays, updated_lay)
            Process.put(hbacks, updated_back)
            matching_algorithm(tbacks, lays)
          end
        else
          :ok
        end
    end
  end

  ########################
  #### MISC FUNCTIONS ####
  ########################

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

  def insert_by(elem, [], _, _) do
	  [elem]
  end
  def insert_by(elem, [head | tail], function, :asc) do
    if function.(head) <= function.(elem) do
      [head | insert_by(elem, tail, function, :asc)]
    else
      [elem | [head | tail]]
    end
  end
  def insert_by(elem, [head | tail], function, :desc) do
    if function.(head) > function.(elem) do
      [head | insert_by(elem, tail, function, :desc)]
    else
      [elem | [head | tail]]
    end
  end
end
