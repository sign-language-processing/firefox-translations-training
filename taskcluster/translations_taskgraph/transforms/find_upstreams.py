# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This transform sequence sets `dependencies` and `fetches` based on
# the information provided in the `upstreams-config` data in each job
# and the given parameters.

# It will through all tasks generated from `kind-dependencies` and
# set any tasks that match the following conditions as dependencies:
# - src and trg locale given match the {src,trg}_locale attributes on the upstream task
# - `upstream-task-attributes` given match their equivalents on the upstream task
# - `dataset` attribute on the upstream task is one of the datasets provided in `parameters`
#   for the `dataset-category` given in the job.
#
# Additionally, fetches will be added for those tasks for each entry in `upstream-artifacts`.
#
# (It is not ideal that this transform hardcodes dataset handling, but because kinds are
# completely unaware of parameters, there's no other real way to do this.)

import copy

from taskgraph.transforms.base import TransformSequence
from taskgraph.util.schema import Schema, optionally_keyed_by, resolve_keyed_by
from voluptuous import ALLOW_EXTRA, Required, Optional

from translations_taskgraph.util.substitution import substitute
from translations_taskgraph.util.dataset_helpers import sanitize_dataset_name

SCHEMA = Schema(
    {
        Required("upstreams-config"): {
            Required("upstream-task-attributes"): {
                str: optionally_keyed_by("cleaning-type", str),
            },
            Required("upstream-artifacts"): [str],
        },
    },
    extra=ALLOW_EXTRA,
)

by_locales = TransformSequence()
by_locales.add_validate(SCHEMA)

MONO = Schema(
    {
        Required("upstreams-config"): {
            Required("upstream-task-attributes"): {
                str: optionally_keyed_by("cleaning-type", str),
            },
            Required("upstream-artifacts"): [str],
            Optional("substitution-fields"): [str],
        },
    },
    extra=ALLOW_EXTRA,
)

mono = TransformSequence()
mono.add_validate(MONO)


def get_cleaning_type(upstreams):
    candidates = set()

    for upstream in upstreams:
        if upstream.kind not in ("bicleaner", "clean-corpus"):
            continue

        candidates.add(upstream.attributes["cleaning-type"])

    for type_ in ("bicleaner-ai", "bicleaner", "clean-corpus"):
        if type_ in candidates:
            return type_

    raise Exception("Unable to find cleaning type!")


@by_locales.add
def resolve_keyed_by_fields(config, jobs):
    for job in jobs:
        upstreams_config = job["upstreams-config"]
        cleaning_type = get_cleaning_type(config.kind_dependencies_tasks.values())

        resolve_keyed_by(
            upstreams_config,
            "upstream-task-attributes.cleaning-type",
            item_name=job["description"],
            **{"cleaning-type": cleaning_type},
        )

        yield job


@by_locales.add
def upstreams_for_locales(config, jobs):
    datasets = config.params.get("training_config", {}).get("datasets", {})
    for job in jobs:
        dataset_category = job["attributes"]["dataset-category"]
        target_datasets = datasets[dataset_category]
        upstreams_config = job.pop("upstreams-config")
        artifacts = upstreams_config["upstream-artifacts"]
        upstream_task_attributes = upstreams_config["upstream-task-attributes"]

        subjob = copy.deepcopy(job)
        subjob.setdefault("dependencies", {})
        subjob.setdefault("fetches", {})

        # Now that we've resolved which type of upstream task we want, we need to
        # find all instances of that task for our locale pair, add them to our
        # dependencies, and the necessary artifacts to our fetches.
        for task in sorted(config.kind_dependencies_tasks.values(), key=lambda t: t.label):
            # Filter out any tasks that don't match the desired attributes.
            if any(task.attributes.get(k) != v for k, v in upstream_task_attributes.items()):
                continue

            provider = task.attributes["provider"]
            dataset = task.attributes["dataset"]
            task_dataset = f"{provider}_{dataset}"

            # Filter out any tasks that don't match a desired dataset
            if task_dataset not in target_datasets:
                continue

            subs = {
                "src_locale": task.attributes["src_locale"],
                "trg_locale": task.attributes["trg_locale"],
                "dataset_sanitized": sanitize_dataset_name(dataset),
            }

            subjob["dependencies"][task.label] = task.label
            subjob["fetches"].setdefault(task.label, [])
            for artifact in sorted(artifacts):
                subjob["fetches"][task.label].append(
                    {
                        "artifact": artifact.format(**subs),
                        "extract": False,
                    }
                )

        yield subjob


@mono.add
def upstreams_for_mono(config, jobs):
    training_config = config.params.get("training_config", {})
    datasets = training_config.get("datasets", {})
    src = training_config["experiment"]["src"]
    trg = training_config["experiment"]["trg"]
    for job in jobs:
        dataset_category = job["attributes"]["dataset-category"]
        target_datasets = datasets[dataset_category]
        job.setdefault("dependencies", {})
        job.setdefault("fetches", {})
        upstreams_config = job.pop("upstreams-config")
        upstream_task_attributes = upstreams_config["upstream-task-attributes"]
        artifacts = upstreams_config["upstream-artifacts"]
        substitution_fields = upstreams_config.get("substitution-fields", [])

        for task in sorted(config.kind_dependencies_tasks.values(), key=lambda t: t.label):
            # Filter out any tasks that don't match the desired attributes.
            if any(task.attributes.get(k) != v for k, v in upstream_task_attributes.items()):
                continue

            provider = task.attributes["provider"]
            dataset = task.attributes["dataset"]
            task_dataset = f"{provider}_{dataset}"

            # Filter out any tasks that don't match a desired dataset
            if task_dataset not in target_datasets:
                continue

            if dataset_category == "mono-src":
                locale = src
            elif dataset_category == "mono-trg":
                locale = trg
            else:
                raise Exception(
                    "Don't use `find_upstreams:mono` without the `mono-src` or `mono-trg` category!"
                )

            job["dependencies"][task.label] = task.label
            job["fetches"].setdefault(task.label, [])

            subs = {
                "provider": provider,
                "dataset": dataset,
                "dataset_sanitized": sanitize_dataset_name(dataset),
                "locale": locale,
                "src_locale": src,
                "trg_locale": trg,
            }

            for field in substitution_fields:
                container, subfield = job, field
                while "." in subfield:
                    f, subfield = subfield.split(".", 1)
                    container = container[f]

                container[subfield] = substitute(container[subfield], **subs)

            for artifact in sorted(artifacts):
                job["fetches"][task.label].append(
                    {
                        "artifact": artifact.format(**subs),
                        "extract": False,
                    }
                )

            job["attributes"]["src_locale"] = src
            job["attributes"]["trg_locale"] = trg

        yield job
