/**
 ******************************************************************************
 * @file    pca_adc_integration.c
 * @brief   Integration layer implementation
 ******************************************************************************
 */

#include "pca_adc_integration.h"
#include "uart_protocol.h"
#include <string.h>
#include <stdio.h>

/* Forward declaration for callback */
static void PCA_ADC_EventCallback(uint8_t channel, uint16_t value, void *user_data);

/* Helper function to control motor (EN + PWM) */
static void SetMotorPWM(PCA9635_HandleTypeDef *hpca, uint8_t motor_id, uint8_t pwm_value);

/**
 * @brief Initialize PCA-ADC integration
 * @param hpca_adc: Integration handle
 * @param hpca: PCA9635 handle
 * @param hmon: ADC monitor handle
 */
void PCA_ADC_Init(PCA_ADC_Handle_t *hpca_adc, PCA9635_HandleTypeDef *hpca, ADC_MonitorHandle_t *hmon)
{
    if (hpca_adc == NULL || hpca == NULL || hmon == NULL) {
        return;
    }

    memset(hpca_adc, 0, sizeof(PCA_ADC_Handle_t));
    hpca_adc->hpca = hpca;
    hpca_adc->hmon = hmon;
}

/**
 * @brief Set UART protocol handler for verbose logging
 * @param hpca_adc: Integration handle
 * @param huart_prot: UART protocol handle
 */
void PCA_ADC_SetVerboseHandler(PCA_ADC_Handle_t *hpca_adc, struct UART_Protocol_Handle_t *huart_prot)
{
    if (hpca_adc == NULL) {
        return;
    }
    hpca_adc->huart_prot = huart_prot;
}

/**
 * @brief Configure a PCA-ADC channel (Motor control mode)
 * @param hpca_adc: Integration handle
 * @param motor_id: Motor ID (0-7)
 * @param adc_ch: ADC channel to monitor (0-7)
 * @param monitor_type: ADC monitor type
 * @param threshold: ADC threshold value
 * @param intensity: PWM intensity (0-255)
 * @param duration_ms: Duration in milliseconds (0 = infinite)
 * @param response_mode: Response mode
 * @retval 0 on success, 1 on error
 */
uint8_t PCA_ADC_ConfigChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t motor_id,
                               uint8_t adc_ch, ADC_MonitorType_t monitor_type, uint16_t threshold,
                               uint8_t intensity, uint32_t duration_ms,
                               PCA_ResponseMode_t response_mode)
{
    if (hpca_adc == NULL || motor_id >= PCA_ADC_MAX_CHANNELS) {
        return 1;
    }

    PCA_ADC_ChannelConfig_t *cfg = &hpca_adc->channels[motor_id];

    /* Configure ADC monitor */
    cfg->adc_channel = adc_ch;
    cfg->threshold = threshold;
    cfg->monitor_type = monitor_type;

    /* Configure Motor Control */
    cfg->motor_id = motor_id;  // Store motor ID
    cfg->intensity = intensity;
    cfg->duration_ms = duration_ms;
    cfg->response_mode = response_mode;

    /* State */
    cfg->enabled = true;
    cfg->active = false;
    cfg->start_time = 0;

    /* Register with ADC monitor system */
    ADC_Monitor_ConfigChannel(hpca_adc->hmon, motor_id, adc_ch, monitor_type, 
                              threshold, PCA_ADC_EventCallback, hpca_adc);

    return 0;
}

/**
 * @brief Enable a PCA-ADC channel
 * @param hpca_adc: Integration handle
 * @param channel: Channel index (0-15)
 * @retval 0 on success, 1 on error
 */
uint8_t PCA_ADC_EnableChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t channel)
{
    if (hpca_adc == NULL || channel >= PCA_ADC_MAX_CHANNELS) {
        return 1;
    }

    hpca_adc->channels[channel].enabled = true;
    ADC_Monitor_EnableChannel(hpca_adc->hmon, channel);
    return 0;
}

/**
 * @brief Disable a PCA-ADC channel
 * @param hpca_adc: Integration handle
 * @param channel: Channel index (0-15)
 * @retval 0 on success, 1 on error
 */
uint8_t PCA_ADC_DisableChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t channel)
{
    if (hpca_adc == NULL || channel >= PCA_ADC_MAX_CHANNELS) {
        return 1;
    }

    hpca_adc->channels[channel].enabled = false;
    hpca_adc->channels[channel].active = false;
    
    /* Turn off motor */
    SetMotorPWM(hpca_adc->hpca, channel, 0);
    
    ADC_Monitor_DisableChannel(hpca_adc->hmon, channel);
    return 0;
}

/**
 * @brief Clear a PCA-ADC channel configuration
 * @param hpca_adc: Integration handle
 * @param channel: Channel index (0-15)
 * @retval 0 on success, 1 on error
 */
uint8_t PCA_ADC_ClearChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t channel)
{
    if (hpca_adc == NULL || channel >= PCA_ADC_MAX_CHANNELS) {
        return 1;
    }

    /* Turn off motor */
    SetMotorPWM(hpca_adc->hpca, channel, 0);
    
    /* Clear configuration */
    memset(&hpca_adc->channels[channel], 0, sizeof(PCA_ADC_ChannelConfig_t));
    
    ADC_Monitor_ClearChannel(hpca_adc->hmon, channel);
    return 0;
}

/**
 * @brief Clear all PCA-ADC channel configurations
 * @param hpca_adc: Integration handle
 */
void PCA_ADC_ClearAll(PCA_ADC_Handle_t *hpca_adc)
{
    if (hpca_adc == NULL) {
        return;
    }

    /* Turn off all motors */
    for (uint8_t i = 0; i < PCA_ADC_MAX_CHANNELS; i++) {
        SetMotorPWM(hpca_adc->hpca, i, 0);
    }
    
    /* Clear all configurations */
    for (uint8_t i = 0; i < PCA_ADC_MAX_CHANNELS; i++) {
        memset(&hpca_adc->channels[i], 0, sizeof(PCA_ADC_ChannelConfig_t));
    }
    
    ADC_Monitor_ClearAll(hpca_adc->hmon);
}

/**
 * @brief Check if a channel is configured
 * @param hpca_adc: Integration handle
 * @param channel: Channel index (0-15)
 * @retval true if configured, false otherwise
 */
bool PCA_ADC_IsChannelConfigured(PCA_ADC_Handle_t *hpca_adc, uint8_t channel)
{
    if (hpca_adc == NULL || channel >= PCA_ADC_MAX_CHANNELS) {
        return false;
    }

    return hpca_adc->channels[channel].enabled;
}

/**
 * @brief Get channel configuration
 * @param hpca_adc: Integration handle
 * @param channel: Channel index (0-15)
 * @retval Pointer to configuration, or NULL on error
 */
PCA_ADC_ChannelConfig_t* PCA_ADC_GetConfig(PCA_ADC_Handle_t *hpca_adc, uint8_t channel)
{
    if (hpca_adc == NULL || channel >= PCA_ADC_MAX_CHANNELS) {
        return NULL;
    }

    return &hpca_adc->channels[channel];
}

/**
 * @brief Process PCA-ADC integration (handle duration-based outputs)
 * @param hpca_adc: Integration handle
 * @param adc_values: Array of ADC values
 * @param count: Number of ADC values
 */
void PCA_ADC_Process(PCA_ADC_Handle_t *hpca_adc, uint16_t *adc_values, uint8_t count)
{
    if (hpca_adc == NULL) {
        return;
    }

    /* First, let the ADC monitor process events */
    ADC_Monitor_Process(hpca_adc->hmon, adc_values, count);

    /* Then handle duration-based outputs */
    uint32_t current_time = HAL_GetTick();
    
    for (uint8_t i = 0; i < PCA_ADC_MAX_CHANNELS; i++) {
        PCA_ADC_ChannelConfig_t *cfg = &hpca_adc->channels[i];
        
        if (!cfg->enabled) {
            continue;
        }

        /* Handle duration-based outputs */
        if (cfg->response_mode == PCA_RESPONSE_DURATION && cfg->active) {
            if (cfg->duration_ms > 0) {
                if ((current_time - cfg->start_time) >= cfg->duration_ms) {
                    /* Duration expired, turn off motor */
                    SetMotorPWM(hpca_adc->hpca, i, 0);
                    cfg->active = false;
                    
                    /* Verbose logging */
                    if (hpca_adc->huart_prot != NULL && UART_Protocol_IsVerboseEnabled(hpca_adc->huart_prot)) {
                        char verbose_buf[128];
                        snprintf(verbose_buf, sizeof(verbose_buf),
                                 "[TRIGGER] Motor %d: DURATION EXPIRED OFF\r\n", i);
                        UART_Protocol_SendResponse(hpca_adc->huart_prot, verbose_buf);
                    }
                }
            }
        }
        
        /* Handle mapped mode */
        if (cfg->response_mode == PCA_RESPONSE_MAPPED) {
            ADC_MonitorConfig_t *mon_cfg = ADC_Monitor_GetConfig(hpca_adc->hmon, i);
            if (mon_cfg != NULL) {
                bool is_triggered = mon_cfg->triggered;
                
                /* Detection of state change for logging and efficiency */
                if (is_triggered && !cfg->active) {
                    /* State transition: OFF -> ON */
                    SetMotorPWM(hpca_adc->hpca, i, cfg->intensity);
                    cfg->active = true;
                    
                    /* Verbose logging */
                    if (hpca_adc->huart_prot != NULL && UART_Protocol_IsVerboseEnabled(hpca_adc->huart_prot)) {
                        char verbose_buf[128];
                        snprintf(verbose_buf, sizeof(verbose_buf),
                                 "[TRIGGER] Motor %d: MAPPED ON (Intensity %d)\r\n", i, cfg->intensity);
                        UART_Protocol_SendResponse(hpca_adc->huart_prot, verbose_buf);
                    }
                } 
                else if (!is_triggered && cfg->active) {
                    /* State transition: ON -> OFF */
                    SetMotorPWM(hpca_adc->hpca, i, 0);
                    cfg->active = false;
                    
                    /* Verbose logging */
                    if (hpca_adc->huart_prot != NULL && UART_Protocol_IsVerboseEnabled(hpca_adc->huart_prot)) {
                        char verbose_buf[128];
                        snprintf(verbose_buf, sizeof(verbose_buf),
                                 "[TRIGGER] Motor %d: MAPPED OFF\r\n", i);
                        UART_Protocol_SendResponse(hpca_adc->huart_prot, verbose_buf);
                    }
                }
            }
        }
    }
}

/**
 * @brief Event callback from ADC monitor
 * @param channel: Channel that triggered
 * @param value: ADC value
 * @param user_data: User data (PCA_ADC_Handle_t pointer)
 */
static void PCA_ADC_EventCallback(uint8_t channel, uint16_t value, void *user_data)
{
    PCA_ADC_Handle_t *hpca_adc = (PCA_ADC_Handle_t *)user_data;
    
    if (hpca_adc == NULL || channel >= PCA_ADC_MAX_CHANNELS) {
        return;
    }

    PCA_ADC_ChannelConfig_t *cfg = &hpca_adc->channels[channel];
    
    if (!cfg->enabled) {
        return;
    }

    /* Handle different response modes */
    switch (cfg->response_mode) {
        case PCA_RESPONSE_DURATION:
            /* Turn on motor */
            SetMotorPWM(hpca_adc->hpca, channel, cfg->intensity);
            cfg->active = true;
            cfg->start_time = HAL_GetTick();
            
            /* Verbose logging */
            if (hpca_adc->huart_prot != NULL && UART_Protocol_IsVerboseEnabled(hpca_adc->huart_prot)) {
                char verbose_buf[128];
                snprintf(verbose_buf, sizeof(verbose_buf),
                         "[TRIGGER] Motor %d: ADC=%d VALUE=%u PWM=%u DUR=%lums\r\n",
                         channel, cfg->adc_channel, value, cfg->intensity, cfg->duration_ms);
                UART_Protocol_SendResponse(hpca_adc->huart_prot, verbose_buf);
            }
            break;

        case PCA_RESPONSE_MAPPED:
            /* Handled in PCA_ADC_Process */
            break;

        case PCA_RESPONSE_LATCHED:
            /* Turn on motor and stay on */
            SetMotorPWM(hpca_adc->hpca, channel, cfg->intensity);
            cfg->active = true;
            
            /* Verbose logging */
            if (hpca_adc->huart_prot != NULL && UART_Protocol_IsVerboseEnabled(hpca_adc->huart_prot)) {
                char verbose_buf[128];
                snprintf(verbose_buf, sizeof(verbose_buf),
                         "[TRIGGER] Motor %d: ADC=%d VALUE=%u PWM=%u LATCHED\r\n",
                         channel, cfg->adc_channel, value, cfg->intensity);
                UART_Protocol_SendResponse(hpca_adc->huart_prot, verbose_buf);
            }
            break;

        case PCA_RESPONSE_NONE:
        default:
            /* No action */
            break;
    }
}

/**
 * @brief Helper function to set motor PWM (controls both EN and PWM channels)
 * @param hpca: PCA9635 handle
 * @param motor_id: Motor ID (0-7)
 * @param pwm_value: PWM value (0-255), 0 = motor off, >0 = motor on with PWM
 * @note  Motor mapping:
 *        EN channel = motor_id * 2 (0, 2, 4, 6, 8, 10, 12, 14)
 *        PWM channel = motor_id * 2 + 1 (1, 3, 5, 7, 9, 11, 13, 15)
 *        EN = HIGH (255) when motor is on, LOW (0) when motor is off
 */
static void SetMotorPWM(PCA9635_HandleTypeDef *hpca, uint8_t motor_id, uint8_t pwm_value)
{
    if (motor_id >= 8) {
        return;  // Invalid motor ID
    }

    uint8_t en_channel = motor_id * 2;      // EN channel (0, 2, 4, ...)
    uint8_t pwm_channel = motor_id * 2 + 1; // PWM channel (1, 3, 5, ...)

    if (pwm_value > 0) {
        /* Motor ON: Set EN to HIGH (255) and PWM to desired value */
        PCA9635_SetPWM(hpca, en_channel, 255);    // EN = HIGH (enable motor)
        PCA9635_SetPWM(hpca, pwm_channel, pwm_value); // PWM = intensity
    } else {
        /* Motor OFF: Set EN to LOW (0) and PWM to 0 */
        PCA9635_SetPWM(hpca, en_channel, 0);      // EN = LOW (disable motor)
        PCA9635_SetPWM(hpca, pwm_channel, 0);     // PWM = 0
    }
}
