defmodule Torchx.DeviceTest do
  use ExUnit.Case, async: true

  alias Torchx.Backend, as: TB

  setup do
    Nx.default_backend(Torchx.Backend)
    :ok
  end

  if Torchx.device_available?(:cuda) do
    @device {:cuda, 0}
  else
    @device :cpu
  end

  describe "creation" do
    test "from_binary" do
      t = Nx.tensor([1, 2, 3], backend: {TB, device: @device})
      assert TB.device(t) == @device
    end

    test "tensor" do
      t = Nx.tensor(7.77, backend: {TB, device: @device})
      assert TB.device(t) == @device
    end
  end

  describe "backend_transfer" do
    test "to" do
      t = Nx.tensor([1, 2, 3])
      td = Nx.backend_transfer(t, {TB, device: @device})
      assert TB.device(td) == @device
    end

    test "from" do
      t = Nx.tensor([1, 2, 3], backend: {TB, device: @device})
      Nx.backend_transfer(t)
      assert Nx.backend_transfer(t) == Nx.tensor([1, 2, 3], backend: Nx.BinaryBackend)

      # TODO: we need to raise once the data has been transfered once
      # assert_raise ArgumentError, fn -> Nx.backend_transfer(t) end
    end
  end
end
