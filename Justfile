set shell := ["bash", "-uc"]

fixture_dir := "fixtures/npm/widget-test"
install_dir := "tmp/npm-install"
registry := "http://localhost:4000/api/"
npmrc := "tmp/npmrc"

dev:
	iex -S mix phx.server

npm-fixture-pack:
	cd {{fixture_dir}} && npm pack

npm-fixture-publish registry_url=registry:
	mkdir -p tmp
	printf 'registry={{registry_url}}\nalways-auth=true\n//localhost:4000/api/:_authToken=dummy-token\n' > {{npmrc}}
	cd {{fixture_dir}} && npm publish --registry {{registry_url}} --userconfig "$PWD/../../../{{npmrc}}"

npm-fixture-install version="1.0.0" registry_url=registry:
	rm -rf {{install_dir}}
	mkdir -p {{install_dir}}
	cd {{install_dir}} && npm init -y
	cd {{install_dir}} && npm install widget-test@{{version}} --registry {{registry_url}}
