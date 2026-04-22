# Reki

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## npm Fixture

A minimal npm package fixture lives in `fixtures/npm/widget-test`.

Manual registry flow:

* Start the app with `just dev`
* Publish the fixture with `just npm-fixture-publish`
* Try installing it with `just npm-fixture-install`
* Approve the version in Postgres, then rerun `just npm-fixture-install`

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
