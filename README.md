# PTBE

Sources involved in human-machine interaction based on parallel tribobiomimetic electroreceptors (PTBE), including three neural networks and one application. 

---

## Contents

- [System Requirements](#system-requirements)
  - [Hardware Requirements](#hardware-requirements)
  - [Software Requirements](#software-requirements)

---

## System Requirements

### Hardware Requirements

`PTBE` package requires only a standard computer with enough RAM to support the in-memory operations.
For optimal performance we recommend:

- **RAM:** 16 GB or more  
- **CPU:** 4+ cores @ 3.3 GHz or faster

Benchmark timings reported below were collected on a machine with 32 GB RAM, 12 cores @ 3.4 GHz, and a 50 Mbps internet connection.

### Software Requirements

#### OS Requirements

This package is supported for **Windows**. The package has been tested on the following systems:

- Windows 10 / 11

#### Python Version

- **Python 3.9.18** (64-bit)

#### Python Dependencies

`FLEXI` relies on the standard scientific-Python stack:

- numpy==1.26.0  
- scipy==1.11.4  
- scikit-learn==1.3.2  
- pandas==2.2.2  
- seaborn==0.13.2  
- torch==2.1.0  
- torchvision==0.16.0  
- matplotlib==3.8.2  
- librosa==0.10.1  
- os (built-in)

(All dependencies will be installed automatically when you run the setup script.)

---

## Installation Guide

### Install from GitHub

git clone https://github.com/Adai2020/FLEXI.git  
cd FLEXI  
python3 setup.py install  

The entire process typically finishes in ~10 minutes on the recommended hardware.

## Quick Demo

### Instructions to run on data

1. Clone or download the repository.  
2. Open the notebook `FLEXI-1-ECG-test.ipynb`.  
3. Double-click the notebook to launch Jupyter.  
4. Select **Kernel → Change Kernel** and choose the Python environment you just created.  
5. Click **Cell → Run All** to execute the entire demo.

### Expected output

The network has 122 weights that need to be deployed.  
NET_1k_ECG(...)  
The test accuracy after quantization is: 99.20%  

### Expected run time

3s

## Data Usage
### Example: MNIST
#### Two ways to download MNIST:
From the official MNIST website, download the four gzipped files.  
Use Python libraries like torchvision.datasets.MNIST (automatically downloads when initialized).  
#### File placement:
Place the downloaded files in the following directory structure within FLEXI:

raw\MNIST\raw\
  t10k-images-idx3-ubyte.gz  
  t10k-labels-idx1-ubyte.gz  
  train-images-idx3-ubyte.gz  
  train-labels-idx1-ubyte.gz  



---

## License

This project is licensed under the **MIT License**.

**Disclaimer**: This project contains MATLAB code developed by the author. 
A valid MATLAB license from The MathWorks, Inc. is required to run this code. 
The code provided here is for research/demonstration purposes only and is 
not affiliated with or endorsed by The MathWorks, Inc.



