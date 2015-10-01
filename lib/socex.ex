defmodule Socex do
  use Application
  use Silverb
  use Logex,  [ttl: 100]
  use Tinca , [
                :users_names,
                :curstate
              ]

  defp logex_error(_) do
    IO.write(Socex.Shell.prompt)
  end
  defp logex_warn(_) do
    IO.write(Socex.Shell.prompt)
  end
  defp logex_notice(_) do
    IO.write(Socex.Shell.prompt)
  end

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false
    Tinca.declare_namespaces

    children = [
      # Define workers and child supervisors to be supervised
      # worker(Socex.Worker, [arg1, arg2, arg3]),
      worker(Socex.Api, [])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Socex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defstruct state: "menu",
            dialogs: [],
            current_dialog: nil,
            messages: [],
            stamp: 0
end
use Hashex, [Socex]
