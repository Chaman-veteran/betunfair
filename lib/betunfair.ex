defmodule BetUnfair do
  @moduledoc """
  Documentation for `BetUnfair`.
  """
  use GenServer

  @type bet :: String.t()
  @type participants :: list
  @type market :: tuple

  #### EXCHANGES INTERACTIONS ####

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
  @spec start_link(name :: String.t()) :: {:ok, market}
  def start_link(name) do
    # Remark :
    {:ok, market_pid} = GenServer.start_link(BetUnfair, %{})
    Process.put(:market_server, market_pid)
    Process.put(name, market_pid)
    {:ok, market_pid}
  end

  @doc """
  Initialize the GenServer state.

  ## Parameters
    - market, the initial state of the market

  ## Examples

      iex> Betunfair.init(%{})
      {:ok, %{}}

  """
  @spec init(market :: market) :: {:ok, market}
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

end
