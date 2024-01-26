import yaml
import os
import subprocess

from snakemake.utils import min_version


min_version("6.6.1")

# `include` directive is not supported by Pycharm plugin, moving all rules to one file to enable live checks
# https://github.com/JetBrains-Research/snakecharm/issues/195


### configuration

container: 'Singularity.sif'

install_deps = config['deps'] == 'true'
data_root_dir = config['root']
cuda_dir = config.get('cuda', os.path.dirname(os.path.dirname(subprocess.check_output('which nvcc', shell=True).decode().strip())))
cudnn_dir = config['cudnn']
gpus_num = config['numgpus']
# marian occupies all GPUs on a machine if `gpus` are not specified
gpus = config['gpus'] if config['gpus'] else ' '.join([str(n) for n in range(int(gpus_num))])
workspace = config['workspace']
marian_cmake = config['mariancmake']

# experiment
src = config['experiment']['src']
trg = config['experiment']['trg']
experiment = config['experiment']['name']

mono_max_sent_src = config['experiment']['mono-max-sentences-src']
mono_max_sent_trg = config['experiment']['mono-max-sentences-trg']
bicl_default_threshold = config['experiment']['bicleaner']['default-threshold']
bicl_dataset_thresholds = config['experiment']['bicleaner']['dataset-thresholds']
use_opuscleaner = config['experiment']['use-opuscleaner']
backward_pretrained = config['experiment']['backward-model']
vocab_pretrained = config['experiment']['vocab']

experiment_dir=f"{data_root_dir}/experiments/{src}-{trg}/{experiment}"

# override marian cofings
marian_args = {name: ' '.join([f'--{k} {v}' for k,v in conf.items() ])
               for name, conf in config['marian-args'].items()}

# datasets
train_datasets = config['datasets']['train']
valid_datasets = config['datasets']['devtest']
eval_datasets = config['datasets']['test']
mono_src_datasets = config['datasets']['mono-src']
mono_trg_datasets = config['datasets']['mono-trg']
mono_datasets = {src: mono_src_datasets, trg: mono_trg_datasets}
mono_max_sent = {src: mono_max_sent_src, trg: mono_max_sent_trg}

# parallelization

ensemble = list(range(config['experiment']['teacher-ensemble']))
split_chunks = config['experiment']['split-chunks']

# logging
log_dir = f"{data_root_dir}/logs/{src}-{trg}/{experiment}"
reports_dir = f"{data_root_dir}/reports/{src}-{trg}/{experiment}"

# binaries
cwd = os.getcwd()
third_party_dir = f'{cwd}/3rd_party'
marian_dir = f'{third_party_dir}/marian-dev/build'
bmt_marian_dir = f'{third_party_dir}/browsermt-marian-dev/build'
trainer = f'{marian_dir}/marian'
decoder = f'{marian_dir}/marian-decoder'
scorer = f'{marian_dir}/marian-scorer'
spm_encoder = f'{marian_dir}/spm_encode'
spm_trainer = f'{marian_dir}/spm_train'
spm_exporter = f'{marian_dir}/spm_export_vocab'
bmt_decoder = f'{bmt_marian_dir}/marian-decoder'
bmt_converter = f'{bmt_marian_dir}/marian-conv'

kenlm = f'{third_party_dir}/kenlm'
fast_align_build = f'{third_party_dir}/fast_align/build'
extract_lex_build = f'{third_party_dir}/extract-lex/build'
preprocess_build_dir=f'{third_party_dir}/preprocess/build'
bin = f'{cwd}/bin'
deduper = f'{cwd}/bin/dedupe'

# data
data_dir = f"{data_root_dir}/data/{src}-{trg}/{experiment}"
clean = f"{data_dir}/clean"
biclean = f"{data_dir}/biclean"
cache_dir = f"{data_dir}/cache"
original = f"{data_dir}/original"
translated = f"{data_dir}/translated"
backtranslated = f"{data_dir}/backtranslated"
merged = f"{data_dir}/merged"
filtered = f'{data_dir}/filtered'
align_dir = f"{data_dir}/alignment"

# models
models_dir = f"{data_root_dir}/models/{src}-{trg}/{experiment}"
teacher_base_dir = f"{models_dir}/teacher-base"
student_dir = f"{models_dir}/student"
student_finetuned_dir = f"{models_dir}/student-finetuned"
speed_dir = f"{models_dir}/speed"
exported_dir = f"{models_dir}/exported"
best_model_metric = config['experiment']['best-model']
best_model = f"final.model.npz.best-{best_model_metric}.npz"
backward_dir = f'{models_dir}/backward'
spm_sample_size=config['experiment']['spm-sample-size']
spm_vocab_size=config['experiment'].get('spm-vocab-size',"32000")
spm_user_defined_symbols=config['experiment'].get('spm-user-defined-symbols',"")
vocab_path=vocab_pretrained or f"{models_dir}/vocab/vocab.spm"

#evaluation
eval_data_dir = f"{original}/eval"
eval_res_dir = f"{models_dir}/evaluation"
eval_backward_dir = f'{eval_res_dir}/backward'
eval_student_dir = f'{eval_res_dir}/student'
eval_student_finetuned_dir = f'{eval_res_dir}/student-finetuned'
eval_speed_dir = f'{eval_res_dir}/speed'
eval_teacher_ens_dir = f'{eval_res_dir}/teacher-ensemble'

# set common environment variables
envs = f'''SRC={src} TRG={trg} MARIAN="{marian_dir}" BMT_MARIAN="{bmt_marian_dir}" GPUS="{gpus}" WORKSPACE={workspace} \
BIN="{bin}" CUDA_DIR="{cuda_dir}" CUDNN_DIR="{cudnn_dir}" '''
# CUDA_VISIBLE_DEVICES is used by bicleaner ai. slurm sets this variable
# it can be overriden manually by 'gpus' config setting to split GPUs in local mode
if config['gpus']:
    envs += f' CUDA_VISIBLE_DEVICES="{gpus}" '

### workflow options

results = [f'{exported_dir}/model.{src}{trg}.intgemm.alphas.bin.gz',
           f'{exported_dir}/lex.50.50.{src}{trg}.s2t.bin.gz',
           f'{exported_dir}/vocab.{src}{trg}.spm.gz',
           f'{experiment_dir}/config.yml',
           *expand(f'{eval_res_dir}/teacher-base{{ens}}/{{dataset}}.metrics',ens=ensemble, dataset=eval_datasets),
           *expand(f'{eval_student_dir}/{{dataset}}.metrics', dataset=eval_datasets),
           *expand(f'{eval_student_finetuned_dir}/{{dataset}}.metrics', dataset=eval_datasets),
           *expand(f'{eval_speed_dir}/{{dataset}}.metrics', dataset=eval_datasets)
           ]

if len(ensemble) > 1:
    results.extend(expand(f'{eval_teacher_ens_dir}/{{dataset}}.metrics', dataset=eval_datasets))

if install_deps:
    results.append("/tmp/flags/setup.done")

if not backward_pretrained:
    # don't evaluate pretrained model
    results.extend(expand(f'{eval_backward_dir}/{{dataset}}.metrics',dataset=eval_datasets))
    do_train_backward=True
else:
    do_train_backward = False
    backward_dir = backward_pretrained

# bicleaner

# todo: move to setting if needed
use_bicleaner = True

if use_bicleaner:
    clean_corpus_prefix = f'{biclean}/corpus'
else:
    clean_corpus_prefix = f'{clean}/corpus'

clean_corpus_src = f'{clean_corpus_prefix}.{src}.gz'
clean_corpus_trg = f'{clean_corpus_prefix}.{trg}.gz'

# cleaning tools

clean_corpus_cmd = 'pipeline/clean/opuscleaner/clean-corpus.sh' \
    if use_opuscleaner \
    else 'pipeline/clean/clean-corpus.sh'



### helper functions

def find_parts(wildcards, checkpoint):
    checkpoint_output = checkpoint.get(**wildcards).output[0]
    return glob_wildcards(os.path.join(checkpoint_output,"file.{part,\d+}")).part

def dataset_norm(name: str):
    return name.replace('/','_')

def get_args(section):
    return marian_args.get(section) or ""


### rules

shell.prefix(f"{envs} ")

rule all:
    input: results

localrules: experiment

rule experiment:
    message: "Saving experiment metadata"
    output: f'{experiment_dir}/config.yml'
    priority: 100
    run:
        os.makedirs(experiment_dir, exist_ok=True)
        with open(f'{experiment_dir}/config.yml', 'w') as f:
            yaml.dump(config, f)

# todo: fix jobs grouping in cluster mode


# setup

if install_deps:
    rule setup:
        message: "Installing dependencies"
        log: f"{log_dir}/install-deps.log"
        conda: "envs/base.yml"
        priority: 99
        # group: 'setup'
        output: touch("/tmp/flags/setup.done")  # specific to local machine
        shell: 'bash pipeline/setup/install-deps.sh >> {log} 2>&1'

rule marian:
    message: "Compiling marian"
    log: f"{log_dir}/compile-{{marian_type}}.log"
    conda: "envs/base.yml"
    threads: 16
    resources: gpu=1
 #   group: 'setup'
    output:
        trainer=protected(f"{third_party_dir}/{{marian_type}}/build/marian"),
        decoder=protected(f"{third_party_dir}/{{marian_type}}/build/marian-decoder"),
        scorer=protected(f"{third_party_dir}/{{marian_type}}/build/marian-scorer"),
        converter=protected(f'{third_party_dir}/{{marian_type}}/build/marian-conv'),
        spm_trainer=protected(f'{third_party_dir}/{{marian_type}}/build/spm_train'),
        spm_encoder=protected(f'{third_party_dir}/{{marian_type}}/build/spm_encode'),
        spm_exporter=protected(f'{third_party_dir}/{{marian_type}}/build/spm_export_vocab')
    params: build_dir=f'{third_party_dir}/{{marian_type}}/build'
    shell: 'bash pipeline/setup/compile-marian.sh {params.build_dir} {threads} {marian_cmake} >> {log} 2>&1'

rule fast_align:
    message: "Compiling fast align"
    log: f"{log_dir}/compile-fast-align.log"
    conda: "envs/base.yml"
    threads: 4
#    group: 'setup'
    output: fast_align=protected(f"{bin}/fast_align"), atools=protected(f"{bin}/atools")
    shell: 'bash pipeline/setup/compile-fast-align.sh {fast_align_build} {threads}  >> {log} 2>&1'

rule compile_preprocess:
    message: "Compiling preprocess"
    log: f"{log_dir}/compile-preprocess.log"
    conda: "envs/base.yml"
    threads: 4
    # group: 'setup'
    output: deduper=f'{bin}/dedupe'
    shell: 'bash pipeline/setup/compile-preprocess.sh {preprocess_build_dir} {threads}  >> {log} 2>&1'

rule extract_lex:
    message: "Compiling fast align"
    log: f"{log_dir}/compile-extract-lex.log"
    conda: "envs/base.yml"
    threads: 4
#    group: 'setup'
    output: protected(f"{bin}/extract_lex")
    shell: 'bash pipeline/setup/compile-extract-lex.sh {extract_lex_build} {threads} >> {log} 2>&1'

# data downloading

rule download_corpus:
    message: "Downloading parallel corpus"
    log: f"{log_dir}/download_corpus/{{kind}}/{{dataset}}.log"
    conda: "envs/data.yml"
    threads: 1
#    group: 'data'
    cache: False # caching is broken in snakemake
    wildcard_constraints: kind="corpus|devset|eval"
    output: multiext(f"{original}/{{kind}}/{{dataset}}", f".{src}.gz", f".{trg}.gz")
    params: prefix=f"{original}/{{kind}}/{{dataset}}", dataset="{dataset}"
    shell: '''python pipeline/data/dataset_importer.py \
               --type corpus --dataset "{params.dataset}" --output_prefix "{params.prefix}"  >> {log} 2>&1'''

rule download_mono:
    message: "Downloading monolingual dataset"
    log: f"{log_dir}/download_mono/{{dataset}}.{{lang}}.log"
    conda: "envs/base.yml"
    threads: 1
#    group: 'data'
    cache: False # caching is broken in snakemake
    wildcard_constraints: lang=f"{src}|{trg}"
    output: f'{original}/mono/{{dataset}}.{{lang}}.gz'
    params: max_sent=lambda wildcards: mono_max_sent[wildcards.lang], dataset='{dataset}', lang='{lang}'
    shell: '''bash pipeline/data/download-mono.sh \
                "{params.dataset}" {params.lang} {params.max_sent} "{output}"  >> {log} 2>&1'''

# cleaning

rule clean_corpus:
    message: "Cleaning dataset"
    log: f"{log_dir}/clean_corpus/{{dataset}}.log"
    conda: "envs/opuscleaner.yml"
#    group: "clean_corpus"
    threads: workflow.cores
    input: multiext(f"{original}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz")
    output: multiext(f"{clean}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz")
    params: prefix_input=f"{original}/corpus/{{dataset}}",prefix_output=f"{clean}/corpus/{{dataset}}",
            dataset=lambda wildcards: dataset_norm(wildcards.dataset)
    shell: f'bash {clean_corpus_cmd} ' + '''"{params.prefix_input}" "{params.prefix_output}" {threads} {params.dataset} >> {log} 2>&1'''

rule clean_mono:
    message: "Cleaning monolingual dataset"
    log: f"{log_dir}/clean_mono/{{dataset}}.{{lang}}.log"
    conda: "envs/base.yml"
    threads: workflow.cores
#    group: "clean_mono{lang}"
    cache: False
    wildcard_constraints: lang=f"{src}|{trg}"
    input: f'{original}/mono/{{dataset}}.{{lang}}.gz'
    output: f'{clean}/mono/{{dataset}}.{{lang}}.gz'
    params: prefix_input=f"{original}/mono/{{dataset}}", prefix_output=f"{clean}/mono/{{dataset}}",
            dataset=lambda wildcards: dataset_norm(wildcards.dataset)
    shell: '''bash pipeline/clean/clean-mono.sh {wildcards.lang} "{params.prefix_input}" "{params.prefix_output}" \
                {threads} {params.dataset} >> {log} 2>&1'''

if use_bicleaner:
    rule kenlm:
        message: "Installing kenlm"
        log: f"{log_dir}/kenlm.log"
        conda: bicleaner_env
        threads: 4
#        group: 'setup'
        output: directory(f"{bin}/kenlm")
        shell: 'bash pipeline/setup/install-kenlm.sh {kenlm} {threads}  >> {log} 2>&1'

    rule bicleaner_pack:
        message: f"Downloading language pack for bicleaner"
        log: f"{log_dir}/bicleaner_pack.log"
        conda: bicleaner_env
#        group: "clean_corpus"
        threads: 1
        input: rules.kenlm.output
        output: directory(f"{biclean}/pack")
        params: src=src, trg=trg
        shell: '''python pipeline/bicleaner/download_pack.py \
                --src={params.src} --trg={params.trg} "{output}" >> {log} 2>&1'''

    rule bicleaner:
        message: f"Cleaning corpus using Bicleaner AI"
        log: f"{log_dir}/bicleaner/{{dataset}}.log"
        conda: bicleaner_env
#       group: "bicleaner"
        threads: gpus_num * 2
        resources: gpu=gpus_num
        input: ancient(rules.kenlm.output), multiext(f"{clean}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz"),
                pack=rules.bicleaner_pack.output
        output: multiext(f"{biclean}/corpus/{{dataset}}", f".{src}.gz", f".{trg}.gz")
        params:
            prefix_input=f"{clean}/corpus/{{dataset}}",prefix_output=f"{biclean}/corpus/{{dataset}}",
            threshold=lambda wildcards: bicl_dataset_thresholds[wildcards.dataset]
                                            if wildcards.dataset in bicl_dataset_thresholds
                                            else bicl_default_threshold
        shell: '''bash pipeline/bicleaner/bicleaner.sh \
                    "{params.prefix_input}" "{params.prefix_output}" {params.threshold} {threads} \
                    "{input.pack}" >> {log} 2>&1'''

rule merge_corpus:
    message: "Merging clean parallel datasets"
    log: f"{log_dir}/merge_corpus.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    # group: "clean_corpus"
    input:  expand(f"{clean_corpus_prefix}/{{dataset}}.{{lang}}.gz", dataset=train_datasets, lang=[src, trg]),
            bin=ancient(deduper)
    output: src=clean_corpus_src,trg=clean_corpus_trg
    params: prefix_output=clean_corpus_prefix, prefixes=expand(f"{clean_corpus_prefix}/{{dataset}}", dataset=train_datasets)
    shell: '''bash pipeline/clean/merge-corpus.sh "{params.prefix_output}" {params.prefixes} >> {log} 2>&1'''

rule merge_devset:
    message: "Merging devsets"
    log: f"{log_dir}/merge_devset.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    # group: "clean_corpus"
    input:  expand(f"{original}/devset/{{dataset}}.{{lang}}.gz", dataset=valid_datasets, lang=[src, trg]),
            bin=ancient(deduper)
    output: multiext(f"{original}/devset", f".{src}.gz", f".{trg}.gz")
    params: prefix_output=f"{original}/devset", prefixes=expand(f"{original}/devset/{{dataset}}", dataset=valid_datasets)
    shell: '''bash pipeline/clean/merge-corpus.sh "{params.prefix_output}" {params.prefixes} >> {log} 2>&1'''

rule merge_mono:
    message: "Merging clean monolingual datasets"
    log: f"{log_dir}/merge_mono_{{lang}}.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    #group "clean_mono{lang}"
    input:
        corpora=lambda wildcards: expand(f"{clean}/mono/{{dataset}}.{{lang}}.gz",
            dataset=mono_datasets[wildcards.lang], lang=wildcards.lang),
            bin=ancient(deduper)
    output: f"{clean}/mono.{{lang}}.gz"
    params: max_sent=lambda wildcards: mono_max_sent[wildcards.lang]
    shell: '''bash pipeline/clean/merge-mono.sh "{output}" {params.max_sent} {input.corpora} >> {log} 2>&1'''

# augmentation and teacher training

if not vocab_pretrained:
    rule train_vocab:
        message: "Training spm vocab"
        log: f"{log_dir}/train_vocab.log"
        conda: "envs/base.yml"
        threads: 2
        input: bin=ancient(spm_trainer), corpus_src=clean_corpus_src, corpus_trg=clean_corpus_trg
        output: vocab_path
        params: prefix_train=clean_corpus_prefix,prefix_test=f"{original}/devset"
        shell: '''bash pipeline/train/spm-vocab.sh "{input.corpus_src}" "{input.corpus_trg}" "{output}" {spm_sample_size} \
                    {threads} {spm_vocab_size} '{spm_user_defined_symbols}' >> {log} 2>&1'''

if do_train_backward:
    rule train_backward:
        message: "Training backward model"
        log: f"{log_dir}/train_backward.log"
        conda: "envs/train.yml"
        threads: gpus_num * 2
        resources: gpu=gpus_num
        #group 'backward'
        input:
            rules.merge_devset.output, train_src=clean_corpus_src,train_trg=clean_corpus_trg,
            bin=ancient(trainer), vocab=vocab_path,
        output:  model=f'{backward_dir}/{best_model}'
        params: prefix_train=clean_corpus_prefix,prefix_test=f"{original}/devset",
                args=get_args("training-backward")
        shell: '''bash pipeline/train/train.sh \
                    backward train {trg} {src} "{params.prefix_train}" "{params.prefix_test}" "{backward_dir}" \
                    "{input.vocab}" "{best_model_metric}" None {params.args} >> {log} 2>&1'''


checkpoint split_mono_trg:
    message: "Splitting monolingual trg dataset"
    log: f"{log_dir}/split_mono_trg.log"
    conda: "envs/base.yml"
    threads: 1
    input: corpora=f"{clean}/mono.{trg}.gz", bin=ancient(deduper)
    output: directory(f'{translated}/mono_trg')
    shell: '''python pipeline/translate/splitter.py \
                --output_dir={output} \
                --num_parts={split_chunks} \
                --compression_cmd=pigz \
                {input.corpora} >> {log} 2>&1'''

rule translate_mono_trg:
    message: "Translating monolingual trg dataset with backward model"
    log: f"{log_dir}/translate_mono_trg/{{part}}.log"
    conda: "envs/base.yml"
    threads: gpus_num * 2
    resources: gpu=gpus_num
    input:
        bin=ancient(decoder), file=f'{translated}/mono_trg/file.{{part}}.gz',
        vocab=vocab_path, model=f'{backward_dir}/{best_model}'
    output: f'{translated}/mono_trg/file.{{part}}.out'
    params: args = get_args("decoding-backward")
    shell: '''bash pipeline/translate/translate.sh "{input.file}" "{input.vocab}" {input.model} {params.args} \
            >> {log} 2>&1'''

rule collect_mono_trg:
    message: "Collecting translated mono trg dataset"
    log: f"{log_dir}/collect_mono_trg.log"
    conda: "envs/base.yml"
    threads: 4
    #group 'mono_trg'
    input:
        lambda wildcards: expand(f"{translated}/mono_trg/file.{{part}}.out",
            part=find_parts(wildcards, checkpoints.split_mono_trg))
    output: f'{translated}/mono.{src}.gz'
    params: src_mono=f"{clean}/mono.{trg}.gz",dir=directory(f'{translated}/mono_trg')
    shell: 'bash pipeline/translate/collect.sh "{params.dir}" "{output}" "{params.src_mono}" >> {log} 2>&1'


rule copy_backtranslated:
    message: "Copy back-translated dataset"
    log: f"{log_dir}/rule copy_backtranslated.log"
    conda: "envs/base.yml"
    threads: 4
    input:
        src=rules.collect_mono_trg.output,
        trg=rules.split_mono_trg.input
    output:
        src=f'{backtranslated}/corpus.{src}.gz',
        trg=f'{backtranslated}/corpus.{trg}.gz'
    params: dir=backtranslated,
    shell: '''
            mkdir -p {params.dir}
            cp {input.src} {output.src}
            cp {input.trg} {output.trg}
            '''

rule train_teacher:
    message: "Training teacher on all data"
    log: f"{log_dir}/train_teacher{{ens}}.log"
    conda: "envs/train.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    input:
        rules.merge_devset.output,
        rules.copy_backtranslated.output.src, rules.copy_backtranslated.output.trg,
        train_src=clean_corpus_src, train_trg=clean_corpus_trg,
        bin=ancient(trainer),
        vocab=vocab_path
    output: model=f'{teacher_base_dir}{{ens}}/{best_model}'
    params: prefix_clean=clean_corpus_prefix,
            prefix_backtranslated=backtranslated,
            prefix_test=f"{original}/devset",
            dir=directory(f'{teacher_base_dir}{{ens}}'),
            args=get_args("training-teacher")
    shell: '''bash pipeline/train/train.sh \
                teacher train {src} {trg} "{params.prefix_clean},{params.prefix_backtranslated}," "{params.prefix_test}" "{params.dir}" \
                "{input.vocab}" "{best_model_metric}" None {params.args} >> {log} 2>&1'''


### translation with teacher

# corpus

checkpoint split_corpus:
    message: "Splitting the corpus to translate"
    log: f"{log_dir}/split_corpus.log"
    conda: "envs/base.yml"
    threads: 1
    input: corpus_src=clean_corpus_src,corpus_trg=clean_corpus_trg
    output: directory(f"{translated}/corpus")
    shell: '''
            python pipeline/translate/splitter.py \
                --output_dir={output} \
                --num_parts={split_chunks} \
                --compression_cmd=pigz \
                {input.corpus_src} >> {log} 2>&1
            python pipeline/translate/splitter.py \
                --output_dir={output} \
                --num_parts={split_chunks} \
                --compression_cmd=pigz \
                {input.corpus_trg} >> {log} 2>&1
            '''

rule translate_corpus:
    message: "Translating corpus with teacher"
    log: f"{log_dir}/translate_corpus/{{part}}.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    input:
        ancient(decoder),
        file=f'{translated}/corpus/file.{{part}}.gz',
        vocab=vocab_path,
        teacher_models=expand(f"{teacher_base_dir}{{ens}}/{best_model}",ens=ensemble)
    output: f'{translated}/corpus/file.{{part}}.nbest'
    params: args=get_args('decoding-teacher')
    shell: '''bash pipeline/translate/translate-nbest.sh \
                "{input.file}" "{input.vocab}" {input.teacher_models} {params.args} >> {log} 2>&1'''

rule extract_best:
    message: "Extracting best translations for the corpus"
    log: f"{log_dir}/extract_best/{{part}}.log"
    conda: "envs/base.yml"
    threads: 1
    #group 'translate_corpus'
    input: nbest=f"{translated}/corpus/file.{{part}}.nbest", ref=f"{translated}/corpus/file.{{part}}.ref"
    output: f"{translated}/corpus/file.{{part}}.nbest.out"
    shell: 'python pipeline/translate/bestbleu.py -i {input.nbest} -r {input.ref} -m bleu -o {output} >> {log} 2>&1'

rule collect_corpus:
    message: "Collecting translated corpus"
    log: f"{log_dir}/collect_corpus.log"
    conda: "envs/base.yml"
    threads: 4
    #group 'translate_corpus'
    input:
        lambda wildcards: expand(f"{translated}/corpus/file.{{part}}.nbest.out",
            part=find_parts(wildcards, checkpoints.split_corpus))
    output: f'{translated}/corpus.{trg}.gz'
    params: src_corpus=clean_corpus_src
    shell: 'bash pipeline/translate/collect.sh {translated}/corpus {output} {params.src_corpus} >> {log} 2>&1'

# mono

checkpoint split_mono_src:
    message: "Splitting monolingual src dataset"
    log: f"{log_dir}/split_mono_src.log"
    conda: "envs/base.yml"
    threads: 1
    input: corpora=f"{clean}/mono.{src}.gz", bin=ancient(deduper)
    output: directory(f'{translated}/mono_src')
    shell: '''python pipeline/translate/splitter.py \
                --output_dir={output} \
                --num_parts={split_chunks} \
                --compression_cmd=pigz \
                {input.corpora} >> {log} 2>&1'''

rule translate_mono_src:
    message: "Translating monolingual src dataset with teacher"
    log: f"{log_dir}/translate_mono_src/{{part}}.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    input:
        file=f'{translated}/mono_src/file.{{part}}.gz',vocab=vocab_path,
        teacher_models=expand(f"{teacher_base_dir}{{ens}}/{best_model}",ens=ensemble),
        bin=ancient(decoder)
    output: f'{translated}/mono_src/file.{{part}}.out'
    params: args=get_args('decoding-teacher')
    shell: '''bash pipeline/translate/translate.sh "{input.file}" "{input.vocab}" {input.teacher_models} \
              {params.args} >> {log} 2>&1'''


rule collect_mono_src:
    message: "Collecting translated mono src dataset"
    log: f"{log_dir}/collect_mono_src.log"
    conda: "envs/base.yml"
    threads: 4
    #group 'mono_src'
    input:
       lambda wildcards: expand(f"{translated}/mono_src/file.{{part}}.out",
           part=find_parts(wildcards, checkpoints.split_mono_src))
    output: f'{translated}/mono.{trg}.gz'
    params: src_mono=f"{clean}/mono.{src}.gz",dir=f'{translated}/mono_src'
    shell: 'bash pipeline/translate/collect.sh "{params.dir}" "{output}" "{params.src_mono}" >> {log} 2>&1'

# merge

rule merge_translated:
    message: "Merging translated datasets"
    log: f"{log_dir}/merge_translated.log"
    conda: "envs/base.yml"
    threads: 4
    #group 'mono_src'
    input:
        src1=clean_corpus_src,src2=f"{clean}/mono.{src}.gz",
        trg1=rules.collect_corpus.output,trg2=rules.collect_mono_src.output,
        bin=ancient(deduper)
    output: res_src=f'{merged}/corpus.{src}.gz',res_trg=f'{merged}/corpus.{trg}.gz'
    shell: '''bash pipeline/translate/merge-corpus.sh \
                "{input.src1}" "{input.src2}" "{input.trg1}" "{input.trg2}" "{output.res_src}" "{output.res_trg}" \
                  >> {log} 2>&1'''

# train student

rule score:
    message: "Scoring"
    log: f"{log_dir}/score.log"
    conda: "envs/base.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    input:
        ancient(scorer),
        model=f'{backward_dir}/{best_model}', vocab=vocab_path,
        src_corpus=rules.merge_translated.output.res_src, trg_corpus=rules.merge_translated.output.res_trg
    output: f"{filtered}/scores.txt"
    params: input_prefix=f'{merged}/corpus'
    shell: '''bash pipeline/cefilter/score.sh \
                "{input.model}" "{input.vocab}" "{params.input_prefix}" "{output}" >> {log} 2>&1'''

rule ce_filter:
    message: "Cross entropy filtering"
    log: f"{log_dir}/ce_filter.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    resources: mem_mb=workflow.cores*5000
    input:
        src_corpus=rules.merge_translated.output.res_src,trg_corpus=rules.merge_translated.output.res_trg,
        scores=rules.score.output
    output: src_corpus=f"{filtered}/corpus.{src}.gz",trg_corpus=f"{filtered}/corpus.{trg}.gz"
    params: input_prefix=f'{merged}/corpus',output_prefix=f'{filtered}/corpus'
    shell: '''bash pipeline/cefilter/ce-filter.sh \
                "{params.input_prefix}" "{params.output_prefix}" "{input.scores}" >> {log} 2>&1'''

rule alignments:
    message: 'Training word alignment and lexical shortlists'
    log: f"{log_dir}/alignments.log"
    conda: "envs/base.yml"
    threads: workflow.cores
    input:
        ancient(spm_encoder), ancient(spm_exporter),
        src_corpus=rules.ce_filter.output.src_corpus,trg_corpus=rules.ce_filter.output.trg_corpus,
        vocab=vocab_path,
        fast_align=ancient(rules.fast_align.output.fast_align), atools=ancient(rules.fast_align.output.atools),
        extract_lex=ancient(rules.extract_lex.output)
    output: alignment=f'{align_dir}/corpus.aln.gz',shortlist=f'{align_dir}/lex.s2t.pruned.gz'
    params: input_prefix=f'{filtered}/corpus'
    shell: '''bash pipeline/alignment/generate-alignment-and-shortlist.sh \
                "{params.input_prefix}" "{input.vocab}" "{align_dir}" {threads} >> {log} 2>&1'''

rule train_student:
    message: "Training student"
    log: f"{log_dir}/train_student.log"
    conda: "envs/train.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    #group 'student'
    input:
        rules.merge_devset.output, ancient(trainer),
        train_src=rules.ce_filter.output.src_corpus, train_trg=rules.ce_filter.output.trg_corpus,
        alignments=rules.alignments.output.alignment,
        vocab=vocab_path
    output: model=f'{student_dir}/{best_model}'
    params: prefix_train=rules.ce_filter.params.output_prefix,prefix_test=f"{original}/devset",
            args=get_args("training-student")
    shell: '''bash pipeline/train/train.sh \
                student train {src} {trg} "{params.prefix_train}" "{params.prefix_test}" \
                "{student_dir}" "{input.vocab}" "{best_model_metric}" "{input.alignments}" {params.args} >> {log} 2>&1'''

# quantize

rule finetune_student:
    message: "Fine-tuning student"
    log: f"{log_dir}/finetune_student.log"
    conda: "envs/train.yml"
    threads: gpus_num*2
    resources: gpu=gpus_num
    #group 'student-finetuned'
    input:
        rules.merge_devset.output, ancient(trainer),
        train_src=rules.ce_filter.output.src_corpus, train_trg=rules.ce_filter.output.trg_corpus,
        alignments=rules.alignments.output.alignment, student_model=rules.train_student.output.model,
        vocab=vocab_path
    output: model=f'{student_finetuned_dir}/{best_model}'
    params: prefix_train=rules.ce_filter.params.output_prefix,prefix_test=f"{original}/devset",
            args=get_args("training-student-finetuned")
    shell: '''bash pipeline/train/train-student.sh \
                student finetune {src} {trg} "{params.prefix_train}" "{params.prefix_test}" \
                "{student_finetuned_dir}" "{input.vocab}" "{best_model_metric}" "{input.alignments}" --pretrained-model "{input.student_model}" {params.args} >> {log} 2>&1'''

rule quantize:
    message: "Quantization"
    log: f"{log_dir}/quntize.log"
    conda: "envs/base.yml"
    threads: 1
    input:
        ancient(bmt_decoder), ancient(bmt_converter),
        shortlist=rules.alignments.output.shortlist, model=rules.finetune_student.output.model,
        vocab=vocab_path, devset=f"{original}/devset.{src}.gz"
    output: model=f'{speed_dir}/model.intgemm.alphas.bin'
    shell: '''bash pipeline/quantize/quantize.sh \
                "{input.model}" "{input.vocab}" "{input.shortlist}" "{input.devset}" "{speed_dir}" >> {log} 2>&1'''

rule export:
    message: "Exporting models"
    log: f"{log_dir}/export.log"
    conda: "envs/base.yml"
    #group 'export'
    threads: 1
    input:
        model=rules.quantize.output.model,shortlist=rules.alignments.output.shortlist,
        vocab=vocab_path,marian=bmt_converter
    output:
        model=f'{exported_dir}/model.{src}{trg}.intgemm.alphas.bin.gz',
        shortlist=f'{exported_dir}/lex.50.50.{src}{trg}.s2t.bin.gz',
        vocab=f'{exported_dir}/vocab.{src}{trg}.spm.gz'
    shell:
        'bash pipeline/quantize/export.sh "{speed_dir}" "{input.shortlist}" "{input.vocab}" "{exported_dir}" >> {log} 2>&1'


### evaluation

rule evaluate:
    message: "Evaluating a model"
    log: f"{log_dir}/eval/eval_{{model}}_{{dataset}}.log"
    conda: "envs/base.yml"
    threads: gpus_num * 2
    resources: gpu=gpus_num
    #group '{model}'
    priority: 50
    wildcard_constraints:
        model="[\w-]+"
    input:
        ancient(decoder),
        data=multiext(f'{eval_data_dir}/{{dataset}}',f".{src}.gz",f".{trg}.gz"),
        models=lambda wildcards: f'{models_dir}/{wildcards.model}/{best_model}'
                                    if wildcards.model != 'teacher-ensemble'
                                    else [f'{teacher_base_dir}{ens}/{best_model}' for ens in ensemble]
    output:
        report(f'{eval_res_dir}/{{model}}/{{dataset}}.metrics',
            category='evaluation', subcategory='{model}', caption='reports/evaluation.rst')
    params:
        dataset_prefix=f'{eval_data_dir}/{{dataset}}',
        res_prefix=f'{eval_res_dir}/{{model}}/{{dataset}}',
        src_lng=lambda wildcards: src if wildcards.model != 'backward' else trg,
        trg_lng=lambda wildcards: trg if wildcards.model != 'backward' else src,
        decoder_config=lambda wildcards: f'{models_dir}/{wildcards.model}/{best_model}.decoder.yml'
                            if wildcards.model != 'teacher-ensemble'
                            else f'{teacher_base_dir}0/{best_model}.decoder.yml'
    shell: '''bash pipeline/eval/eval-gpu.sh "{params.res_prefix}" "{params.dataset_prefix}" \
             {params.src_lng} {params.trg_lng} "{params.decoder_config}" {input.models} >> {log} 2>&1'''

rule eval_quantized:
    message: "Evaluating qunatized student model"
    log: f"{log_dir}/eval_quantized_{{dataset}}.log"
    conda: "envs/base.yml"
    #group 'export'
    threads: 1
    priority: 50
    input:
        ancient(bmt_decoder),
        data=multiext(f'{eval_data_dir}/{{dataset}}',f".{src}.gz",f".{trg}.gz"),
        model=rules.quantize.output.model,
        shortlist=rules.alignments.output.shortlist,
        vocab=vocab_path
    output:
        report(f'{eval_speed_dir}/{{dataset}}.metrics', category='evaluation',
            subcategory='quantized', caption='reports/evaluation.rst')
    params:
        dataset_prefix=f'{eval_data_dir}/{{dataset}}',
        res_prefix=f'{eval_speed_dir}/{{dataset}}',
        decoder_config='../quantize/decoder.yml'
    shell: '''bash pipeline/eval/eval-quantized.sh "{input.model}" "{input.shortlist}" "{params.dataset_prefix}" \
            "{input.vocab}" "{params.res_prefix}" "{params.decoder_config}" >> {log} 2>&1'''
