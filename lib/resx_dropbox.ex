defmodule ResxDropbox do
    @moduledoc """
      A producer to handle dropbox URIs.

        ResxDropbox.open("dbpath:/path/to/file.txt")
        ResxDropbox.open("dbid:AAAAAAAAAAAAAAAAAAAAAA")

      Add `ResxDropbox` to your list of resx producers.

        config :resx,
            producers: [ResxDropbox]

      ### Types

      MIME types are inferred from file extension names. Following the behaviour
      of `Resx.Producers.File.mime/1`.

      ### Authorities

      Authorities are used to match with a dropbox access token. When no authority
      is provided, it will attempt to find an access token for `nil`. These tokens
      can be configured by setting the `:token` configuration option for `:resx_dropbox`.

        config :resx_dropbox,
            token: "TOKEN"

        config :resx_dropbox,
            token: %{ nil => "TOKEN1", "foo@bar" => "TOKEN2", "main" => "TOKEN3" }

        config :resx_dropbox,
            token: { MyDropboxTokenRetriever, :to_token, 1 }

      The `:token` field should contain either a string which will be the token
      used by any authority, or a map of authority keys and token string values,
      or a callback function that will be passed the authority and should return
      `{ :ok, token }` or `:error` if there is no token for the given authority.
      Valid function formats are any callback variant, see `Callback` for more
      information.

      ### Sources

      Dropbox sources are dropbox content references with a backup data source, so
      if the content no longer exists it will revert back to getting the data from
      the source and creating the content again. The data source is any compatible
      URI.

        ResxDropbox.open("dbpath:/foo.txt?source=ZGF0YTp0ZXh0L3BsYWluO2NoYXJzZXQ9VVMtQVNDSUk7YmFzZTY0LGRHVnpkQT09")

      If the source cannot be accessed anymore but the content exists, it will access
      the content. If both cannot be accessed then the request will fail.
    """
    use Resx.Producer
    use Resx.Storer
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
    defp to_path(%URI{ scheme: "dbpath", path: nil, authority: authority, query: query }), do: build_repo(authority, { :path, "" }, query)
    defp to_path(%URI{ scheme: "dbpath", path: "/", authority: authority, query: query }), do: build_repo(authority, { :path, "" }, query)
    defp to_path(%URI{ scheme: "dbpath", path: path, authority: authority, query: query }), do: build_repo(authority, { :path, path }, query)
    defp to_path(%URI{ scheme: "dbid", path: "/" }), do: { :error, { :invalid_reference, "no ID" } }
    defp to_path(%URI{ scheme: "dbid", path: "/" <> path, authority: authority, query: query }), do: build_repo(authority, { :id, "id:" <> path }, query)
    defp to_path(%URI{ scheme: "dbid", path: path, authority: authority, query: query }) when not is_nil(path), do: build_repo(authority, { :id, "id:" <> path }, query)
    defp to_path(uri) when is_binary(uri), do: URI.decode(uri) |> URI.parse |> to_path
    defp to_path(_), do: { :error, { :invalid_reference, "not a dropbox reference" } }

    defp build_repo(authority, path, nil), do: { :ok, { authority, path, nil } }
    defp build_repo(_, { :id, _ }, _), do: { :error, { :invalid_reference, "dbid cannot have a source" } }
    defp build_repo(authority, path, query) do
        with %{ "source" => data } <- URI.decode_query(query),
             { :ok, source } <- Base.decode64(data) do
                { :ok, { authority, path, source } }
        else
            _ -> { :error, { :invalid_reference, "source is not base64" } }
        end
    end

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

    defp get_header([{ key, value }|_], key), do: value
    defp get_header([_|headers], key), do: get_header(headers, key)
    defp get_header(_, _), do: nil

    defp api_result(response), do: get_header(response.headers, "dropbox-api-result")

    defp format_timestamp(timestamp) do
        { :ok, timestamp, _ } = DateTime.from_iso8601(timestamp)
        timestamp
    end

    defp timestamp(data, :server), do: data["server_modified"] |> format_timestamp
    defp timestamp(data, :client), do: data["client_modified"] |> format_timestamp
    defp timestamp(data, nil), do: timestamp(data, Application.get_env(:resx_dropbox, :timestamp, :server))

    defp get_metadata(path, token), do: HTTPoison.post("https://api.dropboxapi.com/2/files/get_metadata", Poison.encode!(%{ path: path }), [{"Content-Type", "application/json"}|header(token)])

    defp download(path, token), do: HTTPoison.post("https://content.dropboxapi.com/2/files/download", "", [{"Dropbox-API-Arg", Poison.encode!(%{ path: path })}|header(token)])

    defp upload(path, token, contents, timestamp, mute), do: HTTPoison.post("https://content.dropboxapi.com/2/files/upload", contents, [{"Dropbox-API-Arg", Poison.encode!(%{ path: path, mode: :overwrite, client_modified: timestamp, mute: mute })}|header(token)])

    defp delete(path, token), do: HTTPoison.post("https://api.dropboxapi.com/2/files/delete", Poison.encode!(%{ path: path }), [{"Content-Type", "application/json"}|header(token)])

    @impl Resx.Producer
    def schemes(), do: ["dbpath", "dbid"]

    @doc """
      Opens a dropbox resource.

      The `:timestamp` option allows for choosing between `:server` or `:client`
      timestamps. By default the server timestamp is used, or whatever application
      timestamp setting was given.

        config :resx_dropbox,
            timestamp: :client

      If it is a source reference then a `:mute` option may be passed, which expects
      a boolean indicating whether the action should appear in the dropbox change
      history or not.
    """
    @impl Resx.Producer
    def open(reference, opts \\ []) do
        with { :path, { :ok, repo = { name, { _, path }, _ } } } <- { :path, to_path(reference) },
             { :token, { :ok, token }, _ } <- { :token, get_token(name), name },
             { :content, { :ok, response = %HTTPoison.Response{ status_code: 200 } }, _ } <- { :content, download(path, token), repo },
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
            { :content, error, { _, { _, path }, nil } } -> format_http_error(error, path, "retrieve content")
            { :content, _, { name, { :path, path }, source } } -> Resource.store(source, __MODULE__, auth: name, path: path, mute: opts[:mute])
            { :data, _ } -> { :error, { :internal, "unable to process api result" } }
        end
    end

    @impl Resx.Producer
    def exists?(reference) do
        with { :path, { :ok, repo = { name, { _, path }, _ } } } <- { :path, to_path(reference) },
             { :token, { :ok, token }, _ } <- { :token, get_token(name), name },
             { :metadata, { :ok, %HTTPoison.Response{ status_code: 200 } }, _ } <- { :metadata, get_metadata(path, token), repo } do
                { :ok, true }
        else
            { :path, error } -> error
            { :token, _, name } -> { :error, { :invalid_reference, "no token for authority (#{inspect name})" } }
            { :metadata, error, { _, { _, path }, nil } } ->
                case format_http_error(error, path, "retrieve metadata") do
                    { :error, { :unknown_resource, _ } } -> { :ok, false }
                    error -> error
                end
            { :metadata, _, { _, _, source } } -> Resource.exists?(source)
        end
    end

    @doc """
      See if two references are alike.

      This will check if two references are referring to the same content regardless
      of if they're not of the same kind (aren't both paths or ids) or have different
      access tokens (two different accounts referencing the same shared file). Due to
      this not all the comparisons can be made without making an API request, if
      there is ever a failure accessing that API then the function will assume that
      the two references are not alike.
    """
    @impl Resx.Producer
    def alike?(a, b) do
        with { :a, { :ok, repo_a } } <- { :a, to_path(a) },
             { :b, { :ok, repo_b } } <- { :b, to_path(b) } do
                case { repo_a, repo_b } do
                    { repo, repo } -> true
                    { { _, { :id, id }, _ }, { _, { :id, id }, _ } } -> true
                    { { name_a, path_a, _ }, { name_b, path_b, _ } } ->
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
                                            _ -> false
                                        end
                                end

                                case { path_b, a } do
                                    { _, false } -> false
                                    { _, true } -> true
                                    { { :id, id }, id } -> true
                                    { { :id, _ }, _ } -> false
                                    { { :path, path }, id } ->
                                        with { :metadata, { :ok, response = %HTTPoison.Response{ status_code: 200 } }, _ } <- { :metadata, get_metadata(path, token_b), path },
                                             { :data, { :ok, data } } <- { :data, response.body |> Poison.decode } do
                                                data["id"] == id
                                        else
                                            _ -> false
                                        end
                                end
                        else
                            _ -> false
                        end
                end
        else
            _ -> false
        end
    end

    @impl Resx.Producer
    def source(reference) do
        case to_path(reference) do
            { :ok, { _, _, source } } -> { :ok, source }
            error -> error
        end
    end

    @impl Resx.Producer
    def resource_uri(reference) do
        case to_path(reference) do
            { :ok, { nil, { :id, id }, nil } } -> { :ok, URI.encode("db" <> id) }
            { :ok, { authority, { :id, "id:" <> id }, nil } } -> { :ok, URI.encode("dbid://" <> authority <> "/" <> id) }
            { :ok, { nil, { :path, path }, nil } } -> { :ok, URI.encode("dbpath:" <> path) }
            { :ok, { authority, { :path, path }, nil } } -> { :ok, URI.encode("dbpath://" <> authority <> path) }
            { :ok, { authority, { :path, path }, source } } ->
                case Resource.uri(source) do
                    { :ok, uri } ->
                        case authority do
                            nil -> { :ok, URI.encode("dbpath:" <> path <> "?source=#{Base.encode64(uri)}") }
                            authority -> { :ok, URI.encode("dbpath://" <> authority <> path <> "?source=#{Base.encode64(uri)}") }
                        end
                    error -> error
                end
            error -> error
        end
    end

    @impl Resx.Producer
    def resource_attributes(reference) do
        with { :path, { :ok, repo = { name, { _, path }, _ } } } <- { :path, to_path(reference) },
             { :token, { :ok, token }, _ } <- { :token, get_token(name), name },
             { :metadata, { :ok, metadata = %HTTPoison.Response{ status_code: 200 } }, _ } <- { :metadata, get_metadata(path, token), repo },
             { :data, { :ok, data } } <- { :data, metadata.body |> Poison.decode } do
                { :ok, data }
        else
            { :path, error } -> error
            { :token, _, name } -> { :error, { :invalid_reference, "no token for authority (#{inspect name})" } }
            { :metadata, error, { _, { _, path }, nil } } -> format_http_error(error, path, "retrieve metadata")
            { :metadata, _, { _, _, source } } -> Resource.attributes(source)
            { :data, _ } -> { :error, { :internal, "unable to process api result" } }
        end
    end

    @doc """
      Store a resource as a file in dropbox.

      The required options are:

      * `:path` - expects a string denoting the path the file will be stored at.

      The following options are all optional:

      * `:auth` - expects the authority to lookup the token of.
      * `:mute` - expects a boolean indicating whether the action should appear in
      the dropbox change history or not.
    """
    @impl Resx.Storer
    def store(resource, options) do
        with { :path, { :ok, path } } <- { :path, Keyword.fetch(options, :path) },
             name <- options[:auth],
             { :token, { :ok, token }, _ } <- { :token, get_token(name), name },
             mute <- options[:mute] || false,
             data <- resource.content |> Content.reducer |> Enum.into(<<>>),
             meta_path <- path <> ".meta",
             timestamp <- DateTime.truncate(resource.reference.integrity.timestamp, :second) |> DateTime.to_iso8601,
             { :upload_meta, { :ok, %HTTPoison.Response{ status_code: 200 } }, _ } <- { :upload_meta, upload(meta_path, token, :erlang.term_to_binary(resource.meta), timestamp, mute), meta_path },
             { :upload_content, { :ok, %HTTPoison.Response{ status_code: 200 } }, _ } <- { :upload_content, upload(path, token, data, timestamp, mute), path } do
                content = %Content{
                    type: Resx.Producers.File.mime(path),
                    data: data
                }
                reference = %Reference{
                    adapter: __MODULE__,
                    repository: { name, { :path, path }, resource.reference },
                    integrity: %Integrity{
                        timestamp: DateTime.utc_now
                    }
                }
                { :ok, %{ resource | reference: reference, content: content } }
        else
            { :path, _ } -> { :error, { :internal, "a store :path must be specified" } }
            { :token, _, name } -> { :error, { :invalid_reference, "no token for authority (#{inspect name})" } }
            { :upload_content, error, path } -> format_http_error(error, path, "upload content")
            { :upload_meta, error, path } -> format_http_error(error, path, "upload meta")
        end
    end

    @doc """
      Discard a dropbox resource.

      The following options are all optional:

      * `:meta` - specify whether the meta file should also be deleted. By default
      it is.
      * `:content` - specify whether the content file should also be deleted. By
      default it is.
    """
    @impl Resx.Storer
    @spec discard(Resx.ref, [meta: boolean, content: boolean]) :: :ok | Resx.error(Resx.resource_error | Resx.reference_error)
    def discard(reference, opts) do
        with { :path, { :ok, { name, { _, path }, _ } } } <- { :path, to_path(reference) },
             { :token, { :ok, token }, _ } <- { :token, get_token(name), name },
             { :delete, { :ok, %HTTPoison.Response{ status_code: 200 } }, _, _ } <- { :delete, if(opts[:meta] != false, do: delete(path <> ".meta", token), else: { :ok, %HTTPoison.Response{ status_code: 200 } }), path, "meta" },
             { :delete, { :ok, %HTTPoison.Response{ status_code: 200 } }, _, _ } <- { :delete, if(opts[:content] != false, do: delete(path, token), else: { :ok, %HTTPoison.Response{ status_code: 200 } }), path, "content" } do
                :ok
        else
            { :path, error } -> error
            { :token, _, name } -> { :error, { :invalid_reference, "no token for authority (#{inspect name})" } }
            { :delete, error, path, kind } -> format_http_error(error, path, "delete #{kind}")
        end
    end
end
