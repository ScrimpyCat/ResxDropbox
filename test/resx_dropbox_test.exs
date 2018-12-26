defmodule ResxDropboxTest do
    use ExUnit.Case
    doctest ResxDropbox

    setup do
        Application.put_env(:resx_dropbox, :token, System.get_env("RESX_DROPBOX_TOKEN_TEST"))
        :ok
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
