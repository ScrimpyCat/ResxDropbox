defmodule ResxDropbox.Utility do
    @type algos :: :crypto.sha1 | :crypto.sha2 | :crypto.sha3 | :crypto.compatibility_only_hash | :ripemd160
    @type state :: { algos, binary, binary }

    @block_size 4 * 1024 * 1024

    @spec hash_init(algos) :: state
    def hash_init(algo \\ :sha256) do
        { algo, <<>>, <<>> }
    end

    @spec hash_update(state, binary) :: state
    def hash_update({ algo, <<block :: binary-size(@block_size), chunks :: binary>>, hashes }, data), do: hash_update({ algo, chunks <> data, hashes <> :crypto.hash(algo, block) }, <<>>)
    def hash_update(state, <<>>), do: state
    def hash_update({ algo, chunks, hashes }, data), do: hash_update({ algo, chunks <> data, hashes }, <<>>)

    @spec hash_final(state) :: String.t
    def hash_final({ algo, <<block :: binary-size(@block_size), chunks :: binary>>, hashes }), do: hash_final({ algo, chunks, hashes <> :crypto.hash(algo, block) })
    def hash_final({ algo, block, hashes }) do
        hashes = hashes <> :crypto.hash(algo, block)
        :crypto.hash(algo, hashes) |> Base.encode16(case: :lower)
    end

    @spec hash(algos, binary) :: String.t
    def hash(algo \\ :sha256, data), do: hash_init(algo) |> hash_update(data) |> hash_final

    @spec hasher(algos) :: Resx.Resource.hasher
    def hasher(algo \\ :sha256), do: { :dropbox, { :crypto, :hash, [algo] } }

    @spec streamable_hasher(algos) :: Resx.Resource.streamable_hasher
    def streamable_hasher(algo \\ :sha256), do: { :dropbox, { :crypto, :hash_init, [algo], nil }, { :crypto, :hash_update, 2 }, { :crypto, :hash_final, 1 } }
end
