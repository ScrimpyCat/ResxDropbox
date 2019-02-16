defmodule ResxDropboxTest do
    use ExUnit.Case
    doctest ResxDropbox

    @test_file "/resx_dropbox_test_file_#{DateTime.to_unix(DateTime.utc_now)}.txt"
    @test_uri "dbpath:" <> @test_file
    @token System.get_env("RESX_DROPBOX_TOKEN_TEST")

    setup_all do
        Application.put_env(:resx, :producers, [ResxDropbox])
        Application.put_env(:resx_dropbox, :token, @token)
        Resx.Resource.open!("data:,test") |> Resx.Resource.store!(ResxDropbox, [path: @test_file])

        on_exit fn ->
            Application.put_env(:resx_dropbox, :token, @token)
            :ok = Resx.Resource.discard(@test_uri)
        end

        :ok
    end

    setup context do
        Application.put_env(:resx_dropbox, :token, @token)

        if file = context[:temp_file] do
            on_exit fn ->
                Application.put_env(:resx_dropbox, :token, @token)
                Resx.Resource.discard(file)
            end
        end

        { :ok, context }
    end

    test "open" do
        assert { :ok, resource } = Resx.Resource.open(@test_uri)
        assert "test" == Resx.Resource.Content.data(resource.content)

        Application.delete_env(:resx_dropbox, :token)

        assert { :error, { :invalid_reference, "no token for authority (nil)" } } == Resx.Resource.open(@test_uri)
    end

    test "exists?" do
        assert { :ok, true } == Resx.Resource.exists?(@test_uri)
        assert { :ok, false } == Resx.Resource.exists?(@test_uri <> ".foo")

        Application.delete_env(:resx_dropbox, :token)

        assert { :error, { :invalid_reference, "no token for authority (nil)" } } == Resx.Resource.exists?(@test_uri)
    end

    test "alike?" do
        assert true == Resx.Resource.alike?(@test_uri, @test_uri)
        assert false == Resx.Resource.alike?(@test_uri, @test_uri <> ".foo")
        assert false == Resx.Resource.alike?(@test_uri <> ".foo", @test_uri)

        { :ok, id } = Resx.Resource.open!(@test_uri) |> Resx.Resource.attribute("id")
        assert true == Resx.Resource.alike?(@test_uri, "db" <> id)
        assert true == Resx.Resource.alike?("db" <> id, @test_uri)
        assert true == Resx.Resource.alike?("db" <> id, "db" <> id)
        assert false == Resx.Resource.alike?("db" <> id, "db" <> id <> "1")
        assert false == Resx.Resource.alike?("db" <> id, @test_uri <> ".foo")
        assert false == Resx.Resource.alike?(@test_uri <> ".foo", "db" <> id)

        Application.delete_env(:resx_dropbox, :token)

        assert true == Resx.Resource.alike?(@test_uri, @test_uri)
        assert false == Resx.Resource.alike?(@test_uri, @test_uri <> ".foo")
        assert false == Resx.Resource.alike?(@test_uri <> ".foo", @test_uri)

        assert false == Resx.Resource.alike?(@test_uri, "db" <> id)
        assert false == Resx.Resource.alike?("db" <> id, @test_uri)
        assert true == Resx.Resource.alike?("db" <> id, "db" <> id)
        assert false == Resx.Resource.alike?("db" <> id, "db" <> id <> "1")
        assert false == Resx.Resource.alike?("db" <> id, @test_uri <> ".foo")
        assert false == Resx.Resource.alike?(@test_uri <> ".foo", "db" <> id)
    end

    test "uri" do
        assert { :ok, "dbid:foo" } == Resx.Resource.uri("dbid:foo")
        assert { :ok, "dbid://foo@bar/foo" } == Resx.Resource.uri("dbid://foo@bar/foo")
        assert { :ok, "dbpath:/foo.txt" } == Resx.Resource.uri("dbpath:/foo.txt")
        assert { :ok, "dbpath://foo@bar/foo.txt" } == Resx.Resource.uri("dbpath://foo@bar/foo.txt")
        assert { :ok, "dbpath:" } == Resx.Resource.uri("dbpath:/")
        assert { :ok, "dbpath://foo@bar" } == Resx.Resource.uri("dbpath://foo@bar/")

        Application.delete_env(:resx_dropbox, :token)

        assert { :ok, "dbid:foo" } == Resx.Resource.uri("dbid:foo")
        assert { :ok, "dbid://foo@bar/foo" } == Resx.Resource.uri("dbid://foo@bar/foo")
        assert { :ok, "dbpath:/foo.txt" } == Resx.Resource.uri("dbpath:/foo.txt")
        assert { :ok, "dbpath://foo@bar/foo.txt" } == Resx.Resource.uri("dbpath://foo@bar/foo.txt")
        assert { :ok, "dbpath:" } == Resx.Resource.uri("dbpath:/")
        assert { :ok, "dbpath://foo@bar" } == Resx.Resource.uri("dbpath://foo@bar/")
    end

    test "hash" do
        resource = Resx.Resource.open!(@test_uri)
        assert resource.reference.integrity.checksum == Resx.Resource.hash(resource, ResxDropbox.Utility.streamable_hasher)
    end

    describe "stores" do
        @tag temp_file: @test_file <> ".text"
        test "saving a file", %{ temp_file: path } do
            assert { :ok, resource } = Resx.Resource.open!("data:,hello") |> Resx.Resource.store(ResxDropbox, path: path)

            assert { :ok, true } == Resx.Resource.exists?("dbpath:" <> path)
            assert "hello" == Resx.Resource.Content.data(resource.content)
            assert "hello" == Resx.Resource.open!("dbpath:" <> path).content |> Resx.Resource.Content.data
            assert :ok == Resx.Resource.discard(resource)
            assert { :ok, false } == Resx.Resource.exists?("dbpath:" <> path)

            assert { :error, { :unknown_resource, _ } } = Resx.Resource.open("dbpath:" <> path)
            assert { :ok, false } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open(resource)
            assert { :ok, true } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open("dbpath:" <> path)

            assert :ok == Resx.Resource.discard(resource)
            assert { :ok, uri } = Resx.Resource.uri(resource)
            assert { :ok, false } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open(uri)
            assert { :ok, true } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open("dbpath:" <> path)

            Application.delete_env(:resx_dropbox, :token)
            assert { :error, { :invalid_reference, _ } } = Resx.Resource.open!("data:,hello") |> Resx.Resource.store(ResxDropbox, path: path)
        end

        @tag temp_file: @test_file <> ".bin"
        test "saving non-binary contents", %{ temp_file: path } do
            resource = Resx.Resource.open!("data:,hello")
            resource = %{ resource | content: %Resx.Resource.Content{ type: ["application/x.erlang.etf"], data: :foo } }
            assert catch_error(Resx.Resource.store(resource, ResxDropbox, path: path))

            assert { :ok, false } == Resx.Resource.exists?("dbpath:" <> path)

            Application.put_env(:resx, :content_reducer, fn
                content = %{ type: ["application/x.erlang.etf"|_] }, :binary -> &Enumerable.reduce([:erlang.term_to_binary(Resx.Resource.Content.data(content))], &1, &2)
                content, :binary -> &Enumerable.reduce(Resx.Resource.Content.Stream.new(content), &1, &2)
            end)
            Application.put_env(:resx, :content_combiner, fn
                %{ type: ["application/x.erlang.etf"|_], data: [data] } -> data
                content -> Resx.Resource.Content.Stream.combine(content, <<>>)
            end)

            assert { :ok, resource } = Resx.Resource.store(resource, ResxDropbox, path: path)

            assert :erlang.term_to_binary(:foo) == Resx.Resource.Content.data(resource.content)
            assert { :ok, true } == Resx.Resource.exists?("dbpath:" <> path)
            assert :erlang.term_to_binary(:foo) == Resx.Resource.open!("dbpath:" <> path).content |> Resx.Resource.Content.data
            assert :ok == Resx.Resource.discard(resource)
            assert { :ok, false } == Resx.Resource.exists?("dbpath:" <> path)

            assert { :error, { :unknown_resource, _ } } = Resx.Resource.open("dbpath:" <> path)
            assert { :ok, false } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open(resource)
            assert { :ok, true } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open("dbpath:" <> path)

            assert :ok == Resx.Resource.discard(resource)
            assert { :ok, uri } = Resx.Resource.uri(resource)
            assert { :ok, false } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open(uri)
            assert { :ok, true } == Resx.Resource.exists?("dbpath:" <> path)
            assert { :ok, _ } = Resx.Resource.open("dbpath:" <> path)

            Application.delete_env(:resx_dropbox, :token)
            Application.delete_env(:resx, :content_reducer)
            Application.delete_env(:resx, :content_combiner)
        end
    end
end
