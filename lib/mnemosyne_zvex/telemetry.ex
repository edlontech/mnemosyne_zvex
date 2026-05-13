defmodule MnemosyneZvex.Telemetry do
  @moduledoc false

  @prefix [:mnemosyne_zvex]

  @spec span(atom() | [atom()], map(), (-> {result, map()})) :: result when result: var
  def span(event, metadata, fun) do
    name = @prefix ++ List.wrap(event)
    :telemetry.span(name, metadata, fn -> fun.() end)
  end
end
