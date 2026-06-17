/**
 ******************************************************************************
 * @file    pca9635_driver.h
 * @brief   PCA9635 16-channel PWM LED driver for STM32
 * @note    Ported from Arduino library to STM32 HAL
 ******************************************************************************
 */

#ifndef __PCA9635_DRIVER_H__
#define __PCA9635_DRIVER_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include "i2c.h"

/* PCA9635 Registers */
#define PCA9635_MODE1               0x00
#define PCA9635_MODE2               0x01
#define PCA9635_PWM_BASE            0x02    // PWM0 starts at 0x02
#define PCA9635_GRPPWM              0x12
#define PCA9635_GRPFREQ             0x13
#define PCA9635_LEDOUT_BASE         0x14    // LEDOUT0..LEDOUT3
#define PCA9635_SUBADR1             0x15
#define PCA9635_SUBADR2             0x16
#define PCA9635_SUBADR3             0x17
#define PCA9635_ALLCALLADR          0x18

/* Auto-increment flag for register access */
#define PCA9635_AUTO_INC            0x80

/* MODE1 register bits */
#define PCA9635_MODE1_RESTART       0x80
#define PCA9635_MODE1_EXTCLK        0x40
#define PCA9635_MODE1_AI2           0x20
#define PCA9635_MODE1_AI1           0x10
#define PCA9635_MODE1_AI0           0x08
#define PCA9635_MODE1_SLEEP         0x04
#define PCA9635_MODE1_SUB1          0x02
#define PCA9635_MODE1_SUB2          0x01
#define PCA9635_MODE1_ALLCALL       0x00

/* MODE2 register bits */
#define PCA9635_MODE2_DMBLNK        0x20    // 0=dim, 1=blink
#define PCA9635_MODE2_INVRT         0x10    // 0=normal, 1=inverted
#define PCA9635_MODE2_OCH           0x08    // 0=update on STOP, 1=update on ACK
#define PCA9635_MODE2_OUTDRV        0x04    // 0=open-drain, 1=totem-pole
#define PCA9635_MODE2_OUTNE1        0x02
#define PCA9635_MODE2_OUTNE0        0x01

/* LEDOUT register modes (2 bits per LED) */
#define PCA9635_LED_OFF             0x00    // LED driver off
#define PCA9635_LED_ON              0x01    // LED driver on
#define PCA9635_LED_PWM             0x02    // LED driver PWM controlled
#define PCA9635_LED_GRPPWM          0x03    // LED driver group PWM controlled

/* Error codes */
#define PCA9635_OK                  0x00
#define PCA9635_ERR_I2C             0x01
#define PCA9635_ERR_CHANNEL         0x02
#define PCA9635_ERR_PARAM           0x03

/* Default I2C address (7-bit) */
#define PCA9635_DEFAULT_ADDR        0x01

/* Number of channels */
#define PCA9635_CHANNEL_COUNT       16

/**
 * @brief PCA9635 handle structure
 */
typedef struct {
    I2C_HandleTypeDef *hi2c;        // I2C handle
    uint8_t address;                // I2C device address (7-bit)
    uint8_t error;                  // Last error code
} PCA9635_HandleTypeDef;

/* Initialization and Configuration */
uint8_t PCA9635_Init(PCA9635_HandleTypeDef *hpca, I2C_HandleTypeDef *hi2c, uint8_t address);
uint8_t PCA9635_Reset(PCA9635_HandleTypeDef *hpca);
uint8_t PCA9635_SetMode1(PCA9635_HandleTypeDef *hpca, uint8_t mode);
uint8_t PCA9635_SetMode2(PCA9635_HandleTypeDef *hpca, uint8_t mode);
uint8_t PCA9635_GetMode1(PCA9635_HandleTypeDef *hpca, uint8_t *mode);
uint8_t PCA9635_GetMode2(PCA9635_HandleTypeDef *hpca, uint8_t *mode);

/* LED Driver Mode Control */
uint8_t PCA9635_SetLedDriverMode(PCA9635_HandleTypeDef *hpca, uint8_t channel, uint8_t mode);
uint8_t PCA9635_SetLedDriverModeAll(PCA9635_HandleTypeDef *hpca, uint8_t mode);

/* PWM Control */
uint8_t PCA9635_SetPWM(PCA9635_HandleTypeDef *hpca, uint8_t channel, uint8_t value);
uint8_t PCA9635_SetPWMAll(PCA9635_HandleTypeDef *hpca, uint8_t *values);
uint8_t PCA9635_GetPWM(PCA9635_HandleTypeDef *hpca, uint8_t channel, uint8_t *value);

/* Group Control */
uint8_t PCA9635_SetGroupPWM(PCA9635_HandleTypeDef *hpca, uint8_t value);
uint8_t PCA9635_SetGroupFreq(PCA9635_HandleTypeDef *hpca, uint8_t value);

/* Utility Functions */
uint8_t PCA9635_AllOff(PCA9635_HandleTypeDef *hpca);
uint8_t PCA9635_AllOn(PCA9635_HandleTypeDef *hpca);
uint8_t PCA9635_GetLastError(PCA9635_HandleTypeDef *hpca);

#ifdef __cplusplus
}
#endif

#endif /* __PCA9635_DRIVER_H__ */
