/**
 ******************************************************************************
 * @file    pca9635_driver.c
 * @brief   PCA9635 16-channel PWM LED driver implementation
 ******************************************************************************
 */

#include "pca9635_driver.h"
#include <string.h>

/* I2C timeout in milliseconds */
#define PCA9635_I2C_TIMEOUT     100

/* Private function prototypes */
static uint8_t PCA9635_WriteRegister(PCA9635_HandleTypeDef *hpca, uint8_t reg, uint8_t value);
static uint8_t PCA9635_ReadRegister(PCA9635_HandleTypeDef *hpca, uint8_t reg, uint8_t *value);
static uint8_t PCA9635_WriteMultiple(PCA9635_HandleTypeDef *hpca, uint8_t reg, uint8_t *data, uint8_t length);

/**
 * @brief Initialize PCA9635 device
 * @param hpca: PCA9635 handle
 * @param hi2c: I2C handle
 * @param address: I2C device address (7-bit)
 * @retval Error code
 */
uint8_t PCA9635_Init(PCA9635_HandleTypeDef *hpca, I2C_HandleTypeDef *hi2c, uint8_t address)
{
    if (hpca == NULL || hi2c == NULL) {
        return PCA9635_ERR_PARAM;
    }

    hpca->hi2c = hi2c;
    hpca->address = address;
    hpca->error = PCA9635_OK;

    /* Configure MODE1: Enable ALLCALL (0x01) - matches reference implementations */
    uint8_t mode1 = 0x01;  // ALLCALL enabled, normal mode, no sleep
    if (PCA9635_WriteRegister(hpca, PCA9635_MODE1, mode1) != PCA9635_OK) {
        return hpca->error;
    }

    /* CRITICAL: 500μs delay for oscillator stabilization (per PCA9635 datasheet) */
    /* Reference: pca9635rpi.c line 138 - mandatory delay */
    HAL_Delay(10);  // 1ms delay (500μs minimum required)

    /* Configure MODE2: Totem-pole output, non-inverted */
    uint8_t mode2 = PCA9635_MODE2_OUTDRV | PCA9635_MODE2_INVRT;  // 0x04
    if (PCA9635_WriteRegister(hpca, PCA9635_MODE2, mode2) != PCA9635_OK) {
        return hpca->error;
    }

    /* Initialize all LEDOUT registers to 0xAA (all channels in individual PWM mode) */
    /* 0xAA = 0b10101010, each 2 bits = 10 (PWM mode), not 11 (GRPPWM mode) */
    /* Reference: Arduino PCA9635.cpp setLedDriverModeAll() with LEDPWM mode */
    uint8_t ledout_init[4] = {0xAA, 0xAA, 0xAA, 0xAA};
    if (PCA9635_WriteMultiple(hpca, PCA9635_LEDOUT_BASE | PCA9635_AUTO_INC, ledout_init, 4) != PCA9635_OK) {
        return hpca->error;
    }

    /* Verify MODE1 and MODE2 registers were written correctly */
    /* Reference: pca9635rpi.c lines 131-136 - readback verification */
    uint8_t verify_mode1, verify_mode2;
    if (PCA9635_ReadRegister(hpca, PCA9635_MODE1, &verify_mode1) != PCA9635_OK) {
        return hpca->error;
    }
    if (PCA9635_ReadRegister(hpca, PCA9635_MODE2, &verify_mode2) != PCA9635_OK) {
        return hpca->error;
    }

    /* Check if values match what we wrote */
    if (verify_mode1 != mode1 || verify_mode2 != mode2) {
        hpca->error = PCA9635_ERR_I2C;
        return PCA9635_ERR_I2C;
    }

    /* Set all PWM values to 0 (off) */
    PCA9635_AllOff(hpca);

    return PCA9635_OK;
}

/**
 * @brief Reset PCA9635 to default state
 * @param hpca: PCA9635 handle
 * @retval Error code
 */
uint8_t PCA9635_Reset(PCA9635_HandleTypeDef *hpca)
{
    if (hpca == NULL) {
        return PCA9635_ERR_PARAM;
    }

    /* Software reset via MODE1 register */
    return PCA9635_WriteRegister(hpca, PCA9635_MODE1, 0x00);
}

/**
 * @brief Set MODE1 register
 * @param hpca: PCA9635 handle
 * @param mode: MODE1 register value
 * @retval Error code
 */
uint8_t PCA9635_SetMode1(PCA9635_HandleTypeDef *hpca, uint8_t mode)
{
    return PCA9635_WriteRegister(hpca, PCA9635_MODE1, mode);
}

/**
 * @brief Set MODE2 register
 * @param hpca: PCA9635 handle
 * @param mode: MODE2 register value
 * @retval Error code
 */
uint8_t PCA9635_SetMode2(PCA9635_HandleTypeDef *hpca, uint8_t mode)
{
    return PCA9635_WriteRegister(hpca, PCA9635_MODE2, mode);
}

/**
 * @brief Get MODE1 register
 * @param hpca: PCA9635 handle
 * @param mode: Pointer to store MODE1 value
 * @retval Error code
 */
uint8_t PCA9635_GetMode1(PCA9635_HandleTypeDef *hpca, uint8_t *mode)
{
    return PCA9635_ReadRegister(hpca, PCA9635_MODE1, mode);
}

/**
 * @brief Get MODE2 register
 * @param hpca: PCA9635 handle
 * @param mode: Pointer to store MODE2 value
 * @retval Error code
 */
uint8_t PCA9635_GetMode2(PCA9635_HandleTypeDef *hpca, uint8_t *mode)
{
    return PCA9635_ReadRegister(hpca, PCA9635_MODE2, mode);
}

/**
 * @brief Set LED driver mode for a single channel
 * @param hpca: PCA9635 handle
 * @param channel: LED channel (0-15)
 * @param mode: LED mode (PCA9635_LED_OFF/ON/PWM/GRPPWM)
 * @retval Error code
 */
uint8_t PCA9635_SetLedDriverMode(PCA9635_HandleTypeDef *hpca, uint8_t channel, uint8_t mode)
{
    if (channel >= PCA9635_CHANNEL_COUNT) {
        hpca->error = PCA9635_ERR_CHANNEL;
        return PCA9635_ERR_CHANNEL;
    }

    if (mode > PCA9635_LED_GRPPWM) {
        hpca->error = PCA9635_ERR_PARAM;
        return PCA9635_ERR_PARAM;
    }

    /* Calculate LEDOUT register and bit position */
    uint8_t reg = PCA9635_LEDOUT_BASE + (channel >> 2);  // Divide by 4
    uint8_t shift = (channel & 0x03) << 1;  // (channel % 4) * 2

    /* Read current register value */
    uint8_t value;
    if (PCA9635_ReadRegister(hpca, reg, &value) != PCA9635_OK) {
        return hpca->error;
    }

    /* Modify the bits for this channel */
    value &= ~(0x03 << shift);  // Clear bits
    value |= (mode << shift);   // Set new mode

    /* Write back */
    return PCA9635_WriteRegister(hpca, reg, value);
}

/**
 * @brief Set LED driver mode for all channels
 * @param hpca: PCA9635 handle
 * @param mode: LED mode (PCA9635_LED_OFF/ON/PWM/GRPPWM)
 * @retval Error code
 */
uint8_t PCA9635_SetLedDriverModeAll(PCA9635_HandleTypeDef *hpca, uint8_t mode)
{
    if (mode > PCA9635_LED_GRPPWM) {
        hpca->error = PCA9635_ERR_PARAM;
        return PCA9635_ERR_PARAM;
    }

    /* Create bit pattern for all 4 channels in each register */
    uint8_t value = (mode << 6) | (mode << 4) | (mode << 2) | mode;

    /* Write to all 4 LEDOUT registers */
    uint8_t data[4] = {value, value, value, value};
    return PCA9635_WriteMultiple(hpca, PCA9635_LEDOUT_BASE | PCA9635_AUTO_INC, data, 4);
}

/**
 * @brief Set PWM value for a single channel
 * @param hpca: PCA9635 handle
 * @param channel: LED channel (0-15)
 * @param value: PWM value (0-255)
 * @retval Error code
 */
uint8_t PCA9635_SetPWM(PCA9635_HandleTypeDef *hpca, uint8_t channel, uint8_t value)
{
    if (channel >= PCA9635_CHANNEL_COUNT) {
        hpca->error = PCA9635_ERR_CHANNEL;
        return PCA9635_ERR_CHANNEL;
    }

    uint8_t reg = PCA9635_PWM_BASE + channel;
    return PCA9635_WriteRegister(hpca, reg, value);
}

/**
 * @brief Set PWM values for all channels
 * @param hpca: PCA9635 handle
 * @param values: Array of 16 PWM values (0-255)
 * @retval Error code
 */
uint8_t PCA9635_SetPWMAll(PCA9635_HandleTypeDef *hpca, uint8_t *values)
{
    if (values == NULL) {
        hpca->error = PCA9635_ERR_PARAM;
        return PCA9635_ERR_PARAM;
    }

    /* Use auto-increment to write all 16 PWM registers */
    return PCA9635_WriteMultiple(hpca, PCA9635_PWM_BASE | PCA9635_AUTO_INC, values, 16);
}

/**
 * @brief Get PWM value for a single channel
 * @param hpca: PCA9635 handle
 * @param channel: LED channel (0-15)
 * @param value: Pointer to store PWM value
 * @retval Error code
 */
uint8_t PCA9635_GetPWM(PCA9635_HandleTypeDef *hpca, uint8_t channel, uint8_t *value)
{
    if (channel >= PCA9635_CHANNEL_COUNT) {
        hpca->error = PCA9635_ERR_CHANNEL;
        return PCA9635_ERR_CHANNEL;
    }

    uint8_t reg = PCA9635_PWM_BASE + channel;
    return PCA9635_ReadRegister(hpca, reg, value);
}

/**
 * @brief Set group PWM value
 * @param hpca: PCA9635 handle
 * @param value: Group PWM value (0-255)
 * @retval Error code
 */
uint8_t PCA9635_SetGroupPWM(PCA9635_HandleTypeDef *hpca, uint8_t value)
{
    return PCA9635_WriteRegister(hpca, PCA9635_GRPPWM, value);
}

/**
 * @brief Set group frequency
 * @param hpca: PCA9635 handle
 * @param value: Frequency value (0-255)
 * @retval Error code
 */
uint8_t PCA9635_SetGroupFreq(PCA9635_HandleTypeDef *hpca, uint8_t value)
{
    return PCA9635_WriteRegister(hpca, PCA9635_GRPFREQ, value);
}

/**
 * @brief Turn off all channels
 * @param hpca: PCA9635 handle
 * @retval Error code
 */
uint8_t PCA9635_AllOff(PCA9635_HandleTypeDef *hpca)
{
    uint8_t values[16] = {0};
    return PCA9635_SetPWMAll(hpca, values);
}

/**
 * @brief Turn on all channels to full brightness
 * @param hpca: PCA9635 handle
 * @retval Error code
 */
uint8_t PCA9635_AllOn(PCA9635_HandleTypeDef *hpca)
{
    uint8_t values[16];
    memset(values, 0xFF, 16);
    return PCA9635_SetPWMAll(hpca, values);
}

/**
 * @brief Get last error code
 * @param hpca: PCA9635 handle
 * @retval Error code
 */
uint8_t PCA9635_GetLastError(PCA9635_HandleTypeDef *hpca)
{
    if (hpca == NULL) {
        return PCA9635_ERR_PARAM;
    }
    return hpca->error;
}

/**
 * @brief Write a single register
 * @param hpca: PCA9635 handle
 * @param reg: Register address
 * @param value: Value to write
 * @retval Error code
 */
static uint8_t PCA9635_WriteRegister(PCA9635_HandleTypeDef *hpca, uint8_t reg, uint8_t value)
{
    uint8_t data[2] = {reg, value};
    HAL_StatusTypeDef status;

    status = HAL_I2C_Master_Transmit(hpca->hi2c, hpca->address << 1, data, 2, PCA9635_I2C_TIMEOUT);

    if (status != HAL_OK) {
        hpca->error = PCA9635_ERR_I2C;
        return PCA9635_ERR_I2C;
    }

    hpca->error = PCA9635_OK;
    return PCA9635_OK;
}

/**
 * @brief Read a single register
 * @param hpca: PCA9635 handle
 * @param reg: Register address
 * @param value: Pointer to store read value
 * @retval Error code
 */
static uint8_t PCA9635_ReadRegister(PCA9635_HandleTypeDef *hpca, uint8_t reg, uint8_t *value)
{
    HAL_StatusTypeDef status;

    /* Write register address */
    status = HAL_I2C_Master_Transmit(hpca->hi2c, hpca->address << 1, &reg, 1, PCA9635_I2C_TIMEOUT);
    if (status != HAL_OK) {
        hpca->error = PCA9635_ERR_I2C;
        return PCA9635_ERR_I2C;
    }

    /* Read register value */
    status = HAL_I2C_Master_Receive(hpca->hi2c, hpca->address << 1, value, 1, PCA9635_I2C_TIMEOUT);
    if (status != HAL_OK) {
        hpca->error = PCA9635_ERR_I2C;
        return PCA9635_ERR_I2C;
    }

    hpca->error = PCA9635_OK;
    return PCA9635_OK;
}

/**
 * @brief Write multiple registers (with auto-increment)
 * @param hpca: PCA9635 handle
 * @param reg: Starting register address (with auto-increment bit if needed)
 * @param data: Data array to write
 * @param length: Number of bytes to write
 * @retval Error code
 */
static uint8_t PCA9635_WriteMultiple(PCA9635_HandleTypeDef *hpca, uint8_t reg, uint8_t *data, uint8_t length)
{
    uint8_t buffer[17];  // 1 byte register + max 16 bytes data
    HAL_StatusTypeDef status;

    if (length > 16) {
        hpca->error = PCA9635_ERR_PARAM;
        return PCA9635_ERR_PARAM;
    }

    buffer[0] = reg;
    memcpy(&buffer[1], data, length);

    status = HAL_I2C_Master_Transmit(hpca->hi2c, hpca->address << 1, buffer, length + 1, PCA9635_I2C_TIMEOUT);

    if (status != HAL_OK) {
        hpca->error = PCA9635_ERR_I2C;
        return PCA9635_ERR_I2C;
    }

    hpca->error = PCA9635_OK;
    return PCA9635_OK;
}
