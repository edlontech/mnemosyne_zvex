defmodule MnemosyneZvex.ErrorsTest do
  use ExUnit.Case, async: true

  alias Mnemosyne.Errors.Framework.AdapterError
  alias Mnemosyne.Errors.Framework.NotFoundError
  alias Mnemosyne.Errors.Framework.StorageError
  alias MnemosyneZvex.Errors
  alias Zvex.Error.Conflict.AlreadyExists
  alias Zvex.Error.Internal.InternalError
  alias Zvex.Error.Invalid.Argument
  alias Zvex.Error.Invalid.FailedPrecondition
  alias Zvex.Error.NotFound.NotFound, as: ZvexNotFound
  alias Zvex.Error.Unknown.Unknown

  describe "translate/2" do
    test "Invalid.Argument -> StorageError(:invalid_argument)" do
      err = Argument.exception(message: "bad")

      assert %StorageError{operation: :apply_changeset, reason: {:invalid_argument, "bad"}} =
               Errors.translate(err, :apply_changeset)
    end

    test "Invalid.FailedPrecondition -> StorageError(:precondition_failed)" do
      err = FailedPrecondition.exception(message: "closed")

      assert %StorageError{reason: {:precondition_failed, "closed"}} =
               Errors.translate(err, :get_node)
    end

    test "NotFound -> NotFoundError(:node, id)" do
      err = ZvexNotFound.exception(message: "abc")
      assert %NotFoundError{resource: :node, id: "abc"} = Errors.translate(err, :get_node)
    end

    test "Conflict.AlreadyExists -> StorageError(:already_exists)" do
      err = AlreadyExists.exception(message: "dup")

      assert %StorageError{reason: {:already_exists, "dup"}} =
               Errors.translate(err, :apply_changeset)
    end

    test "Unavailable.* -> AdapterError" do
      for {struct, tag} <- [
            {Zvex.Error.Unavailable.PermissionDenied, :permission_denied},
            {Zvex.Error.Unavailable.ResourceExhausted, :resource_exhausted},
            {Zvex.Error.Unavailable.Unavailable, :unavailable},
            {Zvex.Error.Unavailable.NotSupported, :not_supported}
          ] do
        err = struct.exception(message: "x")

        assert %AdapterError{adapter: :mnemosyne_zvex, reason: {^tag, "x"}} =
                 Errors.translate(err, :find_candidates)
      end
    end

    test "Internal.InternalError -> AdapterError(:internal)" do
      err = InternalError.exception(message: "boom")

      assert %AdapterError{reason: {:internal, "boom"}} =
               Errors.translate(err, :delete_nodes)
    end

    test "Unknown.Unknown -> AdapterError(:unknown)" do
      err = Unknown.exception(message: "?")
      assert %AdapterError{reason: {:unknown, "?"}} = Errors.translate(err, :init)
    end

    test "{:dets_error, reason} -> StorageError(:sidecar, reason)" do
      assert %StorageError{reason: {:sidecar, :enoent}} =
               Errors.translate({:dets_error, :enoent}, :init)
    end

    test "anything else -> AdapterError with raw reason" do
      assert %AdapterError{reason: {:weird, 1}} = Errors.translate({:weird, 1}, :init)
    end
  end
end
