defmodule Torchx.Macro do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      import unquote(__MODULE__)
      Module.register_attribute(Torchx, :torch_function, accumulate: true)
    end
  end

  @doc """
  Function that receives a device and allocates a tensor.
  """
  defmacro defcreate(call) do
    {name, args} = Macro.decompose_call(call)

    unless has_device?(args) do
      raise("At least one argument of defcreate function should be named 'device'.")
    end

    quote do
      @torch_function {unquote(name), unquote(length(args))}
      def unquote(name)(unquote_splicing(args)) do
        {user_device, index} = normalize_device!(var!(device))
        var!(device) = torch_device!(user_device, index)

        case user_device do
          :cpu -> Torchx.NIF.unquote(:"#{name}_cpu")(unquote_splicing(args))
          _ -> Torchx.NIF.unquote(:"#{name}_io")(unquote_splicing(args))
        end
        |> unwrap_tensor!(user_device)
      end
    end
  end

  @doc """
  Generates a call that returns a tensor (or a tuple/list of tensors).

  All tensor variables must start with the name tensor.
  """
  defmacro deftensor(call) do
    defcall(call, :unwrap_tensor!, [Macro.var(:device, __MODULE__)])
  end

  @doc """
  Generates a call that returns a value (not a tensor).

  All tensor variables must start with the name tensor.
  """
  defmacro defvalue(call) do
    defcall(call, :unwrap!, [])
  end

  defp defcall(call, unwrapper, extra) do
    {name, args} = Macro.decompose_call(call)

    tensors = Enum.filter(args, fn {name, _, _} ->
      match?("tensor", Atom.to_string(name))
    end)

    quote do
      @torch_function {unquote(name), unquote(length(args))}
      def unquote(name)(unquote_splicing(args)) do
        {unquote(tensors), device} = prepare_tensors!(unquote(tensors))

        case device do
          :cpu -> Torchx.NIF.unquote(:"#{name}_cpu")(unquote_splicing(args))
          device -> Torchx.NIF.unquote(:"#{name}_io")(unquote_splicing(args))
        end
        |> unquote(unwrapper)(unquote_splicing(extra))
      end
    end
  end

  defp has_device?(args) do
    Enum.any?(args, &match?({:device, _, nil}, &1))
  end
end

defmodule Torchx do
  # TODO: Add moduledoc that documents the types and devices.
  # Make it clear they are Torchx specific and that Torchx.Backend
  # provides the mapping between Nx to the underlying Torchx types.

  # TODO: Automatically download libtorch like we do for esbuild/xla.

  use Torchx.Macro
  alias Torchx.NIF

  @doc """
  Check if device of the given type is available for Torchx.
  Device atom can be any of:

    * :cpu
    * :cuda
    * :mkldnn
    * :opengl
    * :opencl
    * :ideep
    * :hip
    * :fpga
    * :msnpu
    * :xla
    * :vulkan
    * :metal
    * :xpu

  But only :cuda availability check is supported for now.
  """
  def device_available?(:cuda), do: NIF.cuda_is_available()
  def device_available?(:cpu), do: true
  def device_available?(_), do: raise("Only CUDA device availability check is supported for now.")

  @doc """
  Return devices quantity for the given device type. Only :cuda is supported for now.
  """
  def device_count(:cuda), do: NIF.cuda_device_count()
  def device_count(_), do: raise("Only CUDA devices can be counted for now.")

  # LibTorch API bindings

  ## Creation / conversion

  defcreate randint(min, max, shape, type, device)
  defcreate rand(min, max, shape, type, device)
  defcreate normal(mu, sigma, shape, type, device)

  defcreate arange(from, to, step, type, device)
  defcreate arange(from, to, step, type, device, shape)
  defcreate full(shape, scalar, type, device)
  defcreate scalar_tensor(scalar, type, device)
  defcreate ones(shape, type, device)
  defcreate eye(size, type, device)
  defcreate from_blob(blob, shape, type, device)
  defcreate to_device(tensor, device)

  ## Manipulation

  deftensor reshape(tensor, shape)
  deftensor to_type(tensor, type)
  deftensor squeeze(tensor)
  deftensor squeeze(tensor, axis)
  deftensor broadcast_to(tensor, shape)
  deftensor transpose(tensor, dim0, dim1)
  deftensor permute(tensor, dims)
  deftensor split(tensor, split_size)
  deftensor narrow(tensor, dim, start, length)
  deftensor as_strided(tensor, size, strides, offset)

  ## Aggregation

  deftensor sum(tensor, axes, keep_axes)
  deftensor argmax(tensor, axis, keep_axes)
  deftensor argmin(tensor, axis, keep_axes)

  ## Operations

  ### Binary

  deftensor add(tensorA, tensorB)
  deftensor subtract(tensorA, tensorB)
  deftensor multiply(tensorA, tensorB)
  deftensor power(tensorA, tensorB)
  deftensor remainder(tensorA, tensorB)
  deftensor divide(tensorA, tensorB)
  deftensor atan2(tensorA, tensorB)
  deftensor min(tensorA, tensorB)
  deftensor max(tensorA, tensorB)
  deftensor quotient(tensorA, tensorB)

  deftensor left_shift(tensorA, tensorB)
  deftensor right_shift(tensorA, tensorB)

  deftensor equal(tensorA, tensorB)
  deftensor not_equal(tensorA, tensorB)
  deftensor greater(tensorA, tensorB)
  deftensor less(tensorA, tensorB)
  deftensor greater_equal(tensorA, tensorB)
  deftensor less_equal(tensorA, tensorB)

  deftensor logical_and(tensorA, tensorB)
  deftensor logical_or(tensorA, tensorB)
  deftensor logical_xor(tensorA, tensorB)

  deftensor bitwise_and(tensorA, tensorB)
  deftensor bitwise_or(tensorA, tensorB)
  deftensor bitwise_xor(tensorA, tensorB)

  deftensor outer(tensorA, tensorB)
  deftensor tensordot(tensorA, tensorB, axesA, axesB)
  deftensor matmul(tensorA, tensorB)

  ### Unary

  deftensor exp(tensor)
  deftensor expm1(tensor)
  deftensor log(tensor)
  deftensor log1p(tensor)
  deftensor logistic(tensor)
  deftensor cos(tensor)
  deftensor sin(tensor)
  deftensor tan(tensor)
  deftensor cosh(tensor)
  deftensor sinh(tensor)
  deftensor tanh(tensor)
  deftensor acos(tensor)
  deftensor asin(tensor)
  deftensor atan(tensor)
  deftensor acosh(tensor)
  deftensor asinh(tensor)
  deftensor atanh(tensor)
  deftensor sqrt(tensor)
  deftensor rsqrt(tensor)
  deftensor cbrt(tensor)
  deftensor erf(tensor)
  deftensor erfc(tensor)
  deftensor erf_inv(tensor)

  deftensor abs(tensor)
  deftensor bitwise_not(tensor)
  deftensor ceil(tensor)
  deftensor floor(tensor)
  deftensor negate(tensor)
  deftensor round(tensor)
  deftensor sign(tensor)

  ## Transformations

  deftensor cholesky(tensor)
  deftensor cholesky(tensor, upper)
  deftensor qr(tensor)
  deftensor qr(tensor, reduced)

  ## Return values

  defvalue to_blob(tensor)
  defvalue to_blob(tensor, limit)
  defvalue delete_tensor(tensor)

  ## Utils

  # TODO: make them public
  # TODO: confirm they are all CPU based (if not, move to defvalue)

  @doc false
  def type_of({_device, ref}), do: NIF.scalar_type(ref) |> unwrap!()

  @doc false
  def shape_of({_device, ref}), do: NIF.shape(ref) |> unwrap!()

  @doc false
  def item({_device, ref}), do: NIF.item(ref) |> unwrap!()

  @doc false
  def nbytes({_device, ref}), do: NIF.nbytes(ref) |> unwrap!()

  @doc false
  def to_blob_view({_device, ref}), do: NIF.to_blob_view(ref) |> unwrap!()

  ## Reflection

  @doc false
  def __torch__, do: @torch_function

  ## Macro callbacks

  @devices %{
    cpu: 0,
    cuda: 1,
    mkldnn: 2,
    opengl: 3,
    opencl: 4,
    ideep: 5,
    hip: 6,
    fpga: 7,
    msnpu: 8,
    xla: 9,
    vulkan: 10,
    metal: 11,
    xpu: 12
  }

  defp normalize_device!({device, index}) when is_atom(device) and is_integer(index),
    do: {device, index}

  defp normalize_device!(device) when is_atom(device),
    do: {device, -1}

  defp normalize_device!(device),
    do: raise ArgumentError, "expected device to be {atom, index} or atom, got: #{device}"

  defp torch_device!(device, index) do
    id = @devices[device] || raise ArgumentError, "unknown device #{inspect(device)}"
    {id, index}
  end

  defp unwrap!({:ok, result}), do: result
  defp unwrap!({:error, error}), do: raise("Torchx: " <> List.to_string(error))

  defp unwrap_tensor!(tagged_result, device) do
    case unwrap!(tagged_result) do
      ref when is_reference(ref) ->
        {device, ref}

      list when is_list(list) ->
        Enum.map(list, &{device, &1})

      tuple when is_tuple(tuple) ->
        tuple |> Tuple.to_list() |> Enum.map(&{device, &1}) |> List.to_tuple()
    end
  end

  defp prepare_tensors!(tensors) do
    Enum.map_reduce(tensors, nil, fn
      {dev, ref}, nil when is_atom(dev) and is_reference(ref) ->
        {ref, dev}

      {dev, ref}, dev when is_atom(dev) and is_reference(ref) ->
        {ref, dev}

      {dev, ref}, other_dev  when is_atom(dev) and is_reference(ref) ->
        raise ArgumentError, "cannot perform operation across devices #{dev} and #{other_dev}"

      bad_tensor, _dev ->
        raise ArgumentError, "expected a Torchx tensor, got: #{inspect(bad_tensor)}"
    end)
  end
end
