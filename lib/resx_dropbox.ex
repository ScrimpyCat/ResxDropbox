defmodule ResxDropbox do
    require Callback

    defp get_token(name) do
        case Application.get_env(:resx_dropbox, :token, %{}) do
            to_token when Callback.is_callback(to_token) -> Callback.call(to_token, [name])
            tokens when is_map(tokens) -> Map.fetch(tokens, name)
            token -> { :ok, token }
        end
    end
end
