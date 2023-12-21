---
layout: default
title: Home
nav_order: 1
description: "Firefox Translations Training documentation."
permalink: /
---

# Firefox Translations training
Training pipelines for Firefox Translations machine translation models.

The trained models are hosted in [firefox-translations-models](https://github.com/mozilla/firefox-translations-models/) repository,
compatible with [bergamot-translator](https://github.com/mozilla/bergamot-translator) and 
power the Firefox web page translation starting with version 118. 

The pipeline was originally developed as a part of [Bergamot](https://browser.mt/) project  that focuses on improving client-side machine translation in a web browser.

## Training pipeline

The pipeline is capable of training a translation model for a language pair end to end. 
Translation quality depends on the chosen datasets, data cleaning procedures and hyperparameters. 
Some settings, especially low resource languages might require extra tuning.

We use [Marian](https://marian-nmt.github.io), the fast neural machine translation engine .

## Learning resources

- High level overview [post on Mozilla Hacks](https://hacks.mozilla.org/2022/06/training-efficient-neural-network-models-for-firefox-translations/)
- [Model training guide](training-guide.md) - practical advice on how to use the pipeline
- [Reference papers](references.md)


## Acknowledgements
This project uses materials developed by:
- Bergamot project ([github](https://github.com/browsermt), [website](https://browser.mt/)) that has received funding from the European Union’s Horizon 2020 research and innovation programme under grant agreement No 825303
- HPLT project ([github](https://github.com/hplt-project), [website](https://hplt-project.org/)) that has received funding from the European Union’s Horizon Europe research and innovation programme under grant agreement No 101070350 and from UK Research and Innovation (UKRI) under the UK government’s Horizon Europe funding guarantee [grant number 10052546]
- OPUS-MT project ([github](https://github.com/Helsinki-NLP/Opus-MT), [website](https://opus.nlpl.eu/))
- Many other open source projects and research papers (see [References](references.md))
