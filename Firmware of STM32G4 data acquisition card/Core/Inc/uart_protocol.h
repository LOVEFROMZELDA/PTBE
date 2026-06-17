/**
 ******************************************************************************
 * @file    uart_protocol.h
 * @brief   UART protocol for PCA-ADC configuration and control
 ******************************************************************************
 */

#ifndef __UART_PROTOCOL_H__
#define __UART_PROTOCOL_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include "pca_adc_integration.h"
#include <stdint.h>

/* UART command buffer size */
#define UART_CMD_BUFFER_SIZE    128
#define UART_RESP_BUFFER_SIZE   256

/**
 * @brief Command source enumeration
 */
typedef enum {
    CMD_SOURCE_UART = 0,
    CMD_SOURCE_CDC = 1
} CommandSource_t;

/**
 * @brief UART protocol handle
 */
typedef struct {
    PCA_ADC_Handle_t *hpca_adc;
    UART_HandleTypeDef *huart;
    char cmd_buffer[UART_CMD_BUFFER_SIZE];
    uint8_t cmd_index;
    char resp_buffer[UART_RESP_BUFFER_SIZE];
    uint8_t uart_data_output_enabled;  // Control UART ADC data output
    uint8_t verbose_enabled;            // Control verbose logging
    CommandSource_t command_source;     // Track which interface sent the command
} UART_Protocol_Handle_t;

/* Initialization */
void UART_Protocol_Init(UART_Protocol_Handle_t *huart_prot, PCA_ADC_Handle_t *hpca_adc, UART_HandleTypeDef *huart);

/* Command processing */
void UART_Protocol_SetSource(UART_Protocol_Handle_t *huart_prot, CommandSource_t source);
void UART_Protocol_ProcessByte(UART_Protocol_Handle_t *huart_prot, uint8_t byte);
void UART_Protocol_ProcessCommand(UART_Protocol_Handle_t *huart_prot);

/* Response helpers */
void UART_Protocol_SendOK(UART_Protocol_Handle_t *huart_prot);
void UART_Protocol_SendError(UART_Protocol_Handle_t *huart_prot, const char *error_msg);
void UART_Protocol_SendResponse(UART_Protocol_Handle_t *huart_prot, const char *response);

/* Data output control */
uint8_t UART_Protocol_IsDataOutputEnabled(UART_Protocol_Handle_t *huart_prot);
uint8_t UART_Protocol_IsVerboseEnabled(UART_Protocol_Handle_t *huart_prot);

#ifdef __cplusplus
}
#endif

#endif /* __UART_PROTOCOL_H__ */
