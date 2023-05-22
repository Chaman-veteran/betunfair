defmodule BetUnfair do
  @moduledoc """
  Documentation for `BetUnfair`.
  """
  use GenServer

  @type user_id :: String.t()
  @type bet_id :: String.t()
  @type users :: %{id :: user_id() => {user :: String.t(), balance :: integer, [bet_id()]}}
  # A market is defined by the participants to a bet
  @type market :: %{bet_id() => users()}

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

      iex> Betunfair.start_link(Futbol)
      {:ok, %{}}

  """
  @spec start_link(name :: String.t()) :: {:ok, market()}
  def start_link(name) do
    if Process.get(name) == :nil do
      {:ok, market_pid} = GenServer.start_link(BetUnfair, %{})
      Process.put(:market_server, market_pid)
      Process.put(name, market_pid)
      {:ok, market_pid}
    else
      # TODO : recover the existing data
    end
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

      iex> Betunfair.clean(Futbol)
      :ok

  """
  @spec clean(name :: String.t()):: :ok
  def clean(name) do
    GenServer.stop(Process.get(name))
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

      iex> Betunfair.create_user(Alice,Alice99)
      {:ok, Alice}
      iex> Betunfair.create_user(Alice,Alice01)
      {:error, Alice}

  """
  @spec user_create(id :: String.t(), name :: String.t()) :: {:ok | :error, user_id()}
  def user_create(id, name) do
    users = Process.get(:users, %{})
    if Map.has_key?(users,id) do
      # The user already exists
      {:error, id}
    else
      updated_users = Map.put(users, id, {name, 0, []})
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

      iex> Betunfair.user_deposit(Alice,15)
      :ok
      iex> Betunfair.create_user(Alice,-1)
      :error

  """
  @spec user_deposit(id :: user_id(), amount :: integer()):: :ok | :error
  def user_deposit(id, amount) do
    users = Process.get(:users)
    user = Map.fetch(users, id)
    if user == :nil or amount < 0 do
      # The user do not exist
      :error
    else
      new_amount = elem(user,1)+amount
      updated_users = Map.replace(users, id, {elem(user,0), new_amount, elem(user,2)})
      Process.put(:users, updated_users)
      :ok
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

      iex> Betunfair.user_deposit(Alice,15)
      :ok
      iex> Betunfair.create_user(Alice,-1)
      :error
      iex> Betunfair.create_user(Alice,20)
      :ok

  """
  @spec user_withdraw(id :: user_id(), amount :: integer()):: :ok | :error
  def user_withdraw(id, amount) do
    users = Process.get(:users)
    user = Map.fetch(users, id)
    # Remark : we use the laziness of the or to call elem
    if user == :nil or amount > elem(user,0) do
      # The user do not exist
      :error
    else
      new_amount = elem(user,1)-amount
      updated_users = Map.replace(users, id, {elem(user,0), new_amount, elem(user,2)})
      Process.put(:users, updated_users)
      :ok
    end
  end

  @doc """
  Retrieves information about a user.

  ## Parameters
    - id, the string that identifies the user

  ## Examples

      iex> Betunfair.user_get(Alice, 15)
      {:ok, %{Alice, Alice01, 15}}

  """
  @spec user_get(id :: user_id()) ::
          {:ok, %{name: String.t(), id: user_id(), balance: integer()}} | {:error}
  ## Remark : error in the stated signature ?? Shouldn't it be {:ok, {...}} instead of {:ok, %{...}}
  def user_get(id) do
    users = Process.get(:users)
    user = Map.fetch(users, id)
    if user == :nil do
      {:error}
    else
      {:ok, {elem(user,0), id, elem(user,1), elem(user,2)}}
    end
  end

  @doc """
  Returns an enumerable containing all bets of the user.

  ## Parameters
    - id, the string that identifies the user

  ## Examples

      iex> Betunfair.user_get(Alice,15)
      [Madrid - Barca, Paris - Marseille]

  """
  @spec user_bets(id :: user_id()) :: Enumerable.t(bet_id())
  def user_bets(id) do
    users = Process.get(:users)
    user = Map.fetch(users, id)
    if user == :nil do
      []
    else
      elem(user,2)
    end
  end

end
