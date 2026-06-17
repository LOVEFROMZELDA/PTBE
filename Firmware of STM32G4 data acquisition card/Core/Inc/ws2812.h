/**
 ******************************************************************************
 * @file    ws2812.h
 * @brief   WS2812 RGB LED driver using PWM+DMA
 * @note    Uses TIM8 CH3 (PB9) for single-wire PWM control
 ******************************************************************************
 */

#ifndef __WS2812_H__
#define __WS2812_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "main.h"
#include <stdint.h>
#include <stdbool.h>

/* WS2812 Configuration */
#define WS2812_LED_COUNT    1       // Number of WS2812 LEDs in chain
#define WS2812_RESET_PULSES 50      // Number of low pulses for reset (>50us)

/* Color structure */
typedef struct {
    uint8_t r;  // Red 0-255
    uint8_t g;  // Green 0-255
    uint8_t b;  // Blue 0-255
} WS2812_Color_t;

/* WS2812 handle */
typedef struct {
    TIM_HandleTypeDef *htim;    // Timer handle
    uint32_t channel;           // Timer channel
    uint16_t *pwm_buffer;       // DMA buffer for PWM data
    WS2812_Color_t *colors;     // Color buffer
    uint16_t led_count;         // Number of LEDs
    bool busy;                  // Transfer in progress
} WS2812_Handle_t;

/* Function prototypes */
void WS2812_Init(WS2812_Handle_t *hws, TIM_HandleTypeDef *htim, uint32_t channel, uint16_t led_count);
void WS2812_SetColor(WS2812_Handle_t *hws, uint16_t led_index, uint8_t r, uint8_t g, uint8_t b);
void WS2812_SetColorRGB(WS2812_Handle_t *hws, uint16_t led_index, WS2812_Color_t color);
void WS2812_SetAllColor(WS2812_Handle_t *hws, uint8_t r, uint8_t g, uint8_t b);
void WS2812_Clear(WS2812_Handle_t *hws);
void WS2812_Update(WS2812_Handle_t *hws);
void WS2812_SetBrightness(WS2812_Handle_t *hws, uint16_t led_index, uint8_t brightness);
bool WS2812_IsBusy(WS2812_Handle_t *hws);

/* Predefined colors */
#define WS2812_COLOR_OFF        {0, 0, 0}
#define WS2812_COLOR_RED        {255, 0, 0}
#define WS2812_COLOR_GREEN      {0, 255, 0}
#define WS2812_COLOR_BLUE       {0, 0, 255}
#define WS2812_COLOR_WHITE      {255, 255, 255}
#define WS2812_COLOR_YELLOW     {255, 255, 0}
#define WS2812_COLOR_CYAN       {0, 255, 255}
#define WS2812_COLOR_MAGENTA    {255, 0, 255}

/* DMA transfer complete callback */
void WS2812_DMA_TransferComplete(WS2812_Handle_t *hws);

#ifdef __cplusplus
}
#endif

#endif /* __WS2812_H__ */
