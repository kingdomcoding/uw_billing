defmodule UwBilling.Release do
  @app :uw_billing

  def create_db do
    load_app()

    for repo <- repos() do
      case repo.__adapter__().storage_up(repo.config()) do
        :ok -> :ok
        {:error, :already_up} -> :ok
        {:error, term} -> raise "Could not create database: #{inspect(term)}"
      end
    end
  end

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  def seed do
    start_app()
    eval_priv(["repo", "seeds.exs"])
    eval_priv(["scripts", "setup_stripe.exs"])
    :ok
  end

  defp eval_priv(path_parts) do
    [:code.priv_dir(@app) | path_parts]
    |> Path.join()
    |> Code.eval_file()
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)
  defp load_app, do: Application.load(@app)
  defp start_app, do: Application.ensure_all_started(@app)
end
