#!/usr/bin/env python3
#
# Copyright (C) 2023 Free Software Foundation, Inc.
# Contributed by Sam James.
#
# This script is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3, or (at your option)
# any later version.
#
# Script to create a map between weekly snapshots and the commit they're based on.
# Creates known_snapshots.txt with space-separated format: BRANCH-DATE COMMIT
# For example:
# 8-20210107 5114ee0676e432493ada968e34071f02fb08114f
# 8-20210114 f9267925c648f2ccd9e4680b699e581003125bcf

import os
import re
import urllib.request

MIRROR = "https://mirrorservice.org/sites/sourceware.org/pub/gcc/snapshots/"


def get_remote_snapshot_list() -> list[str]:
    # Parse the HTML index for links to snapshots
    with urllib.request.urlopen(MIRROR) as index_response:
        html = index_response.read().decode("utf-8")
        snapshots = re.findall(r'href="([0-9]+-.*)"', html)

    return snapshots


def load_cached_entries() -> dict[str, str]:
    local_snapshots = {}

    with open("known_snapshots.txt", encoding="utf-8") as local_entries:
        for entry in local_entries.readlines():
            if not entry:
                continue

            date, commit = entry.strip().split(" ")
            local_snapshots[date] = commit

    return local_snapshots


remote_snapshots = get_remote_snapshot_list()
try:
    known_snapshots = load_cached_entries()
except FileNotFoundError:
    # No cache available
    known_snapshots = {}

# This would give us chronological order (as in by creation)
# snapshots.sort(reverse=False, key=lambda x: x.split('-')[1])
# snapshots.sort(reverse=True, key=lambda x: x.split('-')[0])

for snapshot in remote_snapshots:
    # 8-20210107/ -> 8-20210107
    snapshot = snapshot.strip("/")

    # Don't fetch entries we already have stored.
    if snapshot in known_snapshots:
        continue

    # The READMEs are plain text with several lines, one of which is:
    # "with the following options: git://gcc.gnu.org/git/gcc.git branch releases/gcc-8 revision e4e5ad2304db534957c4af612aa288cb6ef51f25""
    # We match after 'revision ' to grab the commit used.
    with urllib.request.urlopen(f"{MIRROR}/{snapshot}/README") as readme_response:
        data = readme_response.read().decode("utf-8")
        parsed_commit = re.findall(r"revision (.*)", data)[0]
        known_snapshots[snapshot] = parsed_commit

# Dump it all back out to disk.
with open("known_snapshots.txt.tmp", "w", encoding="utf-8") as known_entries:
    for name, stored_commit in known_snapshots.items():
        known_entries.write(f"{name} {stored_commit}\n")

os.rename("known_snapshots.txt.tmp", "known_snapshots.txt")
