# PTBE

Source code for human-machine interaction based on parallel tribobiomimetic electroreceptors (PTBE), including three neural-network tasks and one application.

## System Requirements

### Hardware

A standard computer can run the inference demos. A CUDA-capable GPU is recommended for training.

- **RAM:** 16 GB or more
- **CPU:** 4+ cores at 3.3 GHz or faster
- **Inference VRAM:** 4 GB minimum, 8 GB or more recommended
- **Training VRAM:** 12 GB or more recommended

### Software

- Windows 10 or 11
- MATLAB R2022b
- Deep Learning Toolbox v14.5
- MATLAB Compiler v8.5
- Parallel Computing Toolbox v7.7
- Signal Processing Toolbox v9.1
- Statistics and Machine Learning Toolbox v12.4
- MATLAB Runtime R2022b

Install MATLAB and the required products from the [MathWorks website](https://www.mathworks.com/downloads).

## Neural-Network Code

| Task | Directory | Test demo |
|---|---|---|
| Discrete gesture recognition | `Discrete gesture recognition/` | `CNN_sample.m` |
| Continuous gesture recognition | `Continuous gesture recognition/` | `CNN_sample.m` |
| 200-by-200 virtual array recognition | `200×200 virtual array/` | `CNN_sample.m` |

Each task directory contains its data archive, data-preparation code, training code, pretrained model, test-set demo, and a task-specific README. Follow that README to place the data and run the scripts.

All stochastic data-preparation and training entry scripts use the fixed random seed `rng(2026, 'twister')`.

## Application Demo

1. Clone or download the repository.
2. Open `Interaction interface/App/for_redistribution_files_only/App.exe`.
3. Choose a **Task** and click **Initialize**.
4. Click **Load Data**.
5. Click **Identify Data** to identify the data category.
6. Click **Clear Data** before loading the next sample.

The application displays the predicted probability distribution and corresponding scenario. A typical run takes approximately one minute.

## License

This project is licensed under the **MIT License**.

**Disclaimer:** This project contains MATLAB code developed by the author. A valid MATLAB license from The MathWorks, Inc. is required to run the code. The code is provided for research and demonstration purposes only and is not affiliated with or endorsed by The MathWorks, Inc.
