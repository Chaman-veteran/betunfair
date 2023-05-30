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
    if Process.get(name) != :nil do
      {market_id, _} = Process.get(name)
      market_cancel(market_id)
      GenServer.stop(market_id)
      Process.delete(name)
    end
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
    if Map.has_key?(users, id) and amount > 0 do
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
    Process.put(market_pid, {market_pid, :on})
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
    valide_market = &(  &1 != :users
                     && &1 != :market_server
                     && &1 != :iex_evaluator
                     && &1 != :iex_server
                     && &1 != :iex_history
                     && &1 != :"$ancestors"
                     && &1 != :"$initial_call"
                     && &1 != :rand_seed
                     && &1 != :counter)
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
    valide_market = &(  &1 != :users
                     && &1 != :market_server
                     && &1 != :iex_evaluator
                     && &1 != :iex_server
                     && &1 != :iex_history
                     && &1 != :"$ancestors"
                     && &1 != :"$initial_call"
                     && &1 != :rand_seed
                     && &1 != :counter)
    valide_market_on = &(valide_market.(elem(&1,0)) && elem(elem(&1,1),1) == :on)
    list_active_markets = filter(list_markets, valide_market_on)
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      :ok
    else
      # Returning all stakes to users
      GenServer.call(market, :market_cancel)
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      :ok
    else
      GenServer.call(market, :market_freeze)
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      :error
    else
      GenServer.call(market, {:market_settle, result})
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      {:ok, []}
    else
      GenServer.call(market, :market_bets)
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      {:ok, []}
    else
      GenServer.call(market, :market_pending_backs)
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      {:ok, []}
    else
      GenServer.call(market, :market_pending_lays)
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      {:error, %{}}
    else
      GenServer.call(market, :market_get)
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
    {market, _on?} = Process.get(id, {:nil, :off})
    if market == :nil do
      :ok
    else
      GenServer.call(market, :market_match)
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
      {:ok, PID<_>}

  """

  @spec bet_back(user_id :: user_id(), market_id :: market_id(),
                 stake :: integer(), odds :: integer()) :: {:ok, bet_id()} | :error
  # creates a backing bet by the specified user and for the market specified.
  def bet_back(user_id, market_id, stake, odds) do
    can_bet? = user_withdraw(user_id, stake)
    if can_bet? == :ok do
      counter = Process.get(:counter, 0)
      Process.put(:counter, counter+1)
      bet_id = %{user: user_id, market: market_id, counter: counter} # store the bet_id as tuple
      GenServer.call(market_id, {:new_bet, bet_id, market_id, user_id, :back, odds, stake})
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
      {:ok, PID<_>}

  """
  @spec bet_lay(user_id :: user_id(),market_id :: market_id(),
                stake :: integer(),odds :: integer()) :: {:ok, bet_id()} | :error
  # creates a lay bet by the specified user and for the market specified.
  def bet_lay(user_id, market_id, stake, odds) do
    can_bet? = user_withdraw(user_id, stake)
    if can_bet? == :ok do
      counter = Process.get(:counter, 0)
      Process.put(:counter, counter+1)
      bet_id = %{user: user_id, market: market_id, counter: counter} # store the bet_id as tuple
      GenServer.call(market_id, {:new_bet, bet_id, market_id, user_id, :lay, odds, stake})
    else
      :error
    end
  end


  @spec bet_cancel(id :: bet_id()) :: :ok
  # cancels the parts of a bet that has not been matched yet.
  def bet_cancel(id) do
    reply = GenServer.call(id[:market], {:bet_cancel, id})
    user_deposit(id[:user], reply)
    :ok
  end

  @spec bet_cancel_whole(id :: bet_id()) :: :ok
  # cancels the parts of a bet that has not been matched yet.
  def bet_cancel_whole(id) do
    GenServer.call(id[:market], {:bet_cancel_whole, id})
  end

  @spec bet_get(id :: bet_id()) ::{:ok, bet()}
  def bet_get(id) do
    GenServer.call(id[:market], {:bet_get, id})
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
    case bet_get(id) do
      :nil->
        :error
      _->
        if(result) do
          reply = GenServer.call(id[:market],{:bet_settle, id})
          user_deposit(id[:user], reply)
        else
          GenServer.call(id[:market],{:bet_settle, id})
        end
        :ok
    end
  end

  ######################
  #### HANDLE CALLS ####
  ######################

  def handle_call({:market_settle, result}, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = backs ++ lays
    List.foldl(list_bets, :nil, fn bet_id, _acc -> bet_settle(bet_id,result) end)
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             status: {:settled, result}}
    {:reply, :ok, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_freeze, _from, %{market: market_info, backs: backs, lays: lays}) do
    list_bets = backs ++ lays
    List.foldl(list_bets, :nil, fn bet_id, _acc -> bet_cancel(bet_id) end)
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             status: :frozen}
    {:reply, :ok, %{market: updated_market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_cancel, _from, %{market: market_info, backs: backs, lays: lays}) do
    # We could use map but it may be executed in //
    # and if so, it could give weird results
    # (one bet cancel may overwrite another that's in //)
    list_bets = backs ++ lays
    List.foldl(list_bets, [], fn bet_id, _acc -> bet_cancel_whole(bet_id) end)
    updated_market_info = %{ name: market_info[:name],
                             description: market_info[:description],
                             status: :cancelled}
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
    get_bets = List.foldl(backs, [], fn bet_id, acc -> BetUnfair.extract_info_bet(bet_id, acc) end)
    {:reply, {:ok, List.keysort(get_bets,0)}, %{market: market_info, backs: backs, lays: lays}}
  end

  def handle_call(:market_pending_lays, _from, %{market: market_info, backs: backs, lays: lays}) do
    get_bets = List.foldl(lays, [], fn bet_id, acc -> BetUnfair.extract_info_bet(bet_id, acc) end)
    {:reply, {:ok, List.keysort(get_bets,0)}, %{market: market_info, backs: backs, lays: lays}}
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
    if bet == :nil do
      bet_infos = %{ bet_type: bet_type,
                     market_id: market_id,
                     user_id: user_id,
                     odds: odds,
                     original_stake: stake, # original stake
                     remaining_stake: stake, # non-matched stake
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
        {:reply ,:ok, market_infos} # if there is no bet to cancel, ok
      bet ->
        # if there is a bet, we cancel it and return the stake to the user.
        updated_bet = %{ bet_type: bet[:bet_type],
                         market_id: bet[:market_id],
                         user_id: bet[:user_id],
                         odds: bet[:odds],
                         original_stake: bet[:original_stake], # original stake
                         remaining_stake: bet[:remaining_stake], # non-matched stake
                         matched_bets: bet[:matched_bets], # list of matched bets
                         status: :cancelled
                      }
        Process.put(bet_id, updated_bet)
		    {:reply , bet[:remaining_stake], market_infos}
	  end
  end

  def handle_call({:bet_cancel_whole, bet_id}, _from, market_infos) do
    case Process.get(bet_id) do
      :nil ->
        {:reply, :ok, market_infos} # if there is no bet to cancel, ok
      bet ->
        # if there is a bet, we cancel it and return the stake to the user.
        updated_bet = %{ bet_type: bet[:bet_type],
                         market_id: bet[:market_id],
                         user_id: bet[:user_id],
                         odds: bet[:odds],
                         original_stake: bet[:original_stake], # original stake
                         remaining_stake: bet[:original_stake], # non-matched stake
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

  def handle_call({:bet_settle, bet_id}, _from, market_infos) do
    bet = Process.get(bet_id)
    if bet == :nil do
      {:reply, {:error, :nil}, market_infos}
    else
      {:reply, {:ok, bet[:odds]*bet[:original_stake]+bet[:remaining_stake]}, market_infos}
    end
  end

  def extract_info_bet(bet_id, acc) do
    bet_infos = Process.get(bet_id)
    if bet_infos[:matched_bets] == [] do
      [{bet_infos[:odds], bet_id} | acc]
    else
      acc
    end
  end

  def matching_algorithm(backs, lays) do
    case {backs, lays} do
      {[], _} -> :ok
      {_, []} -> :ok
      {[hbacks | tbacks], [hlays | tlays]} ->
        get_back = Process.get(hbacks)
        get_lay = Process.get(hlays)
        if get_back[:status] != :active || get_back[:remaining_stake] == 0 do
          matching_algorithm(tbacks, lays)
        end
        if get_lay[:status] != :active || get_lay[:remaining_stake] == 0 do
          matching_algorithm(backs, tlays)
        end
        if get_back[:odds] <= get_lay[:odds] do
          # There's a match !
          allowed_to_loose = get_back[:remaining_stake]*get_back[:odds]-get_back[:remaining_stake]
          if allowed_to_loose >= get_lay[:remaining_stake] do
            # We consume all of the lay stake
            updated_lay = %{ bet_type: get_lay[:bet_type],
                             market_id: get_lay[:market_id],
                             user_id: get_lay[:user_id],
                             odds: get_lay[:odds],
                             original_stake: get_lay[:original_stake], # original stake
                             remaining_stake: 0, # non-matched stake
                             matched_bets: [ hbacks | get_lay[:matched_bets]], # list of matched bets
                             status: :active
                            }
            updated_back = %{ bet_type: get_back[:bet_type],
                              market_id: get_back[:market_id],
                              user_id: get_back[:user_id],
                              odds: get_back[:odds],
                              original_stake: get_back[:original_stake], # original stake
                              remaining_stake: get_back[:remaining_stake]-get_lay[:remaining_stake], # non-matched stake
                              matched_bets: [ hlays | get_back[:matched_bets]], # list of matched bets
                              status: :active
                            }
            Process.put(hlays, updated_lay)
            Process.put(hbacks, updated_back)
            matching_algorithm(backs, tlays)
          else
            # We consume all of the backing stake
            updated_lay = %{ bet_type: get_lay[:bet_type],
                             market_id: get_lay[:market_id],
                             user_id: get_lay[:user_id],
                             odds: get_lay[:odds],
                             original_stake: get_lay[:original_stake], # original stake
                             remaining_stake: get_lay[:remaining_stake]-get_back[:remaining_stake], # non-matched stake
                             matched_bets: [ hbacks | get_lay[:matched_bets]], # list of matched bets
                             status: :active
                            }
            updated_back = %{ bet_type: get_back[:bet_type],
                              market_id: get_back[:market_id],
                              user_id: get_back[:user_id],
                              odds: get_back[:odds],
                              original_stake: get_back[:original_stake], # original stake
                              remaining_stake: 0, # non-matched stake
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
