/**
 ******************************************************************************
 * @file    adc_monitor.c
 * @brief   ADC channel monitoring system implementation
 ******************************************************************************
 */

#include "adc_monitor.h"
#include <string.h>

/**
 * @brief Initialize ADC monitor system
 * @param hmon: ADC monitor handle
 */
void ADC_Monitor_Init(ADC_MonitorHandle_t *hmon)
{
    if (hmon == NULL) {
        return;
    }

    memset(hmon, 0, sizeof(ADC_MonitorHandle_t));
    hmon->channel_count = ADC_MONITOR_MAX_CHANNELS;
}

/**
 * @brief Configure an ADC monitor channel
 * @param hmon: ADC monitor handle
 * @param monitor_ch: Monitor channel index (0-15)
 * @param adc_ch: ADC channel to monitor (0-15)
 * @param type: Monitor type
 * @param threshold: Threshold value
 * @param callback: Callback function (can be NULL)
 * @param user_data: User data pointer (can be NULL)
 * @retval 0 on success, 1 on error
 */
uint8_t ADC_Monitor_ConfigChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch,
                                   uint8_t adc_ch, ADC_MonitorType_t type,
                                   uint16_t threshold, ADC_MonitorCallback_t callback,
                                   void *user_data)
{
    if (hmon == NULL || monitor_ch >= ADC_MONITOR_MAX_CHANNELS) {
        return 1;
    }

    ADC_MonitorConfig_t *cfg = &hmon->channels[monitor_ch];
    
    cfg->adc_channel = adc_ch;
    cfg->threshold = threshold;
    cfg->type = type;
    cfg->callback = callback;
    cfg->user_data = user_data;
    cfg->enabled = true;
    cfg->last_value = 0;
    cfg->triggered = false;

    return 0;
}

/**
 * @brief Enable a monitor channel
 * @param hmon: ADC monitor handle
 * @param monitor_ch: Monitor channel index (0-15)
 * @retval 0 on success, 1 on error
 */
uint8_t ADC_Monitor_EnableChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch)
{
    if (hmon == NULL || monitor_ch >= ADC_MONITOR_MAX_CHANNELS) {
        return 1;
    }

    hmon->channels[monitor_ch].enabled = true;
    return 0;
}

/**
 * @brief Disable a monitor channel
 * @param hmon: ADC monitor handle
 * @param monitor_ch: Monitor channel index (0-15)
 * @retval 0 on success, 1 on error
 */
uint8_t ADC_Monitor_DisableChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch)
{
    if (hmon == NULL || monitor_ch >= ADC_MONITOR_MAX_CHANNELS) {
        return 1;
    }

    hmon->channels[monitor_ch].enabled = false;
    return 0;
}

/**
 * @brief Clear a monitor channel configuration
 * @param hmon: ADC monitor handle
 * @param monitor_ch: Monitor channel index (0-15)
 * @retval 0 on success, 1 on error
 */
uint8_t ADC_Monitor_ClearChannel(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch)
{
    if (hmon == NULL || monitor_ch >= ADC_MONITOR_MAX_CHANNELS) {
        return 1;
    }

    memset(&hmon->channels[monitor_ch], 0, sizeof(ADC_MonitorConfig_t));
    return 0;
}

/**
 * @brief Clear all monitor channel configurations
 * @param hmon: ADC monitor handle
 */
void ADC_Monitor_ClearAll(ADC_MonitorHandle_t *hmon)
{
    if (hmon == NULL) {
        return;
    }

    for (uint8_t i = 0; i < ADC_MONITOR_MAX_CHANNELS; i++) {
        memset(&hmon->channels[i], 0, sizeof(ADC_MonitorConfig_t));
    }
}

/**
 * @brief Check if a monitor channel is configured
 * @param hmon: ADC monitor handle
 * @param monitor_ch: Monitor channel index (0-15)
 * @retval true if configured, false otherwise
 */
bool ADC_Monitor_IsChannelConfigured(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch)
{
    if (hmon == NULL || monitor_ch >= ADC_MONITOR_MAX_CHANNELS) {
        return false;
    }

    /* A channel is considered configured if it has a callback or is enabled */
    return (hmon->channels[monitor_ch].callback != NULL || 
            hmon->channels[monitor_ch].enabled);
}

/**
 * @brief Check if a monitor channel is enabled
 * @param hmon: ADC monitor handle
 * @param monitor_ch: Monitor channel index (0-15)
 * @retval true if enabled, false otherwise
 */
bool ADC_Monitor_IsChannelEnabled(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch)
{
    if (hmon == NULL || monitor_ch >= ADC_MONITOR_MAX_CHANNELS) {
        return false;
    }

    return hmon->channels[monitor_ch].enabled;
}

/**
 * @brief Get monitor channel configuration
 * @param hmon: ADC monitor handle
 * @param monitor_ch: Monitor channel index (0-15)
 * @retval Pointer to configuration, or NULL on error
 */
ADC_MonitorConfig_t* ADC_Monitor_GetConfig(ADC_MonitorHandle_t *hmon, uint8_t monitor_ch)
{
    if (hmon == NULL || monitor_ch >= ADC_MONITOR_MAX_CHANNELS) {
        return NULL;
    }

    return &hmon->channels[monitor_ch];
}

/**
 * @brief Process ADC values and trigger events
 * @param hmon: ADC monitor handle
 * @param adc_values: Array of ADC values (must have at least 16 elements)
 * @param count: Number of ADC values (should be 16)
 */
void ADC_Monitor_Process(ADC_MonitorHandle_t *hmon, uint16_t *adc_values, uint8_t count)
{
    if (hmon == NULL || adc_values == NULL) {
        return;
    }

    for (uint8_t i = 0; i < ADC_MONITOR_MAX_CHANNELS; i++) {
        ADC_MonitorConfig_t *cfg = &hmon->channels[i];

        /* Skip if not enabled */
        if (!cfg->enabled) {
            continue;
        }

        /* Get ADC value for this channel */
        if (cfg->adc_channel >= count) {
            continue;  // ADC channel out of range
        }
        
        uint16_t value = adc_values[cfg->adc_channel];
        bool trigger_event = false;

        /* Check for event based on monitor type */
        switch (cfg->type) {
            case ADC_MONITOR_RISING:
                /* Trigger on rising edge */
                if (cfg->last_value < cfg->threshold && value >= cfg->threshold) {
                    trigger_event = true;
                    cfg->triggered = true;
                } else if (value < cfg->threshold) {
                    cfg->triggered = false;
                }
                break;

            case ADC_MONITOR_FALLING:
                /* Trigger on falling edge */
                if (cfg->last_value >= cfg->threshold && value < cfg->threshold) {
                    trigger_event = true;
                    cfg->triggered = true;
                } else if (value >= cfg->threshold) {
                    cfg->triggered = false;
                }
                break;

            case ADC_MONITOR_BOTH:
                /* Trigger on both edges */
                if ((cfg->last_value < cfg->threshold && value >= cfg->threshold) ||
                    (cfg->last_value >= cfg->threshold && value < cfg->threshold)) {
                    trigger_event = true;
                    cfg->triggered = !cfg->triggered;
                }
                break;

            case ADC_MONITOR_ABOVE:
                /* Continuously active when above threshold */
                if (value >= cfg->threshold) {
                    trigger_event = !cfg->triggered;  // Only trigger on first time
                    cfg->triggered = true;
                } else {
                    cfg->triggered = false;
                }
                break;

            case ADC_MONITOR_BELOW:
                /* Continuously active when below threshold */
                if (value < cfg->threshold) {
                    trigger_event = !cfg->triggered;  // Only trigger on first time
                    cfg->triggered = true;
                } else {
                    cfg->triggered = false;
                }
                break;

            default:
                break;
        }

        /* Update last value */
        cfg->last_value = value;

        /* Call callback if event triggered */
        if (trigger_event && cfg->callback != NULL) {
            cfg->callback(i, value, cfg->user_data);
        }
    }
}
