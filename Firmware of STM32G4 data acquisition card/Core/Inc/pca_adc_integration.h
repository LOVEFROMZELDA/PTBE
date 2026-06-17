/**
 ******************************************************************************
 * @file    pca_adc_integration.h
 * @brief   Integration layer between ADC monitor and PCA9635
 * 
 * @note    Hardware Configuration:
 *          - 8 ADC channels (0-7)
 *          - 8 Motors (0-7), each motor uses 2 PCA9635 channels:
 *            Motor 0: LED0 (EN), LED1 (PWM)
 *            Motor 1: LED2 (EN), LED3 (PWM)
 *            ...
 *            Motor 7: LED14 (EN), LED15 (PWM)
 ******************************************************************************
 */

#ifndef __PCA_ADC_INTEGRATION_H__
#define __PCA_ADC_INTEGRATION_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include "pca9635_driver.h"
#include "adc_monitor.h"
#include <stdint.h>
#include <stdbool.h>

/* Forward declaration to break circular dependency */
struct UART_Protocol_Handle_t;

/* Maximum number of integrated channels (8 ADC channels -> 8 motors) */
#define PCA_ADC_MAX_CHANNELS    8

/**
 * @brief PCA9635 response mode
 */
typedef enum {
    PCA_RESPONSE_NONE,          // No response
    PCA_RESPONSE_DURATION,      // Pulse for a duration then turn off
    PCA_RESPONSE_MAPPED,        // Map directly: triggered = on, not triggered = off
    PCA_RESPONSE_LATCHED        // Turn on when triggered, stay on until cleared
} PCA_ResponseMode_t;

/**
 * @brief PCA9635-ADC channel configuration (Motor control mode)
 * @note  Each channel corresponds to one motor
 *        Motor ID = channel index (0-7)
 *        PCA9635 EN channel = motor_id * 2 (0, 2, 4, 6, 8, 10, 12, 14)
 *        PCA9635 PWM channel = motor_id * 2 + 1 (1, 3, 5, 7, 9, 11, 13, 15)
 */
typedef struct {
    /* ADC Monitor Configuration */
    uint8_t adc_channel;            // ADC channel to monitor (0-7)
    uint16_t threshold;             // Threshold value
    ADC_MonitorType_t monitor_type; // Monitor type
    
    /* Motor Control Configuration */
    uint8_t motor_id;               // Motor ID (0-7), equals to channel index
    uint8_t intensity;              // PWM intensity (0-255)
    uint32_t duration_ms;           // Duration in milliseconds (0 = infinite)
    PCA_ResponseMode_t response_mode; // Response mode
    
    /* State */
    bool enabled;                   // Channel enabled
    bool active;                    // Currently active
    uint32_t start_time;            // Start time for duration-based response
} PCA_ADC_ChannelConfig_t;

/**
 * @brief PCA-ADC integration handle
 */
typedef struct {
    PCA9635_HandleTypeDef *hpca;
    ADC_MonitorHandle_t *hmon;
    struct UART_Protocol_Handle_t *huart_prot;  // For verbose logging
    PCA_ADC_ChannelConfig_t channels[PCA_ADC_MAX_CHANNELS];
} PCA_ADC_Handle_t;

/* Initialization */
void PCA_ADC_Init(PCA_ADC_Handle_t *hpca_adc, PCA9635_HandleTypeDef *hpca, ADC_MonitorHandle_t *hmon);
void PCA_ADC_SetVerboseHandler(PCA_ADC_Handle_t *hpca_adc, struct UART_Protocol_Handle_t *huart_prot);

/* Configuration */
uint8_t PCA_ADC_ConfigChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t motor_id,
                               uint8_t adc_ch, ADC_MonitorType_t monitor_type, uint16_t threshold,
                               uint8_t intensity, uint32_t duration_ms,
                               PCA_ResponseMode_t response_mode);

uint8_t PCA_ADC_EnableChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t channel);
uint8_t PCA_ADC_DisableChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t channel);
uint8_t PCA_ADC_ClearChannel(PCA_ADC_Handle_t *hpca_adc, uint8_t channel);
void PCA_ADC_ClearAll(PCA_ADC_Handle_t *hpca_adc);

/* Query */
bool PCA_ADC_IsChannelConfigured(PCA_ADC_Handle_t *hpca_adc, uint8_t channel);
PCA_ADC_ChannelConfig_t* PCA_ADC_GetConfig(PCA_ADC_Handle_t *hpca_adc, uint8_t channel);

/* Processing - call this periodically and after ADC conversion */
void PCA_ADC_Process(PCA_ADC_Handle_t *hpca_adc, uint16_t *adc_values, uint8_t count);

#ifdef __cplusplus
}
#endif

#endif /* __PCA_ADC_INTEGRATION_H__ */
