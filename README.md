A collection of scripts for Gentoo development.

### Miscellaneous

#### QA

* `find-new-pkg-by`: list new packages by a maintainer (useful for finding
   e.g. proxied maintainers who add more packages than they maintain, and possibly
   directing them to GURU for such bits)

* `find-unmaintained`: find packages nominally maintained but with no commits
   from their maintainer recently

* `report-bugs-pkgcheck`: report bugs on Bugzilla en-masse for packages
   triggering a given `pkgcheck` check/warning

#### Keywords

* `at-find-unkeyworded-for-arch`: find packages unkeyworded for `${TARGET_ARCH}`
  relative to `${BASE_ARCH}` (e.g. suppose trying to get `riscv` parity with `arm64`)

* `find-unkeyworded`: find packages which have an unkeyworded version in ::gentoo
  for all arches. This sometimes happens and is forgotten about after committing
  something "unkeyworded for testing".

### git

#### Assorted scripts

* `check-all-changed-pkgs`: run `ebuild .. clean prepare` (or up to some other
   phase) on all packages with local pending changes. Useful for ensuring e.g.
   mass revbumps or other QA fixes haven't broken e.g. applying patches (think
   of e.g. `${PF}` being used in `PATCHES`)

* `commit-changed-pkgs`: commits each of the local changes per-package with
   a given commit message

* `sort-branch origin/master my-changes`: sorts commits by commit summary -
   does all work in a temporary branch and leaves `my-changes` alone. Can
   choose to throw away the sorted branch if merge conflicts occur

#### rebase-filter-maint

Takes a branch and creates a filtered version based on included/excluded maintainers.
Optionally can create the inverse too.

Suppose you have a branch with changes across the Gentoo tree affecting a range
of maintainers.

##### Usage

```
$ cd ~/git/gentoo
$ git checkout my-large-change-set
# Make your changes!
# Configure the script as appropriate
$ bash ~/scripts/rebase-filter-maint
$ git checkout my-large-change-set-identifier-whitelist
$ git checkout my-large-change-set-identifier-blacklist
```

##### Example (whitelist)
Our branch is `controversial` with a load of changes some people might
want to discuss, but others you know are okay with.

You might set the list to be maintainers with whom you have a good rapport
and choose the whitelist mode.

`rebase-filter-maint` will then create a branch called `controversial-${identifier}-whitelist`
containing all commits affecting those maintainers, so you can push it straight away.

If you choose, `rebase-filter-maint` will create an inverse branch called
`controversial-${identifier}-blacklist` containing all commits affecting non-listed
maintainers. This is a branch you might have to submit for review or similar.

##### Example (blacklist)
Our branch is `straightforward` and we think the changes are non-controversial,
but we want to leave certain packages maintained by e.g. base-system@ or toolchain@
because those deserve extra care due to their importance.

In this case, you might want to choose the blacklist mode.

`rebase-filter-maint` will then create a branch called `straightforward-${identifier}-blacklist`
which contains all commits that need more care. This is a branch you might have to
submit for review or similar.

If you choose, `rebase-filter-maint` will create an inverse branch called
`straightforward-${identifier}-whitelist` containing all commits affecting
maintainers whose packages we can touch. This is a branch you might be
able to just push.
