/**
 ******************************************************************************
 * @file    config_storage.h
 * @brief   Configuration storage in Flash memory
 * @note    Uses the last page of Flash to store PCA-ADC configurations
 ******************************************************************************
 */

#ifndef __CONFIG_STORAGE_H__
#define __CONFIG_STORAGE_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include "pca_adc_integration.h"
#include <stdint.h>
#include <stdbool.h>

/* Flash configuration */
/* STM32G431 has 128KB Flash, Page size is 2KB */
/* We use the last page (Page 63) for configuration storage */
#define STORAGE_PAGE_SIZE         2048
#define FLASH_TOTAL_PAGES       64
#define CONFIG_FLASH_PAGE       63  // Last page
#define CONFIG_FLASH_ADDRESS    (FLASH_BASE + (CONFIG_FLASH_PAGE * STORAGE_PAGE_SIZE))

/* Configuration structure version */
#define CONFIG_VERSION          0x02  // V2: 8-channel motor control mode

/**
 * @brief Configuration storage structure
 */
typedef struct {
    uint32_t magic;                     // Magic number for validation
    uint8_t version;                    // Configuration version
    uint8_t channel_count;              // Number of configured channels
    uint16_t reserved;                  // Reserved for alignment
    PCA_ADC_ChannelConfig_t channels[PCA_ADC_MAX_CHANNELS];
    uint32_t crc;                       // CRC32 checksum
} Config_Storage_t;

/* Magic number for configuration validation */
#define CONFIG_MAGIC            0x50434139  // "PCA9" in ASCII

/* Function prototypes */
bool Config_Storage_Save(PCA_ADC_Handle_t *hpca_adc);
bool Config_Storage_Load(PCA_ADC_Handle_t *hpca_adc);
bool Config_Storage_Erase(void);
bool Config_Storage_IsValid(void);

#ifdef __cplusplus
}
#endif

#endif /* __CONFIG_STORAGE_H__ */
