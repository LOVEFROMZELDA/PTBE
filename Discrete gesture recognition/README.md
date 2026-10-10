# Discrete Gesture Recognition

This directory contains the data-preparation, training, and test-set inference code for discrete gesture recognition.

Open this directory as the MATLAB current folder before running the commands below.

## Files

- `data_origin.z01` and `data_origin.zip`: split ZIP archive containing the original experimental data
- `signal_segmentation.m`: prepares the `data/` directory
- `signal_classification.m`: trains the network and saves `Net.mat`
- `CNN_sample.m`: evaluates the pretrained model on the fixed test set
- `hyperparameter_ablation.m`: optional hyperparameter experiments
- `Net.mat`: pretrained model, normalization statistics, and data split

## Prepare the Data

Keep `data_origin.z01` and `data_origin.zip` in the same directory. Use an archive tool that supports split ZIP files to extract `data_origin.zip`, and place the numbered class directories in a directory named `data_origin/` beside the MATLAB scripts. Then run:

```matlab
signal_segmentation
```

This creates the processed dataset under `data/`. Data preparation uses the fixed random seed `rng(2026, 'twister')`.

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

Running `signal_classification.m` overwrites `Net.mat` with the newly trained network, normalization statistics, and `splitInfo`.
