/**
 ******************************************************************************
 * @file    config_storage.c
 * @brief   Configuration storage implementation
 ******************************************************************************
 */

#include "config_storage.h"
#include "stm32g4xx_hal.h"
#include <string.h>

/* Private function prototypes */
static uint32_t Calculate_CRC32(const uint8_t *data, uint32_t length);

/**
 * @brief Save configuration to Flash
 * @param hpca_adc: PCA-ADC integration handle
 * @retval true on success, false on error
 */
bool Config_Storage_Save(PCA_ADC_Handle_t *hpca_adc)
{
    if (hpca_adc == NULL) {
        return false;
    }

    HAL_StatusTypeDef status;
    Config_Storage_t config;

    /* Prepare configuration structure */
    config.magic = CONFIG_MAGIC;
    config.version = CONFIG_VERSION;
    config.channel_count = PCA_ADC_MAX_CHANNELS;
    config.reserved = 0;

    /* Copy channel configurations */
    memcpy(config.channels, hpca_adc->channels, sizeof(config.channels));

    /* Calculate CRC (exclude CRC field itself) */
    config.crc = Calculate_CRC32((uint8_t*)&config, sizeof(Config_Storage_t) - sizeof(uint32_t));

    /* Unlock Flash */
    HAL_FLASH_Unlock();

    /* Erase the configuration page */
    FLASH_EraseInitTypeDef EraseInitStruct;
    uint32_t PageError = 0;

    EraseInitStruct.TypeErase = FLASH_TYPEERASE_PAGES;
    EraseInitStruct.Page = CONFIG_FLASH_PAGE;
    EraseInitStruct.NbPages = 1;

    status = HAL_FLASHEx_Erase(&EraseInitStruct, &PageError);
    if (status != HAL_OK) {
        HAL_FLASH_Lock();
        return false;
    }

    /* Write configuration to Flash (64-bit aligned) */
    uint64_t *src_ptr = (uint64_t*)&config;
    uint32_t flash_addr = CONFIG_FLASH_ADDRESS;
    uint32_t data_size = sizeof(Config_Storage_t);
    uint32_t num_dwords = (data_size + 7) / 8;  // Round up to 64-bit words

    for (uint32_t i = 0; i < num_dwords; i++) {
        status = HAL_FLASH_Program(FLASH_TYPEPROGRAM_DOUBLEWORD, flash_addr, src_ptr[i]);
        if (status != HAL_OK) {
            HAL_FLASH_Lock();
            return false;
        }
        flash_addr += 8;
    }

    /* Lock Flash */
    HAL_FLASH_Lock();

    return true;
}

/**
 * @brief Load configuration from Flash
 * @param hpca_adc: PCA-ADC integration handle
 * @retval true on success, false on error
 */
bool Config_Storage_Load(PCA_ADC_Handle_t *hpca_adc)
{
    if (hpca_adc == NULL) {
        return false;
    }

    /* Read configuration from Flash */
    Config_Storage_t *flash_config = (Config_Storage_t*)CONFIG_FLASH_ADDRESS;

    /* Validate magic number */
    if (flash_config->magic != CONFIG_MAGIC) {
        return false;
    }

    /* Validate version */
    if (flash_config->version != CONFIG_VERSION) {
        return false;
    }

    /* Validate CRC */
    uint32_t calculated_crc = Calculate_CRC32((uint8_t*)flash_config, 
                                               sizeof(Config_Storage_t) - sizeof(uint32_t));
    if (calculated_crc != flash_config->crc) {
        return false;
    }

    /* Copy configuration to RAM */
    memcpy(hpca_adc->channels, flash_config->channels, sizeof(hpca_adc->channels));

    /* Re-register all configured channels with ADC monitor */
    for (uint8_t i = 0; i < PCA_ADC_MAX_CHANNELS; i++) {
        if (hpca_adc->channels[i].enabled) {
            PCA_ADC_ChannelConfig_t *cfg = &hpca_adc->channels[i];
            
            /* Re-register with ADC monitor */
            ADC_Monitor_ConfigChannel(hpca_adc->hmon, i, 
                                     cfg->adc_channel, 
                                     cfg->monitor_type, 
                                     cfg->threshold, 
                                     NULL,  // No callback needed, integration layer handles it
                                     hpca_adc);
        }
    }

    return true;
}

/**
 * @brief Erase configuration from Flash
 * @retval true on success, false on error
 */
bool Config_Storage_Erase(void)
{
    HAL_StatusTypeDef status;
    FLASH_EraseInitTypeDef EraseInitStruct;
    uint32_t PageError = 0;

    /* Unlock Flash */
    HAL_FLASH_Unlock();

    /* Erase the configuration page */
    EraseInitStruct.TypeErase = FLASH_TYPEERASE_PAGES;
    EraseInitStruct.Page = CONFIG_FLASH_PAGE;
    EraseInitStruct.NbPages = 1;

    status = HAL_FLASHEx_Erase(&EraseInitStruct, &PageError);

    /* Lock Flash */
    HAL_FLASH_Lock();

    return (status == HAL_OK);
}

/**
 * @brief Check if valid configuration exists in Flash
 * @retval true if valid configuration exists, false otherwise
 */
bool Config_Storage_IsValid(void)
{
    Config_Storage_t *flash_config = (Config_Storage_t*)CONFIG_FLASH_ADDRESS;

    /* Check magic number */
    if (flash_config->magic != CONFIG_MAGIC) {
        return false;
    }

    /* Check version */
    if (flash_config->version != CONFIG_VERSION) {
        return false;
    }

    /* Verify CRC */
    uint32_t calculated_crc = Calculate_CRC32((uint8_t*)flash_config, 
                                               sizeof(Config_Storage_t) - sizeof(uint32_t));
    if (calculated_crc != flash_config->crc) {
        return false;
    }

    return true;
}

/**
 * @brief Calculate CRC32 checksum
 * @param data: Data pointer
 * @param length: Data length in bytes
 * @retval CRC32 value
 */
static uint32_t Calculate_CRC32(const uint8_t *data, uint32_t length)
{
    uint32_t crc = 0xFFFFFFFF;
    
    for (uint32_t i = 0; i < length; i++) {
        crc ^= data[i];
        for (uint8_t j = 0; j < 8; j++) {
            if (crc & 1) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc >>= 1;
            }
        }
    }
    
    return ~crc;
}
