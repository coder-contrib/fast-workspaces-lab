# Build timelines

Each JSON file contains the three arrays that Coder uses for its Build timeline: Terraform, agent connection, and startup scripts.

The files keep all start times, end times, script names, and status values. Job and agent IDs were replaced with example IDs. The original workspace IDs, usernames, and server addresses are not here.

`data/traces-manifest.csv` maps each file to a step. The first three files are one fresh create per template. Steps 4 and 5 each have three prebuild claims.

Run `python3 scripts/check-data.py` from the repository root to recompute the UI durations. Script intervals overlap. Do not add their lengths to get the ready time.
