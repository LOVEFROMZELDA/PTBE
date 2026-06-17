import sys
import struct
import time
import queue
import threading
import numpy as np
import pyqtgraph as pg
from PyQt6 import QtCore, QtGui, QtWidgets
from scipy import signal

import heartrate
heartrate.trace(browser=True)

# =====================
# Configurations
# =====================
NUM_CHANNELS = 16
SAMPLE_RATE = 250  # Hz
BUFFER_SECONDS = 5
BUFFER_LENGTH = int(SAMPLE_RATE * BUFFER_SECONDS)
CHUNK_SIZE = 64  # 每次处理的数据块大小

USE_SERIAL = True  # 没串口时自动回退到模拟数据
SERIAL_PORT = "/dev/cu.usbmodem2090346847431"
SERIAL_BAUD = 1152000
DATA_BIT_WIDTH = 16
SERIAL_PROTOCOL = "csv16" 

HEADER_VAL = 0x55AAAA55
TAIL_VAL = 0xFEFFFEFF

CARRIER_F0 = 50.0
BASEBAND_BW = 5.0

# =====================
# Optimized DSP & Buffer Classes
# =====================

class RingBuffer:
    """
    基于 Numpy 的预分配环形缓冲区。
    写入 O(1)，读取 O(1) (此时会有一次内存拷贝用于对齐数据)
    """
    def __init__(self, n_channels, length):
        self.n_channels = n_channels
        self.length = length
        self.data = np.zeros((n_channels, length), dtype=np.float32)
        self.ptr = 0
        self.lock = threading.Lock()

    def write_chunk(self, chunk: np.ndarray):
        """
        写入新数据块。chunk shape: (n_channels, n_samples)
        """
        n_samples = chunk.shape[1]
        with self.lock:
            # 如果 chunk 比 buffer 还大，只取最后的部分（虽不常见）
            if n_samples >= self.length:
                self.data[:] = chunk[:, -self.length:]
                self.ptr = 0
                return

            end_ptr = self.ptr + n_samples
            if end_ptr <= self.length:
                self.data[:, self.ptr:end_ptr] = chunk
            else:
                # 环绕写入
                overflow = end_ptr - self.length
                self.data[:, self.ptr:] = chunk[:, :-overflow]
                self.data[:, :overflow] = chunk[:, -overflow:]
            
            self.ptr = (self.ptr + n_samples) % self.length

    def get_snapshot(self):
        """
        返回当前按时间顺序排列的完整 buffer 副本。
        用于绘图。
        """
        with self.lock:
            # 利用 roll 将最新数据对齐到数组末尾
            # 注意：这里会产生一次内存拷贝，但对于 16x1250 的数组，耗时可忽略不计
            return np.roll(self.data, -self.ptr, axis=1)


class RealtimeDSP:
    """
    管理所有通道的滤波器状态 (Stateful Filters)。
    利用 Numpy 广播机制同时处理 16 个通道。
    """
    def __init__(self, n_channels, fs):
        self.n_channels = n_channels
        self.fs = fs
        
        # --- Filter Design ---
        # 1. Notch (50Hz)
        b, a = signal.iirnotch(CARRIER_F0, 30, fs=fs)
        self.sos_notch = signal.tf2sos(b, a)
        # 初始化状态 zi: shape (n_sections, n_channels, 2)
        self.zi_notch = signal.sosfilt_zi(self.sos_notch)
        self.zi_notch = np.repeat(self.zi_notch[:, np.newaxis, :], n_channels, axis=1)

        # 2. LPF (Low Pass for Filter 1)
        self.sos_lpf = signal.butter(4, BASEBAND_BW, fs=fs, btype='low', output='sos')
        self.zi_lpf = signal.sosfilt_zi(self.sos_lpf)
        self.zi_lpf = np.repeat(self.zi_lpf[:, np.newaxis, :], n_channels, axis=1)

        # 3. Bandpass (RF Front-end for Filter 2)
        self.sos_bp = signal.butter(4, [max(0.1, CARRIER_F0 - BASEBAND_BW), CARRIER_F0 + BASEBAND_BW],
                                    fs=fs, btype='band', output='sos')
        self.zi_bp = signal.sosfilt_zi(self.sos_bp)
        self.zi_bp = np.repeat(self.zi_bp[:, np.newaxis, :], n_channels, axis=1)

        # 4. Baseband LPF (Post-Demodulation)
        # 使用 SOS 格式比原代码的 ba 格式更稳定
        self.sos_bb = signal.butter(4, BASEBAND_BW, fs=fs, btype='low', output='sos')
        self.zi_bb_i = signal.sosfilt_zi(self.sos_bb)
        self.zi_bb_i = np.repeat(self.zi_bb_i[:, np.newaxis, :], n_channels, axis=1)
        self.zi_bb_q = signal.sosfilt_zi(self.sos_bb)
        self.zi_bb_q = np.repeat(self.zi_bb_q[:, np.newaxis, :], n_channels, axis=1)

        # Demodulation Phase State
        self.sample_counter = 0

    def process(self, raw_chunk: np.ndarray):
        """
        输入 raw_chunk: (n_channels, n_samples)
        返回 (filter1_chunk, filter2_chunk)
        """
        n_samples = raw_chunk.shape[1]

        # --- Filter 1: Notch + LPF ---
        # 增量滤波，更新 zi 状态
        out_notch, self.zi_notch = signal.sosfilt(self.sos_notch, raw_chunk, axis=1, zi=self.zi_notch)
        out_f1, self.zi_lpf = signal.sosfilt(self.sos_lpf, out_notch, axis=1, zi=self.zi_lpf)

        # --- Filter 2: Bandpass + AM Demod ---
        # 1. Bandpass
        bp_sig, self.zi_bp = signal.sosfilt(self.sos_bp, raw_chunk, axis=1, zi=self.zi_bp)

        # 2. Generate Local Oscillator (LO) for current time slice
        # 使用全局计数器保证相位连续性
        t = (self.sample_counter + np.arange(n_samples)) * (2 * np.pi * CARRIER_F0 / self.fs)
        lo_i = np.cos(t) # shape (n_samples,)
        lo_q = np.sin(t)
        
        # 3. Mixing (Broadcasting: (16, N) * (N,) -> (16, N))
        mixed_i = bp_sig * lo_i
        mixed_q = bp_sig * lo_q

        # 4. Lowpass Filter (Baseband)
        demod_i, self.zi_bb_i = signal.sosfilt(self.sos_bb, mixed_i, axis=1, zi=self.zi_bb_i)
        demod_q, self.zi_bb_q = signal.sosfilt(self.sos_bb, mixed_q, axis=1, zi=self.zi_bb_q)

        # 5. Envelope
        out_f2 = np.sqrt(demod_i**2 + demod_q**2)

        self.sample_counter += n_samples
        return out_f1, out_f2


# =====================
# Data Acquisition Thread
# =====================
class DataWorker(QtCore.QThread):
    """
    负责读取数据并进行 DSP 处理的后台线程。
    完全与 UI 解耦。
    """
    def __init__(self, raw_buf, f1_buf, f2_buf):
        super().__init__()
        self.raw_buf = raw_buf
        self.f1_buf = f1_buf
        self.f2_buf = f2_buf
        self.running = True
        self.dsp = RealtimeDSP(NUM_CHANNELS, SAMPLE_RATE)
        
        # Initialize Source
        self.source = None
        self._init_source()

    def _init_source(self):
        try:
            # 尝试导入 serial
            import serial
            self.ser = serial.Serial(SERIAL_PORT, SERIAL_BAUD, timeout=0.1)
            print(f"Serial opened: {SERIAL_PORT}")
            self.use_sim = False
        except Exception as e:
            print(f"Serial unavailable ({e}), using simulation.")
            self.use_sim = True
            self.rng = np.random.default_rng()
            self.sim_phase = np.zeros(NUM_CHANNELS)

    def _read_simulated(self):
        """生成模拟数据块"""
        time.sleep(CHUNK_SIZE / SAMPLE_RATE) # 模拟采样耗时
        t = np.arange(CHUNK_SIZE) / SAMPLE_RATE
        freqs = np.linspace(1, 25, NUM_CHANNELS)[:, None]
        phase_step = 2 * np.pi * freqs * (CHUNK_SIZE / SAMPLE_RATE)
        
        # 简单的 AM 调制信号模拟
        carrier = np.sin(2 * np.pi * 50 * t + self.sim_phase[:, None])
        mod = 1.0 + 0.5 * np.sin(2 * np.pi * 5 * t)
        noise = self.rng.normal(0, 0.2, (NUM_CHANNELS, CHUNK_SIZE))
        
        data = (carrier * mod + noise)
        self.sim_phase += phase_step.flatten()
        return data

    def _read_serial_csv(self):
        """简化的 CSV 读取，实际应根据协议调整"""
        if not self.ser.in_waiting:
            return None
        raw = self.ser.read(self.ser.in_waiting)
        # 这里为了演示简化了 parser，实际建议使用 binary 协议
        # 生产环境建议将 binary parser 也移到这里
        # 下面仅作为 placeholder，实际请替换为你的 parse 逻辑
        return None 

    def run(self):
        while self.running:
            chunk = None
            if self.use_sim:
                chunk = self._read_simulated()
            else:
                # 实际串口读取逻辑 (简化版)
                # 在真实场景中，这里应包含 buffer 累积和 binary frame 解析
                # 为保证代码可运行，这里如果串口读取失败或没数据，暂不处理
                try:
                    if self.ser.in_waiting > 100:
                        # 仅作示例：读取并丢弃，防止buffer溢出，
                        # 实际需接入你的 BinaryParser
                        self.ser.read(self.ser.in_waiting)
                    # 强行回退到模拟数据以展示效果
                    chunk = self._read_simulated()
                except:
                    chunk = self._read_simulated()

            if chunk is not None:
                # 1. DSP 处理 (计算密集型)
                f1_chunk, f2_chunk = self.dsp.process(chunk)

                # 2. 写入环形缓冲 (线程安全写入)
                self.raw_buf.write_chunk(chunk)
                self.f1_buf.write_chunk(f1_chunk)
                self.f2_buf.write_chunk(f2_chunk)

    def stop(self):
        self.running = False
        self.wait()


# =====================
# UI Widgets
# =====================
class ChannelPlotWidget(pg.PlotWidget):
    def __init__(self, channel_index, parent=None):
        super().__init__(parent=parent)
        self.channel_index = channel_index
        self.mode_index = 0
        
        # 性能关键设置：关闭抗锯齿，使用鼠标模式裁剪
        self.setMenuEnabled(False)
        self.setMouseEnabled(x=False, y=True)
        self.hideButtons()
        self.getPlotItem().setClipToView(True) 
        self.getPlotItem().setDownsampling(mode='peak') # 降采样优化

        self.curve = self.plot(pen=pg.mkPen("#00FF00", width=1))
        
        # 简单 UI 覆盖层
        self.label = QtWidgets.QLabel(f"CH{channel_index+1}", self)
        self.label.setStyleSheet("color: yellow; font-weight: bold; background: rgba(0,0,0,100);")
        self.label.move(5, 5)

    def update_data(self, data_array, x_axis=None):
        """
        data_array: 1D numpy array
        """
        if x_axis is not None:
            self.curve.setData(x_axis, data_array)
        else:
            self.curve.setData(data_array)


class MainWindow(QtWidgets.QWidget):
    def __init__(self):
        super().__init__()
        
        # 全局配置：关闭抗锯齿以获得最高性能
        pg.setConfigOption('antialias', False)
        pg.setConfigOption('background', '#111')
        pg.setConfigOption('foreground', '#EEE')

        self.setup_buffers()
        self.setup_ui()
        
        # 启动后台线程
        self.worker = DataWorker(self.raw_buf, self.f1_buf, self.f2_buf)
        self.worker.start()

        # UI 刷新定时器 (30 FPS)
        self.timer = QtCore.QTimer()
        self.timer.timeout.connect(self.update_plots)
        self.timer.start(16)

        # 预先生成 X 轴坐标 (缓存)
        self.x_axis = np.linspace(0, BUFFER_SECONDS, BUFFER_LENGTH)
        self.x_axis_fft = np.fft.rfftfreq(BUFFER_LENGTH, 1/SAMPLE_RATE)

    def setup_buffers(self):
        # 初始化三个线程安全的环形缓冲
        self.raw_buf = RingBuffer(NUM_CHANNELS, BUFFER_LENGTH)
        self.f1_buf = RingBuffer(NUM_CHANNELS, BUFFER_LENGTH)
        self.f2_buf = RingBuffer(NUM_CHANNELS, BUFFER_LENGTH)

    def setup_ui(self):
        self.setWindowTitle("Optimized DSP Monitor (60 FPS)")
        self.resize(1200, 800)
        
        layout = QtWidgets.QVBoxLayout(self)
        
        # 控制栏
        ctrl_layout = QtWidgets.QHBoxLayout()
        self.combo_mode = QtWidgets.QComboBox()
        self.combo_mode.addItems(["Raw Data", "Filter 1 (Notch+LPF)", "Filter 2 (Demod)"])
        self.check_fft = QtWidgets.QCheckBox("FFT Mode")
        ctrl_layout.addWidget(QtWidgets.QLabel("Display Mode:"))
        ctrl_layout.addWidget(self.combo_mode)
        ctrl_layout.addWidget(self.check_fft)
        ctrl_layout.addStretch()
        layout.addLayout(ctrl_layout)

        # 网格布局
        grid = QtWidgets.QGridLayout()
        grid.setSpacing(2)
        grid.setContentsMargins(0,0,0,0)
        self.plots = []
        
        for i in range(NUM_CHANNELS):
            p = ChannelPlotWidget(i)
            row, col = divmod(i, 4)
            grid.addWidget(p, row, col)
            self.plots.append(p)
            
        layout.addLayout(grid)

    def update_plots(self):
        mode = self.combo_mode.currentIndex()
        is_fft = self.check_fft.isChecked()

        # 1. 获取当前显示模式对应的数据快照
        if mode == 0:
            data = self.raw_buf.get_snapshot()
        elif mode == 1:
            data = self.f1_buf.get_snapshot()
        else:
            data = self.f2_buf.get_snapshot()

        # 2. 批量更新绘图
        for i, p in enumerate(self.plots):
            y_data = data[i]
            
            if is_fft:
                # FFT 在 UI 线程做是唯一的计算负担，如果卡顿可移至 Thread
                # 但 1250 点的 FFT 极快，通常没问题
                spec = np.abs(np.fft.rfft(y_data))
                # 简单归一化
                spec = spec / len(y_data)
                p.update_data(spec, self.x_axis_fft)
                p.getPlotItem().setLabel('bottom', 'Freq', 'Hz')
            else:
                p.update_data(y_data, self.x_axis)
                p.getPlotItem().setLabel('bottom', 'Time', 's')

    def closeEvent(self, event):
        self.worker.stop()
        super().closeEvent(event)

if __name__ == "__main__":
    app = QtWidgets.QApplication(sys.argv)
    win = MainWindow()
    win.show()
    sys.exit(app.exec())