# Contributing

Thanks for considering a contribution. This file is a generic starting
point shipped by the `github-template` template repository; adjust it once
the project created from this template has its own conventions.

## Before you start

- Search open issues and pull requests first, so effort is not duplicated.
- For a change of any size, open an issue describing what you want to do
  before writing code, so the approach can be discussed up front.

## Making a change

1. Fork the repository and create a branch off `main`.
2. Install pre-commit and the hooks this repo wires up:

   ```shell
   pip install pre-commit
   pre-commit install
   ```

   Or work in a devcontainer-airlock workbench, where the hooks run in an
   L2 container that already carries pre-commit and every tool they need;
   see [.devcontainer/README.md](.devcontainer/README.md).

3. Make your change, and run the checks locally before opening a pull
   request:

   ```shell
   pre-commit run --all-files
   ```

4. Commit using [Conventional Commits](https://www.conventionalcommits.org/),
   for example `fix: correct a typo in the README`. No ticket prefix is
   required by default.
5. Open a pull request against `main` using the template in
   [.github/PULL_REQUEST_TEMPLATE.md](.github/PULL_REQUEST_TEMPLATE.md). Open
   it as a draft first if the checks take a while to run, and mark it ready
   once they are green.

## License

By contributing, you agree that your contributions will be licensed under
this repository's [Apache License 2.0](LICENSE.md). A project created from
this template that changes its license should update this line to match.

## Code of Conduct

Participation in this project is governed by
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Security issues

Do not open a public issue for a security vulnerability. See
[SECURITY.md](SECURITY.md) instead.
