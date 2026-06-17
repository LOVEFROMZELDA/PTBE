/**
 ******************************************************************************
 * @file    uart_protocol.c
 * @brief   UART protocol implementation
 * 
 * Command Format (text-based):
 * - SET_CH <ch> <adc_ch> <type> <thresh> <pca_ch> <intensity> <duration> <mode>
 * - GET_CH <ch>
 * - GET_ALL
 * - EN_CH <ch>
 * - DIS_CH <ch>
 * - CLR_CH <ch>
 * - CLR_ALL
 * - SAVE_CFG (保存配置到Flash)
 * - LOAD_CFG (从Flash加载配置)
 * - SET_MOTOR <motor_id> <intensity> (直接控制电机)
 * 
 * Where:
 * - ch: Channel index (0-15)
 * - adc_ch: ADC channel (0-15)
 * - type: Monitor type (0=RISING, 1=FALLING, 2=BOTH, 3=ABOVE, 4=BELOW)
 * - thresh: Threshold value (0-4095)
 * - pca_ch: PCA9635 channel (0-15)
 * - intensity: PWM intensity (0-255)
 * - duration: Duration in ms (0=infinite)
 * - mode: Response mode (0=NONE, 1=DURATION, 2=MAPPED, 3=LATCHED)
 * - motor_id: Motor channel (0-15)
 * 
 ******************************************************************************
 */

#include "uart_protocol.h"
#include "config_storage.h"
#include "usbd_cdc_if.h"
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* Private function prototypes */
static void UART_Protocol_ParseCommand(UART_Protocol_Handle_t *huart_prot);
static const char* MonitorTypeToString(ADC_MonitorType_t type);
static const char* ResponseModeToString(PCA_ResponseMode_t mode);

/**
 * @brief Initialize UART protocol
 * @param huart_prot: UART protocol handle
 * @param hpca_adc: PCA-ADC integration handle
 * @param huart: UART handle
 */
void UART_Protocol_Init(UART_Protocol_Handle_t *huart_prot, PCA_ADC_Handle_t *hpca_adc, UART_HandleTypeDef *huart)
{
    if (huart_prot == NULL) {
        return;
    }

    memset(huart_prot, 0, sizeof(UART_Protocol_Handle_t));
    huart_prot->hpca_adc = hpca_adc;
    huart_prot->huart = huart;
    huart_prot->command_source = CMD_SOURCE_UART;  // Default to UART
}

/**
 * @brief Set command source before processing
 * @param huart_prot: UART protocol handle
 * @param source: Command source (UART or CDC)
 */
void UART_Protocol_SetSource(UART_Protocol_Handle_t *huart_prot, CommandSource_t source)
{
    if (huart_prot == NULL) {
        return;
    }
    huart_prot->command_source = source;
}

/**
 * @brief Process a single received byte
 * @param huart_prot: UART protocol handle
 * @param byte: Received byte
 */
void UART_Protocol_ProcessByte(UART_Protocol_Handle_t *huart_prot, uint8_t byte)
{
    if (huart_prot == NULL) {
        return;
    }

    /* Handle line endings */
    if (byte == '\r' || byte == '\n') {
        if (huart_prot->cmd_index > 0) {
            /* Null-terminate and process */
            huart_prot->cmd_buffer[huart_prot->cmd_index] = '\0';
            UART_Protocol_ParseCommand(huart_prot);
            huart_prot->cmd_index = 0;
        }
        return;
    }

    /* Add to buffer */
    if (huart_prot->cmd_index < UART_CMD_BUFFER_SIZE - 1) {
        huart_prot->cmd_buffer[huart_prot->cmd_index++] = byte;
    }
}

/**
 * @brief Send OK response to the correct interface
 * @param huart_prot: UART protocol handle
 */
void UART_Protocol_SendOK(UART_Protocol_Handle_t *huart_prot)
{
    const char *msg = "OK\r\n";
    
    if (huart_prot->command_source == CMD_SOURCE_CDC) {
        CDC_Transmit_FS((uint8_t*)msg, strlen(msg));
    } else {
        HAL_UART_Transmit(huart_prot->huart, (uint8_t*)msg, strlen(msg), 100);
    }
}

/**
 * @brief Send error response to the correct interface
 * @param huart_prot: UART protocol handle
 * @param error_msg: Error message
 */
void UART_Protocol_SendError(UART_Protocol_Handle_t *huart_prot, const char *error_msg)
{
    snprintf(huart_prot->resp_buffer, UART_RESP_BUFFER_SIZE, "ERR %s\r\n", error_msg);
    
    if (huart_prot->command_source == CMD_SOURCE_CDC) {
        CDC_Transmit_FS((uint8_t*)huart_prot->resp_buffer, strlen(huart_prot->resp_buffer));
    } else {
        HAL_UART_Transmit(huart_prot->huart, (uint8_t*)huart_prot->resp_buffer, 
                          strlen(huart_prot->resp_buffer), 100);
    }
}

/**
 * @brief Send custom response to the correct interface
 * @param huart_prot: UART protocol handle
 * @param response: Response string
 */
void UART_Protocol_SendResponse(UART_Protocol_Handle_t *huart_prot, const char *response)
{
    if (huart_prot->command_source == CMD_SOURCE_CDC) {
        CDC_Transmit_FS((uint8_t*)response, strlen(response));
    } else {
        HAL_UART_Transmit(huart_prot->huart, (uint8_t*)response, strlen(response), 100);
    }
}

/**
 * @brief Parse and execute command
 * @param huart_prot: UART protocol handle
 */
static void UART_Protocol_ParseCommand(UART_Protocol_Handle_t *huart_prot)
{
    char *token;
    char *saveptr;
    
    /* Get command token */
    token = strtok_r(huart_prot->cmd_buffer, " ", &saveptr);
    if (token == NULL) {
        UART_Protocol_SendError(huart_prot, "INVALID_CMD");
        return;
    }

    /* SET_CH command */
    if (strcmp(token, "SET_CH") == 0) {
        int motor_id, adc_ch, type, thresh, intensity, duration, mode;
        
        if (sscanf(saveptr, "%d %d %d %d %d %d %d", 
                   &motor_id, &adc_ch, &type, &thresh, &intensity, &duration, &mode) == 7) {
            
            if (motor_id < 0 || motor_id >= PCA_ADC_MAX_CHANNELS) {
                UART_Protocol_SendError(huart_prot, "INVALID_MOTOR_ID");
                return;
            }
            
            uint8_t ret = PCA_ADC_ConfigChannel(huart_prot->hpca_adc, motor_id,
                                                 adc_ch, (ADC_MonitorType_t)type, thresh,
                                                 intensity, duration, 
                                                 (PCA_ResponseMode_t)mode);
            
            if (ret == 0) {
                // Print verbose information if enabled
                if (huart_prot->verbose_enabled) {
                    snprintf(huart_prot->resp_buffer, UART_RESP_BUFFER_SIZE,
                             "[VERBOSE] Motor %d configured: ADC_CH=%d TYPE=%s THRESH=%d INT=%d DUR=%d MODE=%s\r\n",
                             motor_id, adc_ch, MonitorTypeToString((ADC_MonitorType_t)type),
                             thresh, intensity, duration, ResponseModeToString((PCA_ResponseMode_t)mode));
                    UART_Protocol_SendResponse(huart_prot, huart_prot->resp_buffer);
                }
                UART_Protocol_SendOK(huart_prot);
            } else {
                UART_Protocol_SendError(huart_prot, "CONFIG_FAILED");
            }
        } else {
            UART_Protocol_SendError(huart_prot, "INVALID_PARAMS");
        }
    }
    
    /* GET_CH command */
    else if (strcmp(token, "GET_CH") == 0) {
        int ch;
        
        if (sscanf(saveptr, "%d", &ch) == 1) {
            if (ch < 0 || ch >= PCA_ADC_MAX_CHANNELS) {
                UART_Protocol_SendError(huart_prot, "INVALID_CH");
                return;
            }
            
            PCA_ADC_ChannelConfig_t *cfg = PCA_ADC_GetConfig(huart_prot->hpca_adc, ch);
            if (cfg != NULL && cfg->enabled) {
                snprintf(huart_prot->resp_buffer, UART_RESP_BUFFER_SIZE,
                         "CH_CFG %d ADC:%d TYPE:%s THRESH:%u MOTOR:%d INT:%u DUR:%lu MODE:%s EN:%d ACT:%d\r\n",
                         ch, cfg->adc_channel, MonitorTypeToString(cfg->monitor_type),
                         cfg->threshold, cfg->motor_id, cfg->intensity, cfg->duration_ms,
                         ResponseModeToString(cfg->response_mode), cfg->enabled, cfg->active);
                UART_Protocol_SendResponse(huart_prot, huart_prot->resp_buffer);
            } else {
                UART_Protocol_SendError(huart_prot, "CH_NOT_CFG");
            }
        } else {
            UART_Protocol_SendError(huart_prot, "INVALID_PARAMS");
        }
    }
    
    /* GET_ALL command */
    else if (strcmp(token, "GET_ALL") == 0) {
        for (uint8_t i = 0; i < PCA_ADC_MAX_CHANNELS; i++) {
            PCA_ADC_ChannelConfig_t *cfg = PCA_ADC_GetConfig(huart_prot->hpca_adc, i);
            if (cfg != NULL && cfg->enabled) {
                snprintf(huart_prot->resp_buffer, UART_RESP_BUFFER_SIZE,
                         "CH_CFG %d ADC:%d TYPE:%s THRESH:%u MOTOR:%d INT:%u DUR:%lu MODE:%s EN:%d ACT:%d\r\n",
                         i, cfg->adc_channel, MonitorTypeToString(cfg->monitor_type),
                         cfg->threshold, cfg->motor_id, cfg->intensity, cfg->duration_ms,
                         ResponseModeToString(cfg->response_mode), cfg->enabled, cfg->active);
                UART_Protocol_SendResponse(huart_prot, huart_prot->resp_buffer);
            }
        }
        UART_Protocol_SendOK(huart_prot);
    }
    
    /* EN_CH command */
    else if (strcmp(token, "EN_CH") == 0) {
        int ch;
        
        if (sscanf(saveptr, "%d", &ch) == 1) {
            if (ch < 0 || ch >= PCA_ADC_MAX_CHANNELS) {
                UART_Protocol_SendError(huart_prot, "INVALID_CH");
                return;
            }
            
            uint8_t ret = PCA_ADC_EnableChannel(huart_prot->hpca_adc, ch);
            if (ret == 0) {
                UART_Protocol_SendOK(huart_prot);
            } else {
                UART_Protocol_SendError(huart_prot, "ENABLE_FAILED");
            }
        } else {
            UART_Protocol_SendError(huart_prot, "INVALID_PARAMS");
        }
    }
    
    /* DIS_CH command */
    else if (strcmp(token, "DIS_CH") == 0) {
        int ch;
        
        if (sscanf(saveptr, "%d", &ch) == 1) {
            if (ch < 0 || ch >= PCA_ADC_MAX_CHANNELS) {
                UART_Protocol_SendError(huart_prot, "INVALID_CH");
                return;
            }
            
            uint8_t ret = PCA_ADC_DisableChannel(huart_prot->hpca_adc, ch);
            if (ret == 0) {
                UART_Protocol_SendOK(huart_prot);
            } else {
                UART_Protocol_SendError(huart_prot, "DISABLE_FAILED");
            }
        } else {
            UART_Protocol_SendError(huart_prot, "INVALID_PARAMS");
        }
    }
    
    /* CLR_CH command */
    else if (strcmp(token, "CLR_CH") == 0) {
        int ch;
        
        if (sscanf(saveptr, "%d", &ch) == 1) {
            if (ch < 0 || ch >= PCA_ADC_MAX_CHANNELS) {
                UART_Protocol_SendError(huart_prot, "INVALID_CH");
                return;
            }
            
            uint8_t ret = PCA_ADC_ClearChannel(huart_prot->hpca_adc, ch);
            if (ret == 0) {
                UART_Protocol_SendOK(huart_prot);
            } else {
                UART_Protocol_SendError(huart_prot, "CLEAR_FAILED");
            }
        } else {
            UART_Protocol_SendError(huart_prot, "INVALID_PARAMS");
        }
    }
    
    /* CLR_ALL command */
    else if (strcmp(token, "CLR_ALL") == 0) {
        PCA_ADC_ClearAll(huart_prot->hpca_adc);
        UART_Protocol_SendOK(huart_prot);
    }
    
    /* SAVE_CFG command - Save configuration to Flash */
    else if (strcmp(token, "SAVE_CFG") == 0) {
        if (Config_Storage_Save(huart_prot->hpca_adc)) {
            UART_Protocol_SendResponse(huart_prot, "CFG_SAVED Configuration saved to Flash\r\n");
            UART_Protocol_SendOK(huart_prot);
        } else {
            UART_Protocol_SendError(huart_prot, "SAVE_FAILED");
        }
    }
    
    /* LOAD_CFG command - Load configuration from Flash */
    else if (strcmp(token, "LOAD_CFG") == 0) {
        if (Config_Storage_Load(huart_prot->hpca_adc)) {
            UART_Protocol_SendResponse(huart_prot, "CFG_LOADED Configuration loaded from Flash\r\n");
            UART_Protocol_SendOK(huart_prot);
        } else {
            UART_Protocol_SendError(huart_prot, "LOAD_FAILED No valid configuration in Flash");
        }
    }
    
    /* EN_UART_DATA command - Enable UART ADC data output */
    else if (strcmp(token, "EN_UART_DATA") == 0) {
        huart_prot->uart_data_output_enabled = 1;
        UART_Protocol_SendResponse(huart_prot, "UART_DATA_EN UART ADC data output enabled\r\n");
        UART_Protocol_SendOK(huart_prot);
    }
    
    /* DIS_UART_DATA command - Disable UART ADC data output */
    else if (strcmp(token, "DIS_UART_DATA") == 0) {
        huart_prot->uart_data_output_enabled = 0;
        UART_Protocol_SendResponse(huart_prot, "UART_DATA_DIS UART ADC data output disabled\r\n");
        UART_Protocol_SendOK(huart_prot);
    }
    
    /* EN_VERBOSE command - Enable verbose logging */
    else if (strcmp(token, "EN_VERBOSE") == 0) {
        huart_prot->verbose_enabled = 1;
        UART_Protocol_SendResponse(huart_prot, "VERBOSE_EN Verbose logging enabled\r\n");
        UART_Protocol_SendOK(huart_prot);
    }
    
    /* DIS_VERBOSE command - Disable verbose logging */
    else if (strcmp(token, "DIS_VERBOSE") == 0) {
        huart_prot->verbose_enabled = 0;
        UART_Protocol_SendResponse(huart_prot, "VERBOSE_DIS Verbose logging disabled\r\n");
        UART_Protocol_SendOK(huart_prot);
    }
    
    /* SET_MOTOR command - Direct motor control */
    else if (strcmp(token, "SET_MOTOR") == 0) {
        int motor_id, intensity;
        
        if (sscanf(saveptr, "%d %d", &motor_id, &intensity) == 2) {
            if (motor_id < 0 || motor_id >= 8) {
                UART_Protocol_SendError(huart_prot, "INVALID_MOTOR_ID");
                return;
            }
            
            if (intensity < 0 || intensity > 255) {
                UART_Protocol_SendError(huart_prot, "INVALID_INTENSITY");
                return;
            }
            
            // Get PCA9635 handle from integration
            PCA9635_HandleTypeDef *hpca = huart_prot->hpca_adc->hpca;
            
            // Motor mapping: EN channel = motor_id * 2, PWM channel = motor_id * 2 + 1
            uint8_t en_channel = motor_id * 2;
            uint8_t pwm_channel = motor_id * 2 + 1;
            uint8_t ret;
            
            if (intensity > 0) {
                // Motor ON: Set EN to HIGH and PWM to desired value
                ret = PCA9635_SetLedDriverMode(hpca, en_channel, PCA9635_LED_PWM);
                ret |= PCA9635_SetLedDriverMode(hpca, pwm_channel, PCA9635_LED_PWM);
                ret |= PCA9635_SetPWM(hpca, en_channel, 255);      // EN = HIGH
                ret |= PCA9635_SetPWM(hpca, pwm_channel, (uint8_t)intensity); // PWM = intensity
            } else {
                // Motor OFF: Set EN to LOW and PWM to 0
                ret = PCA9635_SetPWM(hpca, en_channel, 0);         // EN = LOW
                ret |= PCA9635_SetPWM(hpca, pwm_channel, 0);       // PWM = 0
            }
            
            if (ret == PCA9635_OK) {
                if (huart_prot->verbose_enabled) {
                    snprintf(huart_prot->resp_buffer, UART_RESP_BUFFER_SIZE,
                             "[VERBOSE] Motor %d set to intensity %d (EN=LED%d, PWM=LED%d)\r\n",
                             motor_id, intensity, en_channel, pwm_channel);
                    UART_Protocol_SendResponse(huart_prot, huart_prot->resp_buffer);
                }
                UART_Protocol_SendOK(huart_prot);
            } else {
                UART_Protocol_SendError(huart_prot, "MOTOR_SET_FAILED");
            }
        } else {
            UART_Protocol_SendError(huart_prot, "INVALID_PARAMS");
        }
    }
    
    /* Unknown command */
    else {
        UART_Protocol_SendError(huart_prot, "UNKNOWN_CMD");
    }
}

/**
 * @brief Convert monitor type to string
 */
static const char* MonitorTypeToString(ADC_MonitorType_t type)
{
    switch (type) {
        case ADC_MONITOR_RISING:  return "RISING";
        case ADC_MONITOR_FALLING: return "FALLING";
        case ADC_MONITOR_BOTH:    return "BOTH";
        case ADC_MONITOR_ABOVE:   return "ABOVE";
        case ADC_MONITOR_BELOW:   return "BELOW";
        default:                  return "UNKNOWN";
    }
}

/**
 * @brief Convert response mode to string
 */
static const char* ResponseModeToString(PCA_ResponseMode_t mode)
{
    switch (mode) {
        case PCA_RESPONSE_NONE:     return "NONE";
        case PCA_RESPONSE_DURATION: return "DURATION";
        case PCA_RESPONSE_MAPPED:   return "MAPPED";
        case PCA_RESPONSE_LATCHED:  return "LATCHED";
        default:                    return "UNKNOWN";
    }
}

/**
 * @brief Check if UART data output is enabled
 * @param huart_prot: UART protocol handle
 * @return 1 if enabled, 0 if disabled
 */
uint8_t UART_Protocol_IsDataOutputEnabled(UART_Protocol_Handle_t *huart_prot)
{
    if (huart_prot == NULL) {
        return 0;
    }
    return huart_prot->uart_data_output_enabled;
}

/**
 * @brief Check if verbose logging is enabled
 * @param huart_prot: UART protocol handle
 * @return 1 if enabled, 0 if disabled
 */
uint8_t UART_Protocol_IsVerboseEnabled(UART_Protocol_Handle_t *huart_prot)
{
    if (huart_prot == NULL) {
        return 0;
    }
    return huart_prot->verbose_enabled;
}
