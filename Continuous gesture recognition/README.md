# Continuous Gesture Recognition

This directory contains the data-preparation, training, and test-set inference code for continuous gesture recognition.

Open this directory as the MATLAB current folder before running the commands below.

## Files

- `data_origin.zip`: original experimental data
- `signal_segmentation.m`: prepares the `data/` directory
- `signal_classification.m`: trains the network and saves `Net.mat`
- `CNN_sample.m`: evaluates the pretrained model on the fixed test set
- `sparsity_analysis.m`: optional sparsity analysis
- `Net.mat`: pretrained model and data split

## Prepare the Data

Create a directory named `data_origin/` beside the MATLAB scripts. Extract the numbered class directories from `data_origin.zip` directly into it, and then run:

```matlab
signal_segmentation
```

This creates the processed dataset under `data/`. Data preparation uses the fixed random seed `rng(2026, 'twister')`. Channels containing only zeros remain unchanged.

## Run the Pretrained Model

After preparing the data, run:

```matlab
CNN_sample
```

The script reports the test sample count, overall accuracy, per-class accuracy, and a normalized confusion matrix.

## Retrain the Model

```matlab
signal_classification
CNN_sample
```

Running `signal_classification.m` overwrites `Net.mat` with the newly trained network and `splitInfo`.

Run `sparsity_analysis.m` only when the optional sparsity experiment is needed.
