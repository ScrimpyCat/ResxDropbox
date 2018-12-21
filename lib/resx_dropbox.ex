defmodule ResxDropbox do
    use Resx.Producer
    require Callback

    alias Resx.Resource
    alias Resx.Resource.Content
    alias Resx.Resource.Reference
    alias Resx.Resource.Reference.Integrity

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
    defp to_path(%URI{ scheme: "dbid", path: "/" <> path, authority: authority }), do: { :ok, { authority, { :id, "id:" <> path } } }
    defp to_path(%URI{ scheme: "dbid", path: path, authority: authority }) when not is_nil(path), do: { :ok, { authority, { :id, "id:" <> path } } }
    defp to_path(uri) when is_binary(uri), do: URI.decode(uri) |> URI.parse |> to_path
    defp to_path(_), do: { :error, { :invalid_reference, "not a dropbox reference" } }

    defp format_api_error(%{ "error" => %{ ".tag" => "path", "path" => %{ ".tag" => "malformed_path" } } }, _), do: { :error, { :invalid_reference, "invalid path format" } }
    defp format_api_error(%{ "error" => %{ ".tag" => "path", "path" => %{ ".tag" => "restricted_content" } } }, _), do: { :error, { :invalid_reference, "content is restricted" } }
    defp format_api_error(%{ "error" => %{ ".tag" => "path", "path" => %{ ".tag" => error } } }, path) when error in ["not_found", "not_file", "not_folder"], do: { :error, { :unknown_resource, path } }
    defp format_api_error(%{ "error_summary" => summary }, _), do: { :error, { :internal, summary } }

    defp format_http_error({ :ok, response = %{ status_code: 400 } }, _, _), do: { :error, { :internal, response.body } }
    defp format_http_error({ :ok, response }, path, _) do
        case Poison.decode(response.body) do
            { :ok, error } -> format_api_error(error, path)
            _ -> { :error, { :internal, response.body } }
        end
    end
    defp format_http_error({ :error, error }, _, action), do: { :error, { :internal, "failed to #{action} due to: #{HTTPoison.Error.message(error)}" } }

    defp header(token), do: [{"Authorization", "Bearer #{token}"}]

    defp get_header([{ key, value }|headers], key), do: value
    defp get_header([_|headers], key), do: get_header(headers, key)
    defp get_header(_, _), do: nil

    defp api_result(response), do: get_header(response.headers, "dropbox-api-result")

    defp format_timestamp(timestamp) do
        { :ok, timestamp, _ } = DateTime.from_iso8601(timestamp)
        DateTime.to_unix(timestamp)
    end

    defp timestamp(data, :server), do: data["server_modified"] |> format_timestamp
    defp timestamp(data, :client), do: data["client_modified"] |> format_timestamp
    defp timestamp(data, nil), do: timestamp(data, Application.get_env(:resx_dropbox, :timestamp, :server))

    defp get_metadata(path, token), do: HTTPoison.post("https://api.dropboxapi.com/2/files/get_metadata", Poison.encode!(%{ path: path }), [{"Content-Type", "application/json"}|header(token)])

    defp download(path, token), do: HTTPoison.post("https://content.dropboxapi.com/2/files/download", "", [{"Dropbox-API-Arg", Poison.encode!(%{ path: path })}|header(token)])

    @impl Resx.Producer
    def open(reference, opts \\ []) do
        with { :path, { :ok, repo = { name, { _, path } } } } <- { :path, to_path(reference) },
             { :token, { :ok, token }, _ } <- { :token, get_token(name), name },
             { :content, { :ok, response = %HTTPoison.Response{ status_code: 200 } }, _ } <- { :content, download(path, token), path },
             { :data, { :ok, data } } <- { :data, api_result(response) |> Poison.decode } do
                content = %Content{
                    type: Resx.Producers.File.mime(data["name"]),
                    data: response.body
                }
                resource = %Resource{
                    reference: %Reference{
                        adapter: __MODULE__,
                        repository: repo,
                        integrity: %Integrity{
                            timestamp: timestamp(data, opts[:timestamp]),
                            checksum: { :dropbox, data["content_hash"] }
                        }
                    },
                    content: content
                }

                { :ok,  resource }
        else
            { :path, error } -> error
            { :token, _, name } -> { :error, { :invalid_reference, "no token for authority (#{inspect name})" } }
            { :content, error, path } -> format_http_error(error, path, "retrieve content")
            { :data, _ } -> { :error, { :internal, "unable to process api result" } }
        end
    end

    @impl Resx.Producer
    def exists?(reference) do
        with { :path, { :ok, repo = { name, { _, path } } } } <- { :path, to_path(reference) },
             { :token, { :ok, token }, _ } <- { :token, get_token(name), name },
             { :metadata, { :ok, metadata = %HTTPoison.Response{ status_code: 200 } }, _ } <- { :metadata, get_metadata(path, token), path } do
                { :ok, true }
        else
            { :path, error } -> error
            { :token, _, name } -> { :error, { :invalid_reference, "no token for authority (#{inspect name})" } }
            { :metadata, error, path } ->
                case format_http_error(error, path, "retrieve metadata") do
                    { :error, { :unknown_resource, _ } } -> { :ok, false }
                    error -> error
                end
        end
    end

    @impl Resx.Producer
    def alike?(a, b) do
        with { :a, { :ok, repo_a } } <- { :a, to_path(a) },
             { :b, { :ok, repo_b } } <- { :b, to_path(b) } do
                case { repo_a, repo_b } do
                    { repo, repo } -> true
                    { { _, { :id, id } }, { _, { :id, id } } } -> true
                    { { name_a, path_a }, { name_b, path_b } } ->
                        with { :token_a, { :ok, token_a }, _ } <- { :token_a, get_token(name_a), name_a },
                             { :token_b, { :ok, token_b }, _ } <- { :token_b, get_token(name_b), name_b } do
                                a = case path_a do
                                    ^path_b when token_a == token_b -> true
                                    { :id, id } -> id
                                    { :path, path } ->
                                        with { :metadata, { :ok, response = %HTTPoison.Response{ status_code: 200 } }, _ } <- { :metadata, get_metadata(path, token_a), path },
                                             { :data, { :ok, data } } <- { :data, response.body |> Poison.decode } do
                                                data["id"]
                                        else
                                            { :metadata, error, path } -> format_http_error(error, path, "retrieve metadata")
                                            { :data, _ } -> { :error, { :internal, "unable to process api result" } }
                                        end
                                end

                                case { path_b, a } do
                                    { _, true } -> true
                                    { { :id, id }, id } -> true
                                    { { :id, _ }, _ } -> false
                                    { { :path, path }, id } ->
                                        with { :metadata, { :ok, response = %HTTPoison.Response{ status_code: 200 } }, _ } <- { :metadata, get_metadata(path, token_b), path },
                                             { :data, { :ok, data } } <- { :data, response.body |> Poison.decode } do
                                                data["id"] == id
                                        else
                                            { :metadata, error, path } -> format_http_error(error, path, "retrieve metadata")
                                            { :data, _ } -> { :error, { :internal, "unable to process api result" } }
                                        end
                                end
                        else
                            { _, _, name } -> { :error, { :invalid_reference, "no token for authority (#{inspect name})" } }
                        end
                end
        else
            _ -> false
        end
    end
end
