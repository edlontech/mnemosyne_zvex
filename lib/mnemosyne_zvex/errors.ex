defmodule MnemosyneZvex.Errors do
  @moduledoc """
  Translates `Zvex.Error.*` and DETS error tuples into the
  `Mnemosyne.Errors.Framework.*` hierarchy used by `Mnemosyne.GraphBackend`
  callbacks.
  """

  alias Mnemosyne.Errors.Framework.AdapterError
  alias Mnemosyne.Errors.Framework.NotFoundError
  alias Mnemosyne.Errors.Framework.StorageError

  @adapter :mnemosyne_zvex

  @doc """
  Translates a Zvex error struct or a DETS error reason into a Mnemosyne error.

  Operation is a free-form atom describing the failing callback
  (`:apply_changeset`, `:get_node`, ...).
  """
  @spec translate(term(), atom()) :: Mnemosyne.Errors.error()
  def translate(%Zvex.Error.Invalid.Argument{} = e, op),
    do: StorageError.exception(operation: op, reason: {:invalid_argument, e.message})

  def translate(%Zvex.Error.Invalid.FailedPrecondition{} = e, op),
    do: StorageError.exception(operation: op, reason: {:precondition_failed, e.message})

  def translate(%Zvex.Error.NotFound.NotFound{} = e, _op),
    do: NotFoundError.exception(resource: :node, id: e.message)

  def translate(%Zvex.Error.Conflict.AlreadyExists{} = e, op),
    do: StorageError.exception(operation: op, reason: {:already_exists, e.message})

  def translate(%Zvex.Error.Unavailable.PermissionDenied{} = e, op),
    do:
      AdapterError.exception(
        adapter: @adapter,
        operation: op,
        reason: {:permission_denied, e.message}
      )

  def translate(%Zvex.Error.Unavailable.ResourceExhausted{} = e, op),
    do:
      AdapterError.exception(
        adapter: @adapter,
        operation: op,
        reason: {:resource_exhausted, e.message}
      )

  def translate(%Zvex.Error.Unavailable.Unavailable{} = e, op),
    do:
      AdapterError.exception(
        adapter: @adapter,
        operation: op,
        reason: {:unavailable, e.message}
      )

  def translate(%Zvex.Error.Unavailable.NotSupported{} = e, op),
    do:
      AdapterError.exception(
        adapter: @adapter,
        operation: op,
        reason: {:not_supported, e.message}
      )

  def translate(%Zvex.Error.Internal.InternalError{} = e, op),
    do: AdapterError.exception(adapter: @adapter, operation: op, reason: {:internal, e.message})

  def translate(%Zvex.Error.Unknown.Unknown{} = e, op),
    do: AdapterError.exception(adapter: @adapter, operation: op, reason: {:unknown, e.message})

  def translate({:dets_error, reason}, op),
    do: StorageError.exception(operation: op, reason: {:sidecar, reason})

  def translate(other, op),
    do: AdapterError.exception(adapter: @adapter, operation: op, reason: other)
end
