# PTBE

Sources involved in human-machine interaction based on parallel tribobiomimetic electroreceptors (PTBE), including three neural networks and one application. 

---

## Contents

- [System Requirements](#system-requirements)
  - [Hardware Requirements](#hardware-requirements)
  - [Software Requirements](#software-requirements)
- [Installation Guide](#installation-guide)
- [Quick Demo](#quick-demo)

---

## System Requirements

### Hardware Requirements

Sources of `PTBE` requires a standard computer with enough VRAM to support the inference and training.
For optimal performance we recommend:

- **RAM:** 16 GB or more  
- **CPU:** 4+ cores @ 3.3 GHz or faster
- **Inference minimum VRAM**: 4GB (8GB+ recommended)
- **Training recommended VRAM**: 12GB+ (this project was trained on an RTX 4070 SUPER 16GB)

### Software Requirements

#### OS Requirements

The package has been tested on the following systems:

- Windows 10 / 11

#### MATLAB Version

- **MATLAB R2022b**

#### MATLAB Add-On

- **Deep Learning Toolbox** v14.5
- **MATLAB Compiler** v8.5
- **Parallel Computing Toolbox** v7.7
- **Signal Processing Toolbox** v9.1
- **Statistics and Machine Learning Toolbox** v12.4
- **MATLAB Runtime(R2022b)**

---

## Installation Guide

### Install from GitHub

Visit the official MathWorks website https://www.mathworks.com/downloads to get MATLAB.
Install all the Add-On before getting started.

## Quick Demo

### Instructions to run the application

1. Clone or download the repository.  
2. Open `Interaction interface/App/for_redistribution_files_only/App.exe`.  
3. Choose one **Task**. Click **Intialize**.
4. Click **Load Data** to load the data.
5. Click **Identify Data** to identify the catogory of this data.
6. Click **Clear Data** to get ready for the next cycle of loading and identification.

### Expected output

The app will display the probability distribution of the data loaded and the corresponding scenario.

### Expected run time

1min

---

## License

This project is licensed under the **MIT License**.

**Disclaimer**: This project contains MATLAB code developed by the author. 
A valid MATLAB license from The MathWorks, Inc. is required to run this code. 
The code provided here is for research/demonstration purposes only and is 
not affiliated with or endorsed by The MathWorks, Inc.
