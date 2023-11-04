#!/usr/bin/env python3
import os
import re
import subprocess as sp
import sys

import yaml
from snakemake.logging import logger
from snakemake.utils import read_job_properties

cluster_config_file = os.path.join(os.path.dirname(__file__), "config.cluster.yaml")
cluster_config = yaml.load(open(cluster_config_file), Loader=yaml.FullLoader)

jobscript = sys.argv[-1]
job_properties = read_job_properties(jobscript)

options = []

if job_properties["type"] == "single":
    name = job_properties["rule"]
elif job_properties["type"] == "group":
    name = job_properties["groupid"]
else:
    raise NotImplementedError(
        f"Don't know what to do with job_properties['type']=={job_properties['type']}"
    )

options += ["--job-name", name]

if "resources" in job_properties:
    resources = job_properties["resources"]

    if "gpu" in resources and int(resources["gpu"]) >= 1:
        num_gpu = str(resources["gpu"])
        options += [f"--gres=gpu:{num_gpu}"]

    # we don't need explicit memory limiting for now
    # if 'mem_mb' in resources:
    #     memory = str(resources['mem_mb'])
    #     options += [f'--mem={memory}']

cuda_dir = os.getenv("CUDA_DIR")
if cuda_dir:
    options += ["--export", f'ALL,SINGULARITY_BIND="{cuda_dir}"']

options += ["--nodes=1"]
options += ["-t", str(cluster_config["time-limit"])]

if "threads" in job_properties:
    options += ["--cpus-per-task", str(job_properties["threads"])]

try:
    cmd = ["sbatch"] + ["--parsable"] + options + [jobscript]
    logger.info(f"Running command: {cmd}")
    res = sp.check_output(cmd)
except sp.CalledProcessError as e:
    raise e
# Get jobid
res = res.decode()
try:
    jobid = re.search(r"(\d+)", res).group(1)
except Exception as e:
    raise e

print(jobid)
