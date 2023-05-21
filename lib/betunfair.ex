defmodule BetUnfair do
  @moduledoc """
  Documentation for `BetUnfair`.
  """
  use GenServer

  @type user_id :: String.t()
  @type bet :: String.t()
  @type users :: [{user :: user_id(), balance :: integer}]
  # A market is defined by it's users registered and the
  # participants to a bet
  @type market :: {users(), %{bet() => users()}}

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

      iex> Betunfair.start_link("Futball")
      {:ok, %{}}

  """
  @spec start_link(name :: String.t()) :: {:ok, market()}
  def start_link(name) do
    {:ok, market_pid} = GenServer.start_link(BetUnfair, {[],%{}})
    Process.put(:market_server, market_pid)
    Process.put(name, market_pid)
    {:ok, market_pid}
  end

  @doc """
  GenServer function associated to start_link.
  Initialize the GenServer state.
  """
  @spec init(market :: market()) :: {:ok, market()}
  def init(market) do
    {:ok, market}
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

      iex> Betunfair.clean("Futball")
      :ok

  """
  @spec clean(name :: String.t()):: :ok
  def clean(name) do
    GenServer.stop(Process.get(name))
    Process.delete(name)
    :ok
  end

  ##########################
  #### User interaction ####
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

      iex> Betunfair.create_user("Alice","Futball")
      {:ok, "Alice"}
      iex> Betunfair.create_user("Alice","Futball")
      {:error, "Alice"}

  """
  @spec user_create(id :: String.t(), name :: String.t()) :: {:ok | :error, user_id()}
  def user_create(id, name) do
    market_pid = Process.get(name)
    GenServer.call(market_pid, {:user_create, id})
  end

  @doc """
  GenServer function associated to user_create.
  Adds a user to the exchange state.
  """
  def handle_call({:user_create, id}, _from, {users, bets}) do
    previous = List.keyfind(users, id, 0)
    if previous == :nil do
      {:reply, {:ok, id}, {[{id, 0} | users], bets}}
    else
      # The user already exists
      {:reply, {:error, id}, {users, bets}}
    end
  end

  @doc """
  Adds amount (should be positive) to the user account.

  ## Parameters
    - id, the string that identifies the user
    - amount, the amount to deposit

  ## Examples

      iex> Betunfair.user_deposit("Alice",15)
      {:ok, 15}
      iex> Betunfair.create_user("Alice",-1)
      {:error, 15}

  """
  @spec user_deposit(id :: user_id(), amount :: integer()):: :ok | :error
  def user_deposit(id, amount) do
    market_pid = Process.get(name)
    GenServer.call(market_pid, {:user_deposit, id})
  end

  @doc """
  GenServer function associated to user_deposit.
  Adds an amount of money to the user balance.
  """
  def handle_call({:user_deposit, id, amount}, _from, {users, bets}) do
    previous = List.keyfind(users, id, 0)
    if previous == :nil or amount < 0 do
      # The user do not exist
      {:reply, :error, {users, bets}}
    else
      new_amount = elem(previous,1)+amount
      updated_users = List.keyreplace(users, id, 0, {id, new_amount})
      {:reply, :ok, {updated_users, bets}}
    end
  end

end
