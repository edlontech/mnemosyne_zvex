defmodule MnemosyneZvex do
  @moduledoc """
  Mnemosyne graph-backend adapter backed by Zvex (vector index) and DETS
  (links + mutable metadata).

  Use it by configuring `Mnemosyne` with `{MnemosyneZvex.Backend, opts}`:

      Mnemosyne.open_repo("my-project",
        backend: {MnemosyneZvex.Backend,
          path: "/var/data/mnemosyne/my-project",
          dimension: 1536})

  See `MnemosyneZvex.Backend` for the full options list.
  """
end
