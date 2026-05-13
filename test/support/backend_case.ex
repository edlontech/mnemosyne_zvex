defmodule MnemosyneZvex.BackendCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      @moduletag :tmp_dir
      import MnemosyneZvex.Fixtures
      import MnemosyneZvex.BackendCase
    end
  end

  setup %{tmp_dir: tmp_dir} = ctx do
    opts =
      [path: tmp_dir, dimension: 8, fetch_multiplier: 4]
      |> Keyword.merge(Map.get(ctx, :backend_opts, []))

    {:ok, state} = MnemosyneZvex.Backend.init(opts)
    on_exit(fn -> :ok = MnemosyneZvex.Backend.close(state) end)
    %{state: state, tmp_dir: tmp_dir}
  end
end
