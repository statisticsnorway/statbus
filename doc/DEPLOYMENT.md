# STATBUS GitHub Action Deployments

Development is done on the `master` branch.

Deployment is done to the libu.statbus.no cloud server running Ubuntu LTS hosted by Linode.

Deployment is done from specific branches to their corresponding environments.


*Configured*

* `devops/deploy-to-dev` -> `dev.statbus.org`
* `devops/deploy-to-no` -> `no.statbus.org`
* `devops/deploy-to-tcc` -> `tcc.statbus.org`

Development is done in the `master` branch.
Every commit to `master` is pushed to `devops/deploy-to-dev`.
For testing of PR's it is possible to manually force push any branch to
`devops/deploy-to-dev` for testing.

A manually triggered job pushes `master` to `devops/deploy-to-production`.
An automatic job pushes `devops/deploy-to-production` to `devops/deploy-to-no` and `devops/deploy-to-tcc`
that again triggers deployment.

A manually triggered job pushes `master` to `devops/deploy-to-no` for deploy to `no.statbus.org`.
A manually triggered job pushes `master` to `devops/deploy-to-tcc` for deploy to `tcc.statbus.org`.

A weekly job on Monday morning pushes `master` to `devops/deploy-to-production` for regular releases.

For an overview see
<img src="./diagrams/deployment.svg" alt="Deployment Diagram" style="max-width:100%; max-height:300px;">

## Future Plans

*TODO*
* `devops/deploy-to-demo` -> `demo.statbus.org`
* `devops/deploy-to-unstable` -> `unstable.statbus.org`

*Pending Discussion*
* `devops/deploy-to-qa-no` -> `qa-no.statbus.org`
* `devops/deploy-to-qa-tcc` -> `qa-tcc.statbus.org`


*TODO* Should we switch to a `develop` branch and auto deploy on merge to `master`?

Development is done in the `develop` branch.
Every commit to `develop` is pushed to `devops/deploy-to-unstable`.
For testing of PR's it is possible to manually force push any branch to
`devops/deploy-to-unstable` for testing.

The `dev` environment is removed and replaced by `unstable`.

When work is stable in the `develop` branch, it is merged to `master`.
Every commit to `master` is pushed to `devops/deploy-to-demo` for external testing.

Every commit to `master` is pushed to `devops/deploy-to-qa-*` for Quality Assurance testing
by the users of that installation.
When `qa-*.statbus.org` passes manual tests, then a manual job deploys
to `*.statbus.org`, by pushing the `devops/deploy-to-qa-*` branch to `devops/deploy-to-*`.

There are reset jobs to reset `devops/deploy-to-qa-*` from `devops/deploy-to-*` for testing of
database migrations, and verification of functionality with real life data.
