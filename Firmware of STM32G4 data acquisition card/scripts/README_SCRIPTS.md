# PCA9635-ADC 控制脚本使用说明

本目录包含用于简化PCA9635-ADC系统配置的脚本工具。

## 文件说明

### 1. command_wizard.py / command_wizard.bat (推荐！)
**交互式命令构建向导 - 最简单易用**

#### 特点
- ✅ 无需记忆复杂参数
- ✅ 逐步引导式输入
- ✅ 自动验证参数范围
- ✅ 提供友好的选项菜单
- ✅ 显示详细配置摘要
- ✅ 生成完整命令字符串
- ✅ 可保存命令到文件

#### 依赖
- **Python版本**: Python 3.6+, 无需额外库
- **批处理版本**: 无依赖，Windows原生支持

#### 使用方法

**Python版本:**
```bash
python command_wizard.py
```

**批处理版本 (无需Python):**
```bash
command_wizard.bat
```

#### 使用演示

运行后会看到主菜单:
```
============================================================
  PCA9635-ADC 命令构建向导
============================================================

请选择要生成的命令:
  1. SET_CH  - 配置监测通道
  2. GET_CH  - 查询单个通道
  3. GET_ALL - 查询所有通道
  4. EN_CH   - 启用通道
  5. DIS_CH  - 禁用通道
  6. CLR_CH  - 清除通道
  7. CLR_ALL - 清除所有通道
  0. 退出

请选择 (0-7): 
```

选择配置通道后，逐步引导:
```
[1/8] 通道索引 (0-15)
  通道索引: 0

[2/8] ADC通道 (0-15)
  ADC通道: 5

[3/8] 监测类型
  1. RISING   - 上升沿触发
  2. FALLING  - 下降沿触发
  3. BOTH     - 双向触发
  4. ABOVE    - 高于阈值
  5. BELOW    - 低于阈值
  选择类型 (1-5): 4

...
```

最终生成:
```
============================================================
生成的UART命令:
============================================================

  SET_CH 0 5 3 2048 0 255 0 2

============================================================
```

### 2. pca_control.py (高级用户)
**Python串口控制工具 - 直接执行命令**

#### 依赖
- Python 3.6+
- pyserial 库

安装依赖:
```bash
pip install pyserial
```

#### 使用方法

**命令行模式:**
```bash
# 配置通道
python scripts\pca_control.py -p COM3 set 0 5 ABOVE 2048 0 255 0 MAPPED

# 查询通道
python scripts\pca_control.py -p COM3 get 0

# 查询所有
python scripts\pca_control.py -p COM3 getall

# 清除配置
python scripts\pca_control.py -p COM3 clearall
```

**交互模式 (推荐):**
```bash
python scripts\pca_control.py -p COM3 interactive
```

进入交互模式后，可以直接输入命令:
```
PCA> SET_CH 0 5 3 2048 0 255 0 2
PCA> GET_CH 0
PCA> GET_ALL
PCA> help
PCA> quit
```

#### 参数说明

**set 命令:**
```
set <ch> <adc_ch> <type> <thresh> <pca_ch> <intensity> <duration> <mode>
```

- `ch`: 监测通道索引 (0-15)
- `adc_ch`: ADC通道 (0-15)
- `type`: 监测类型
  - `RISING` 或 `0`: 上升沿
  - `FALLING` 或 `1`: 下降沿
  - `BOTH` 或 `2`: 双向
  - `ABOVE` 或 `3`: 高于阈值
  - `BELOW` 或 `4`: 低于阈值
- `thresh`: 阈值 (0-4095)
- `pca_ch`: PCA9635通道 (0-15)
- `intensity`: PWM强度 (0-255)
- `duration`: 持续时间(ms, 0=无限)
- `mode`: 响应模式
  - `NONE` 或 `0`: 无响应
  - `DURATION` 或 `1`: 定时脉冲
  - `MAPPED` 或 `2`: 直接映射
  - `LATCHED` 或 `3`: 锁存

### 3. quick_test.bat
**快速测试脚本**

自动化运行常见测试场景，适合首次测试。

#### 使用方法
```bat
quick_test.bat
```

运行后会提示输入串口号，然后自动:
1. 清除所有配置
2. 配置光控LED示例 (通道0)
3. 配置温度报警示例 (通道1)
4. 显示所有配置

## 使用示例

### 示例1: 光控LED
当光线暗时(ADC < 1000)，LED亮起
```bash
python scripts\pca_control.py -p COM3 set 0 0 BELOW 1000 0 255 0 MAPPED
```

### 示例2: 温度报警
温度超过阈值时，LED闪烁2秒
```bash
python scripts\pca_control.py -p COM3 set 1 1 RISING 3000 1 200 2000 DURATION
```

### 示例3: 接近检测
物体靠近或远离时都触发
```bash
python scripts\pca_control.py -p COM3 set 2 2 BOTH 2500 2 255 0 DURATION
```

### 示例4: 多通道配置
配置4个通道同时工作:
```bash
python scripts\pca_control.py -p COM3 set 0 0 ABOVE 1000 0 255 0 MAPPED
python scripts\pca_control.py -p COM3 set 1 1 ABOVE 1500 1 200 0 MAPPED
python scripts\pca_control.py -p COM3 set 2 2 ABOVE 2000 2 150 0 MAPPED
python scripts\pca_control.py -p COM3 set 3 3 ABOVE 2500 3 100 0 MAPPED
```

## 交互模式详细说明

交互模式提供了一个实时控制台，可以快速测试和调试。

### 启动交互模式
```bash
python scripts\pca_control.py -p COM3 interactive
```

### 交互模式命令

在交互模式下，直接输入原始UART命令:

```
PCA> SET_CH 0 5 3 2048 0 255 0 2
→ SET_CH 0 5 3 2048 0 255 0 2
✓ 通道 0 配置成功

PCA> GET_CH 0
→ GET_CH 0
✓ CH_CFG 0 ADC:5 TYPE:ABOVE THRESH:2048 PCA:0 INT:255 DUR:0 MODE:MAPPED EN:1 ACT:0

PCA> GET_ALL
→ GET_ALL
  CH_CFG 0 ADC:5 TYPE:ABOVE THRESH:2048 PCA:0 INT:255 DUR:0 MODE:MAPPED EN:1 ACT:0
✓ 共有 1 个已配置通道

PCA> help
[显示帮助信息]

PCA> quit
再见!
```

### 交互模式优势
- ✓ 实时响应，无需重新运行脚本
- ✓ 可以快速测试不同配置
- ✓ 查看实时反馈
- ✓ 支持命令历史 (上下方向键)

## 常见问题

### Q: Python脚本报错 "No module named 'serial'"
**A:** 需要安装pyserial库:
```bash
pip install pyserial
```

### Q: 找不到串口
**A:** 
1. 检查设备管理器确认串口号
2. 确认串口未被其他程序占用
3. 尝试拔插USB重新枚举

### Q: 命令无响应
**A:**
1. 检查波特率是否匹配 (默认115200)
2. 确认STM32程序正确烧录
3. 检查UART接线 (TX-RX交叉)

## 扩展开发

### 添加自定义命令

在`pca_control.py`中添加新方法:

```python
def custom_scenario(self):
    """自定义场景"""
    # 配置多个通道
    self.set_channel(0, 0, 'ABOVE', 1000, 0, 255, 0, 'MAPPED')
    self.set_channel(1, 1, 'ABOVE', 1500, 1, 200, 0, 'MAPPED')
    # 查询状态
    self.get_all()
```

### 创建测试套件

创建新的批处理脚本运行一系列测试:

```bat
@echo off
echo 运行测试套件...

python scripts\pca_control.py -p %PORT% clearall
python scripts\pca_control.py -p %PORT% set 0 0 ABOVE 1000 0 255 0 MAPPED
python scripts\pca_control.py -p %PORT% get 0

echo 测试完成！
```

## 最佳实践

1. **首次使用**: 使用`command_wizard`熟悉命令格式
2. **快速验证**: 运行`quick_test.bat`测试系统
3. **日常配置**: 使用`command_wizard`生成命令，复制到串口终端
4. **高级调试**: 使用`pca_control.py`的`interactive`模式实时控制
5. **自动化**: 编写批处理或Python脚本批量配置
6. **验证配置**: 每次修改后用`GET_ALL`命令验证
7. **重置**: 遇到问题时先执行`CLR_ALL`清空配置

## 技术支持

遇到问题请检查:
1. 硬件连接 (I2C, UART, 电源)
2. 串口设置 (波特率, 端口号)
3. Python和pyserial版本
4. 防火墙或杀毒软件阻止

参考主README.md中的故障排除部分。
