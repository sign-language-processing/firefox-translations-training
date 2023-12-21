---
layout: default
title: Development
nav_order: 8
---

# Development

## Architecture

All steps are independent and contain scripts that accept arguments, read input files from disk and output the results to disk.
It allows writing the steps in any language (currently it's historically mostly bash and Python) and 
represent the pipeline as a directed acyclic graph (DAG).

The DAG of tasks can be launched using any workflow manager 
(currently we support [Snakemake](snakemake.md) and [Taskcluster](task-cluster.md)).
The workflow manager integration code should not include any training specific logic but rather implement it as a script
in the `pipeline` directory.


## Before committing

Set up a local [poetry](https://python-poetry.org/) environment.

Make sure to run linter with `make fix-all`.

For changes in the Taskcluster graph run `TASKCLUSTER_ROOT_URL="" make validate-taskgraph` to validate the graph locally.

## Tests

To run unit tests locally:
```
make run-tests
```

## CI

We run all training pipeline steps with a minimal config on pull requests. It runs on the same hardware as a production run.
Make sure to use `[skip ci]` directive in the PR description not to trigger the run it if not needed to save resources. 
If you do run it, minimize pushing to the branch. 

Ideally every new push to PR without `[skip ci]` should mean to test the new changes using CI. 

We do not run the pipeline on branches without a corresponding pull request.


## Conventions
  
- Scripts inside the `pipeline` directory are independent and operate only using input arguments, input files 
  and global envs.
  
- All scripts test expected environment variables early.

- If a script step fails, it can be safely retried.

- Ideally, every script should start from the last unfinished step, 
  checking presence of intermediate results of previous steps.

- A script fails as early as possible.

- Maximum bash verbosity is set for easy debugging.

- Input data is always read only.

- Output data is placed in a new folder for script results.
  
- It is expected that the specified output folder might not exist and should be created by the script.

- A script creates a folder for intermediate files and cleans it in the end 
  unless intermediate files are useful for retries.
    
- Global variables are upper case, local variables are lower case.

- Scripts should utilize resources provided by a workflow manager (for example number of threads).

- If the logic of the script is getting more complex, it should be written in Python since it can be easier to maintain

- Python scripts should use named arguments and argparse functionality
  
