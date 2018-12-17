defmodule ResxDropbox do
    require Callback

    alias Resx.Resource.Reference

    defp get_token(name) do
        case Application.get_env(:resx_dropbox, :token, %{}) do
            to_token when Callback.is_callback(to_token) -> Callback.call(to_token, [name])
            tokens when is_map(tokens) -> Map.fetch(tokens, name)
            token -> { :ok, token }
        end
    end

    defp to_path(%Reference{ repository: repo }), do: { :ok, repo }
    defp to_path(%URI{ scheme: "dbpath", path: nil, authority: authority }), do: { :ok, { authority, { :path, "" } } }
    defp to_path(%URI{ scheme: "dbpath", path: "/", authority: authority }), do: { :ok, { authority, { :path, "" } } }
    defp to_path(%URI{ scheme: "dbpath", path: path, authority: authority }), do: { :ok, { authority, { :path, path } } }
    defp to_path(%URI{ scheme: "dbid", path: "/" }), do: { :error, { :invalid_reference, "no ID" } }
    defp to_path(%URI{ scheme: "dbid", path: "/" <> path, authority: authority }), do: { :ok, { authority, { :id, path } } }
    defp to_path(%URI{ scheme: "dbid", path: path, authority: authority }) when not is_nil(path), do: { :ok, { authority, { :id, path } } }
    defp to_path(uri) when is_binary(uri), do: URI.decode(uri) |> URI.parse |> to_path
    defp to_path(_), do: { :error, { :invalid_reference, "not a dropbox reference" } }
end
