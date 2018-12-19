defmodule ResxDropbox.Utility do
    @block_size 4 * 1024 * 1024

    def hash_init(algo \\ :sha256) do
        { algo, <<>>, <<>> }
    end

    def hash_update({ algo, <<block :: binary-size(@block_size), chunks :: binary>>, hashes }, data), do: hash_update({ algo, chunks <> data, hashes <> :crypto.hash(algo, block) }, <<>>)
    def hash_update(state, <<>>), do: state
    def hash_update({ algo, chunks, hashes }, data), do: hash_update({ algo, chunks <> data, hashes }, <<>>)

    def hash_final({ algo, <<block :: binary-size(@block_size), chunks :: binary>>, hashes }), do: hash_final({ algo, chunks, hashes <> :crypto.hash(algo, block) })
    def hash_final({ algo, block, hashes }) do
        hashes = hashes <> :crypto.hash(algo, block)
        :crypto.hash(algo, hashes) |> Base.encode16(case: :lower)
    end

    def hash(algo \\ :sha256, data), do: hash_init(algo) |> hash_update(data) |> hash_final
end
