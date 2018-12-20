defmodule ResxDropbox.Utility do
    @moduledoc """
      ## Dropbox Content Hash

      This module provides an implementation of the [Dropbox Content Hash](https://www.dropbox.com/developers/reference/content-hash).
      For use externally or with `Resx.Resource`.
    """

    @type algos :: :crypto.sha1 | :crypto.sha2 | :crypto.sha3 | :crypto.compatibility_only_hash | :ripemd160
    @type state :: { algos, binary, binary }

    @block_size 4 * 1024 * 1024

    @doc """
      Initializes the context for streaming hash operations following the dropbox
      content hashing algorithm.

      By default the algorithm used is `:sha256` as this is the current one used
      by dropbox, this however can be overridden.

      The state can then be passed to `hash_update/2` and `hash_final/1`.

        iex> ResxDropbox.Utility.hash_init |> ResxDropbox.Utility.hash_update("foo") |> ResxDropbox.Utility.hash_update("bar") |> ResxDropbox.Utility.hash_final
        "3f2c7ccae98af81e44c0ec419659f50d8b7d48c681e5d57fc747d0461e42dda1"

        iex> ResxDropbox.Utility.hash_init |> ResxDropbox.Utility.hash_final
        "5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456"
    """
    @spec hash_init(algos) :: state
    def hash_init(algo \\ :sha256) do
        { algo, <<>>, <<>> }
    end

    @doc """
      Updates the digest represented by state using the given data. State must have
      been generated using `hash_init/1` or a previous call to this function. Data
      can be any length. New state must be passed into the next call to `hash_update/2`
      or `hash_final/1`.
    """
    @spec hash_update(state, iodata) :: state
    def hash_update(state, []), do: state
    def hash_update(state, [data|list]), do: hash_update(state, data) |> hash_update(list)
    def hash_update({ algo, <<block :: binary-size(@block_size), chunks :: binary>>, hashes }, data), do: hash_update({ algo, chunks <> data, hashes <> :crypto.hash(algo, block) }, <<>>)
    def hash_update(state, <<>>), do: state
    def hash_update({ algo, chunks, hashes }, data), do: hash_update({ algo, chunks <> data, hashes }, <<>>)

    @doc """
      Finalizes the hash operation referenced by state returned from a previous call
      to `hash_update/2`. The digest will be encoded as a lowercase hexadecimal string
      as required by the dropbox content hashing algorithm.
    """
    @spec hash_final(state) :: String.t
    def hash_final({ algo, <<block :: binary-size(@block_size), chunks :: binary>>, hashes }), do: hash_final({ algo, chunks, hashes <> :crypto.hash(algo, block) })
    def hash_final({ algo, block, hashes }) do
        hashes = hashes <> :crypto.hash(algo, block)
        :crypto.hash(algo, hashes) |> Base.encode16(case: :lower)
    end

    @doc """
      Hash the content following the dropbox content hashing algorithm.

      By default the algorithm used is `:sha256` as this is the current one used
      by dropbox, this however can be overridden.

        iex> ResxDropbox.Utility.hash("foobar")
        "3f2c7ccae98af81e44c0ec419659f50d8b7d48c681e5d57fc747d0461e42dda1"

        iex> ResxDropbox.Utility.hash("")
        "5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456"

        iex> ResxDropbox.Utility.hash(:sha, "foobar")
        "9b500343bc52e2911172eb52ae5cf4847604c6e5"

        iex> ResxDropbox.Utility.hash(["f", "", [[[[["oo"], [["b"]]], ""], ""], "a"], [[],[]], ["r"]])
        ResxDropbox.Utility.hash("foobar")

        iex> ResxDropbox.Utility.hash([])
        ResxDropbox.Utility.hash("")
    """
    @spec hash(algos, iodata) :: String.t
    def hash(algo \\ :sha256, data), do: hash_init(algo) |> hash_update(data) |> hash_final

    @doc """
      A resx resource hasher for the dropbox content hashing algorithm.

      Generally you'll want to use the `streamable_hasher/1` instead.

      This can be applied globally as follows:

        config :resx,
            hash: ResxDropbox.hasher

      Or on individual resources:

        iex> Resx.Resource.open!("data:,foobar") |> Resx.Resource.hash(ResxDropbox.Utility.hasher)
        { :dropbox, ResxDropbox.Utility.hash("foobar") }

        iex> Resx.Resource.open!("data:,foobar") |> Resx.Resource.hash(ResxDropbox.Utility.hasher(:sha))
        { :dropbox, ResxDropbox.Utility.hash(:sha, "foobar") }
    """
    @spec hasher(algos) :: Resx.Resource.hasher
    def hasher(algo \\ :sha256), do: { :dropbox, { ResxDropbox.Utility, :hash, [algo] } }

    @doc """
      A resx resource streamable hasher for the dropbox content hashing algorithm.

      This can be applied globally as follows:

        config :resx,
            hash: ResxDropbox.streamable_hasher

      Or on individual resources:

        iex> Resx.Resource.open!("data:,foobar") |> Resx.Resource.hash(ResxDropbox.Utility.streamable_hasher)
        { :dropbox, ResxDropbox.Utility.hash("foobar") }

        iex> Resx.Resource.open!("data:,foobar") |> Resx.Resource.hash(ResxDropbox.Utility.streamable_hasher(:sha))
        { :dropbox, ResxDropbox.Utility.hash(:sha, "foobar") }
    """
    @spec streamable_hasher(algos) :: Resx.Resource.streamable_hasher
    def streamable_hasher(algo \\ :sha256), do: { :dropbox, { ResxDropbox.Utility, :hash_init, [algo], nil }, { ResxDropbox.Utility, :hash_update, 2 }, { ResxDropbox.Utility, :hash_final, 1 } }
end
