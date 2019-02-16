# ResxDropbox
A dropbox producer for [resx](https://github.com/ScrimpyCat/Resx)

Installation
------------

__Note:__ Whilst [resx](https://github.com/ScrimpyCat/Resx) is pre 0.1.0, this library will follow resx's versioning.

```elixir
def deps do
    [{ :resx_dropbox, "== 0.0.5" }]
end
```

Testing
-------

Set the environment variable `RESX_DROPBOX_TOKEN_TEST` to your access token before running the tests.

```bash
RESX_DROPBOX_TOKEN_TEST='DROPBOX_ACCESS_TOKEN' mix test
```

The tests should create a text file in the root folder with the prefix `resx_dropbox_test_file_`, followed by the timestamp. After the tests have completed running this file should be removed from your dropbox automatically.

The tests do not mute the notifications so you will see these notifications if you look at the dropbox account you're testing with.
