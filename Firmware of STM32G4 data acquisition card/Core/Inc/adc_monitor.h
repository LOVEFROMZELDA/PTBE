/**
 ******************************************************************************
 * @file    adc_monitor.h
 * @brief   ADC channel monitoring system with event detection
 ******************************************************************************
 */

#ifndef __ADC_MONITOR_H__
#define __ADC_MONITOR_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include <stdint.h>
#include <stdbool.h>

/* Maximum number of monitored channels */
#define ADC_MONITOR_MAX_CHANNELS    16

/**
 * @brief ADC monitor event types
 */
typedef enum {
    ADC_MONITOR_RISING,     // Trigger when ADC crosses threshold upward
    ADC_MONITOR_FALLING,    // Trigger when ADC crosses threshold downward
    ADC_MONITOR_BOTH,       // Trigger on both rising and falling edges
    ADC_MONITOR_ABOVE,      // Continuously active when ADC is above threshold
    ADC_MONITOR_BELOW       // Continuously active when ADC is below threshold
} ADC_MonitorType_t;

/**
 * @brief ADC monitor event callback
 * @param channel: ADC channel that triggered
 * @param value: Current ADC value
 * @param user_data: User-defined data pointer
 */
typedef void (*ADC_MonitorCallback_t)(uint8_t channel, uint16_t value, void *user_data);

/**
 * @brief ADC channel monitor configuration
 */
typedef struct {
    uint8_t adc_channel;            // ADC channel to monitor (0-15)
    uint16_t threshold;             // Threshold value
    ADC_MonitorType_t type;         // Monitor type
    bool enabled;                   // Enable/disable this monitor
    ADC_MonitorCallback_t callback; // Callback function (optional)
    void *user_data;                // User data for callback
    
    /* Internal state */
    uint16_t last_value;            // Last ADC value
    bool triggered;                 // Current trigger state (for edge detection)
} ADC_MonitorConfig_t;

/**
 * @brief ADC monitor system handle
 */
typedef struct {
    ADC_MonitorConfig_t channels[ADC_MONITOR_MAX_CHANNELS];
    uint8_t channel_count;
} ADC_MonitorHandle_t;

/* Initialization */
void ADC_Monitor_Init(ADC_MonitorHandle_t *hmon);

/* Configuration */
uint8_t ADC_Monitor_ConfigChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch, 
                                   uint8_t adc_ch, ADC_MonitorType_t type, 
                                   uint16_t threshold, ADC_MonitorCallback_t callback,
                                   void *user_data);
uint8_t ADC_Monitor_EnableChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch);
uint8_t ADC_Monitor_DisableChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch);
uint8_t ADC_Monitor_ClearChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch);
void ADC_Monitor_ClearAll(ADC_MonitorHandle_t *hmon);

/* Query */
bool ADC_Monitor_IsChannelConfigured(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch);
bool ADC_Monitor_IsChannelEnabled(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch);
ADC_MonitorConfig_t* ADC_Monitor_GetConfig(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch);

/* Processing */
void ADC_Monitor_Process(ADC_MonitorHandle_t *hmon, uint16_t *adc_values, uint8_t count);

#ifdef __cplusplus
}
#endif

#endif /* __ADC_MONITOR_H__ */
