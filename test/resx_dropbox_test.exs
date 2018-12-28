defmodule ResxDropboxTest do
    use ExUnit.Case
    doctest ResxDropbox

    @test_file "/resx_dropbox_test_file_#{DateTime.to_unix(DateTime.utc_now)}.txt"
    @test_uri "dbpath:" <> @test_file
    @token System.get_env("RESX_DROPBOX_TOKEN_TEST")

    setup_all do
        Application.put_env(:resx_dropbox, :token, @token)
        Resx.Resource.open!("data:,test") |> ResxDropbox.store([path: @test_file])

        on_exit fn ->
            Application.put_env(:resx_dropbox, :token, @token)
            :ok = ResxDropbox.delete(@test_uri)
        end

        :ok
    end

    setup do
        Application.put_env(:resx_dropbox, :token, @token)
        :ok
    end

    test "open" do
        assert { :ok, resource } = ResxDropbox.open(@test_uri)
        assert "test" == Resx.Resource.Content.data(resource.content)

        Application.delete_env(:resx_dropbox, :token)

        assert { :error, { :invalid_reference, "no token for authority (nil)" } } == ResxDropbox.open(@test_uri)
    end

    test "uri" do
        assert { :ok, "dbid:foo" } == ResxDropbox.resource_uri("dbid:foo")
        assert { :ok, "dbid://foo@bar/foo" } == ResxDropbox.resource_uri("dbid://foo@bar/foo")
        assert { :ok, "dbpath:/foo.txt" } == ResxDropbox.resource_uri("dbpath:/foo.txt")
        assert { :ok, "dbpath://foo@bar/foo.txt" } == ResxDropbox.resource_uri("dbpath://foo@bar/foo.txt")
        assert { :ok, "dbpath:" } == ResxDropbox.resource_uri("dbpath:/")
        assert { :ok, "dbpath://foo@bar" } == ResxDropbox.resource_uri("dbpath://foo@bar/")

        Application.delete_env(:resx_dropbox, :token)

        assert { :ok, "dbid:foo" } == ResxDropbox.resource_uri("dbid:foo")
        assert { :ok, "dbid://foo@bar/foo" } == ResxDropbox.resource_uri("dbid://foo@bar/foo")
        assert { :ok, "dbpath:/foo.txt" } == ResxDropbox.resource_uri("dbpath:/foo.txt")
        assert { :ok, "dbpath://foo@bar/foo.txt" } == ResxDropbox.resource_uri("dbpath://foo@bar/foo.txt")
        assert { :ok, "dbpath:" } == ResxDropbox.resource_uri("dbpath:/")
        assert { :ok, "dbpath://foo@bar" } == ResxDropbox.resource_uri("dbpath://foo@bar/")
    end
end
