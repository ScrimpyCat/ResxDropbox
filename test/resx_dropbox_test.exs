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
            :ok = ResxDropbox.remove(@test_uri, meta: true)
        end

        :ok
    end

    setup do
        Application.put_env(:resx_dropbox, :token, @token)
        :ok
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
end
