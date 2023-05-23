defmodule BetUnfair do
  @moduledoc """
  Documentation for `BetUnfair`.
  """
  use GenServer

  # GenServer is used for markets :
  # each market runs with a unique pid & server
  # in order to increase scalability of market places
  # The users are linked to the whole system and as such
  # are "stored" using the main module along with the Process module

  @type user_id :: String.t()
  @type bet_id :: String.t()
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
  @type market_place :: {market, %{bet_id() => bet()}}

  ################################
  #### EXCHANGES INTERACTIONS ####
  ################################

  @doc """
  Start of the exchange place.
  If an exchange name does not already exist it is created.
  If it exists the existing data (markets, bets,users) is recovered.

  ## Parameters
    - name, which is the name of the market created

  ## Examples

      iex> Betunfair.start_link("Futbol")
      {:ok, %{}}

  """
  @spec start_link(name :: String.t()) :: {:ok, market_place()}
  def start_link(name) do
    if Process.get(name) == :nil do
      market_create(name, :nil)
    else
      # TODO : recover the existing data
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

      iex> Betunfair.clean("Futbol")
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
      ["Madrid - Barca", "Paris - Marseille"]

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

      iex> Betunfair.market_create("Futbol", "Market place for futbol bets")
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
    market_info = %{name: name, description: description, statu: :active}
    {:ok, %{market_info, %{}}}
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
      receive do _reply -> :ok end
    end
  end

  @doc """
  GenServer function associated with market_cancel
  """
  def handle_call(:market_cancel, _from, {market_info, bets}) do
    # We could use map but it may be executed in //
    # and if so, it could give weird results
    # (one bet cancel may overwrite another that's in //)
    list_bets = Map.keys(bets)
    List.foldl(list_bets, :nil, fn bet_id -> bet_cancel_all(bet_id) end)
    updated_market_info = %{ name: market_info[:name]
                           , description: market_info[:description]
                           , satus: :cancelled}
    {reply, :ok, {updated_market_info, %{}}}
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
      receive do _reply -> :ok end
    end
  end

  @doc """
  GenServer function associated with market_cancel
  """
  def handle_call(:market_freeze, _from, {market_info, bets}) do
    list_bets = Map.keys(bets)
    ## TODO : delete un-matched bets from bets and cancel them
    ## using the same fold as before
    ## and then return the new market
  end


end
