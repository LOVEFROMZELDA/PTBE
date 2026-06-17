#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
PCA9635-ADC 命令构建向导
交互式引导生成UART命令字符串
"""

import sys

# 监测类型
MONITOR_TYPES = {
    '1': ('RISING', 0, '上升沿触发'),
    '2': ('FALLING', 1, '下降沿触发'),
    '3': ('BOTH', 2, '双向触发'),
    '4': ('ABOVE', 3, '高于阈值'),
    '5': ('BELOW', 4, '低于阈值')
}

# 响应模式
RESPONSE_MODES = {
    '1': ('NONE', 0, '无响应'),
    '2': ('DURATION', 1, '定时脉冲'),
    '3': ('MAPPED', 2, '直接映射'),
    '4': ('LATCHED', 3, '锁存模式')
}

def clear_screen():
    """清屏（可选）"""
    pass  # 简化版本不清屏

def print_header():
    """打印标题"""
    print("=" * 60)
    print("  PCA9635-ADC 命令构建向导")
    print("=" * 60)
    print()

def print_menu():
    """打印主菜单"""
    print("\n请选择要生成的命令:")
    print("  1. SET_CH   - 配置监测通道")
    print("  2. GET_CH   - 查询单个通道")
    print("  3. GET_ALL  - 查询所有通道")
    print("  4. EN_CH    - 启用通道")
    print("  5. DIS_CH   - 禁用通道")
    print("  6. CLR_CH   - 清除通道")
    print("  7. CLR_ALL  - 清除所有通道")
    print("  8. SAVE_CFG - 保存配置到Flash")
    print("  9. LOAD_CFG - 从Flash加载配置")
    print("  10. EN_UART_DATA  - 启用UART数据输出")
    print("  11. DIS_UART_DATA - 禁用UART数据输出")
    print("  12. EN_VERBOSE    - 启用详细日志(Verbose)")
    print("  13. DIS_VERBOSE   - 禁用详细日志(Verbose)")
    print("  14. SET_MOTOR     - 直接控制电机(无ADC触发)")
    print("  0. 退出")
    print()

def get_input(prompt, validator=None, default=None):
    """获取用户输入并验证"""
    while True:
        if default is not None:
            user_input = input(f"{prompt} [默认: {default}]: ").strip()
            if not user_input:
                return default
        else:
            user_input = input(f"{prompt}: ").strip()
        
        if validator:
            valid, result = validator(user_input)
            if valid:
                return result
            else:
                print(f"  ✗ 输入无效: {result}")
        else:
            return user_input

def validate_int_range(min_val, max_val):
    """创建整数范围验证器"""
    def validator(value):
        try:
            num = int(value)
            if min_val <= num <= max_val:
                return True, num
            else:
                return False, f"必须在 {min_val} 到 {max_val} 之间"
        except ValueError:
            return False, "必须输入整数"
    return validator

def build_set_ch_command():
    """构建SET_CH命令"""
    print("\n" + "─" * 60)
    print("配置监测通道 (SET_CH) - 电机控制模式")
    print("─" * 60)
    
    # 电机ID
    print("\n[1/7] 电机ID")
    print("  选择要配置的电机 (0-7)")
    print("  每个电机使用2个PCA9635通道: EN和PWM")
    motor_id = get_input("  电机ID", validate_int_range(0, 7))
    
    # ADC通道
    print("\n[2/7] ADC通道")
    print("  选择要监测的ADC通道 (0-15)")
    adc_ch = get_input("  ADC通道", validate_int_range(0, 15))
    
    # 监测类型
    print("\n[3/7] 监测类型")
    for key, (name, num, desc) in MONITOR_TYPES.items():
        print(f"  {key}. {name:8s} - {desc}")
    mon_type_choice = get_input("  选择类型 (1-5)", validate_int_range(1, 5))
    mon_type_name, mon_type_num, _ = MONITOR_TYPES[str(mon_type_choice)]
    
    # 阈值
    print("\n[4/7] 阈值")
    print("  设置触发阈值 (0-4095, 12位ADC)")
    threshold = get_input("  阈值", validate_int_range(0, 4095))
    
    # PWM强度
    print("\n[5/7] PWM强度")
    print("  设置PWM占空比 (0-255, 0=关闭, 255=全速)")
    intensity = get_input("  强度", validate_int_range(0, 255), default=255)
    
    # 持续时间
    print("\n[6/7] 持续时间")
    print("  设置持续时间(毫秒), 0表示无限")
    duration = get_input("  持续时间(ms)", validate_int_range(0, 999999), default=0)
    
    # 响应模式
    print("\n[7/7] 响应模式")
    for key, (name, num, desc) in RESPONSE_MODES.items():
        print(f"  {key}. {name:8s} - {desc}")
    mode_choice = get_input("  选择模式 (1-4)", validate_int_range(1, 4))
    mode_name, mode_num, _ = RESPONSE_MODES[str(mode_choice)]
    
    # 生成命令
    command = f"SET_CH {motor_id} {adc_ch} {mon_type_num} {threshold} {intensity} {duration} {mode_num}"
    
    # 显示摘要
    print("\n" + "─" * 60)
    print("配置摘要:")
    print("─" * 60)
    print(f"  电机ID:       {motor_id}")
    print(f"  ADC通道:      {adc_ch}")
    print(f"  监测类型:     {mon_type_name} ({mon_type_num})")
    print(f"  阈值:         {threshold}")
    print(f"  PWM强度:      {intensity}")
    print(f"  持续时间:     {duration} ms")
    print(f"  响应模式:     {mode_name} ({mode_num})")
    print(f"\n  PCA9635连接:")
    print(f"  - EN通道:  LED{motor_id * 2}")
    print(f"  - PWM通道: LED{motor_id * 2 + 1}")
    
    return command

def build_get_ch_command():
    """构建GET_CH命令"""
    print("\n" + "─" * 60)
    print("查询单个通道 (GET_CH)")
    print("─" * 60)
    
    ch = get_input("\n电机ID (0-7)", validate_int_range(0, 7))
    command = f"GET_CH {ch}"
    
    print("\n配置摘要:")
    print(f"  查询电机: {ch}")
    
    return command

def build_en_ch_command():
    """构建EN_CH命令"""
    print("\n" + "─" * 60)
    print("启用通道 (EN_CH)")
    print("─" * 60)
    
    ch = get_input("\n电机ID (0-7)", validate_int_range(0, 7))
    command = f"EN_CH {ch}"
    
    print("\n配置摘要:")
    print(f"  启用电机: {ch}")
    
    return command

def build_dis_ch_command():
    """构建DIS_CH命令"""
    print("\n" + "─" * 60)
    print("禁用通道 (DIS_CH)")
    print("─" * 60)
    
    ch = get_input("\n电机ID (0-7)", validate_int_range(0, 7))
    command = f"DIS_CH {ch}"
    
    print("\n配置摘要:")
    print(f"  禁用电机: {ch}")
    
    return command

def build_clr_ch_command():
    """构建CLR_CH命令"""
    print("\n" + "─" * 60)
    print("清除通道 (CLR_CH)")
    print("─" * 60)
    
    ch = get_input("\n电机ID (0-7)", validate_int_range(0, 7))
    command = f"CLR_CH {ch}"
    
    print("\n配置摘要:")
    print(f"  清除电机: {ch}")
    
    return command

def build_set_motor_command():
    """构建SET_MOTOR命令"""
    print("\n" + "─" * 60)
    print("直接电机控制 (SET_MOTOR)")
    print("─" * 60)
    print("此命令直接控制电机，不依赖ADC触发")
    
    # 电机ID
    print("\n[1/2] 电机ID")
    print("  选择要控制的电机 (0-7)")
    motor_id = get_input("  电机ID", validate_int_range(0, 7))
    
    # PWM强度
    print("\n[2/2] PWM强度")
    print("  设置PWM占空比 (0-255)")
    print("  0 = 关闭, 128 = 半速, 255 = 全速")
    intensity = get_input("  强度", validate_int_range(0, 255))
    
    command = f"SET_MOTOR {motor_id} {intensity}"
    
    # 显示摘要
    print("\n" + "─" * 60)
    print("配置摘要:")
    print("─" * 60)
    print(f"  电机ID:       {motor_id}")
    print(f"  PWM强度:      {intensity}")
    print(f"  状态:         {'关闭' if intensity == 0 else '开启'}")
    print(f"\n  PCA9635连接:")
    print(f"  - EN通道:  LED{motor_id * 2}")
    print(f"  - PWM通道: LED{motor_id * 2 + 1}")
    
    return command


def main():
    """主函数"""
    print_header()
    
    # 保存所有生成的命令
    commands = []
    
    while True:
        print_menu()
        choice = input("请选择 (0-9): ").strip()
        
        command = None
        
        if choice == '1':
            command = build_set_ch_command()
        elif choice == '2':
            command = build_get_ch_command()
        elif choice == '3':
            command = "GET_ALL"
            print("\n配置摘要:")
            print("  查询所有已配置通道")
        elif choice == '4':
            command = build_en_ch_command()
        elif choice == '5':
            command = build_dis_ch_command()
        elif choice == '6':
            command = build_clr_ch_command()
        elif choice == '7':
            command = "CLR_ALL"
            print("\n配置摘要:")
            print("  清除所有通道配置")
        elif choice == '8':
            command = "SAVE_CFG"
            print("\n配置摘要:")
            print("  保存当前配置到Flash存储器")
        elif choice == '9':
            command = "LOAD_CFG"
            print("\n配置摘要:")
            print("  从Flash存储器加载配置")
        elif choice == '10':
            command = "EN_UART_DATA"
            print("\n配置摘要:")
            print("  启用UART数据输出（ADC数据将通过UART和CDC同时发送）")
        elif choice == '11':
            command = "DIS_UART_DATA"
            print("\n配置摘要:")
            print("  禁用UART数据输出（ADC数据仅通过CDC发送）")
        elif choice == '12':
            command = "EN_VERBOSE"
            print("\n配置摘要:")
            print("  启用详细日志：包含配置确认和触发/动作实时日志")
        elif choice == '13':
            command = "DIS_VERBOSE"
            print("\n配置摘要:")
            print("  禁用详细日志")
        elif choice == '14':
            command = build_set_motor_command()
        elif choice == '0':
            break
        else:
            print("✗ 无效选择，请重新输入")
            continue
        
        if command:
            # 显示生成的命令
            print("\n" + "=" * 60)
            print("生成的UART命令:")
            print("=" * 60)
            print(f"\n  {command}\n")
            print("=" * 60)
            
            # 保存命令
            commands.append(command)
            
            # 询问是否继续
            cont = input("\n是否继续生成其他命令? (y/n) [y]: ").strip().lower()
            if cont == 'n':
                break
    
    # 最终总结
    if commands:
        print("\n\n" + "=" * 60)
        print("所有生成的命令:")
        print("=" * 60)
        for i, cmd in enumerate(commands, 1):
            print(f"{i}. {cmd}")
        print("=" * 60)
        
        # 保存到文件选项
        save = input("\n是否保存到文件? (y/n) [n]: ").strip().lower()
        if save == 'y':
            filename = input("文件名 [commands.txt]: ").strip() or "commands.txt"
            try:
                with open(filename, 'w', encoding='utf-8') as f:
                    for cmd in commands:
                        f.write(cmd + '\n')
                print(f"✓ 命令已保存到 {filename}")
            except Exception as e:
                print(f"✗ 保存失败: {e}")
    
    print("\n再见！")

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n\n用户中断，再见！")
        sys.exit(0)
