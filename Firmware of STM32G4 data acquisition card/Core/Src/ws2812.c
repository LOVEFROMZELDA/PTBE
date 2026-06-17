/**
 ******************************************************************************
 * @file    ws2812.c
 * @brief   WS2812 RGB LED driver implementation
 * 
 * @note    WS2812 Timing Requirements (at 800kHz):
 *          - 0 code: HIGH 0.4us (32%), LOW 0.85us (68%) = 1.25us total
 *          - 1 code: HIGH 0.8us (64%), LOW 0.45us (36%) = 1.25us total
 *          - Reset:  LOW > 50us
 * 
 * @note    Timer Configuration:
 *          - Timer frequency: 800kHz (period = 1.25us)
 *          - ARR (Auto-Reload): Based on APB clock
 *          - PWM values: 0 = ~32% duty, 1 = ~64% duty
 ******************************************************************************
 */

#include "ws2812.h"
#include <stdlib.h>
#include <string.h>

/* WS2812 timing parameters (as PWM compare value percentage) */
#define WS2812_0_CODE   32  // 0 code: ~32% duty cycle (0.4us high)
#define WS2812_1_CODE   64  // 1 code: ~64% duty cycle (0.8us high)

/* Static buffer for PWM DMA data */
/* Each LED needs 24 bits (8R + 8G + 8B) + reset pulses */
static uint16_t ws2812_pwm_buffer[(WS2812_LED_COUNT * 24) + WS2812_RESET_PULSES];
static WS2812_Color_t ws2812_colors[WS2812_LED_COUNT];

/**
 * @brief Initialize WS2812 driver
 * @param hws: WS2812 handle
 * @param htim: Timer handle (e.g., &htim8)
 * @param channel: Timer channel (e.g., TIM_CHANNEL_3)
 * @param led_count: Number of LEDs in the chain
 */
void WS2812_Init(WS2812_Handle_t *hws, TIM_HandleTypeDef *htim, uint32_t channel, uint16_t led_count)
{
    if (hws == NULL || htim == NULL) {
        return;
    }

    hws->htim = htim;
    hws->channel = channel;
    hws->led_count = led_count;
    hws->pwm_buffer = ws2812_pwm_buffer;
    hws->colors = ws2812_colors;
    hws->busy = false;

    /* Clear all LEDs */
    WS2812_Clear(hws);
}

/**
 * @brief Set color for a specific LED
 * @param hws: WS2812 handle
 * @param led_index: LED index (0 to led_count-1)
 * @param r: Red value (0-255)
 * @param g: Green value (0-255)
 * @param b: Blue value (0-255)
 */
void WS2812_SetColor(WS2812_Handle_t *hws, uint16_t led_index, uint8_t r, uint8_t g, uint8_t b)
{
    if (hws == NULL || led_index >= hws->led_count) {
        return;
    }

    hws->colors[led_index].r = r;
    hws->colors[led_index].g = g;
    hws->colors[led_index].b = b;
}

/**
 * @brief Set color for a specific LED using color structure
 * @param hws: WS2812 handle
 * @param led_index: LED index
 * @param color: Color structure
 */
void WS2812_SetColorRGB(WS2812_Handle_t *hws, uint16_t led_index, WS2812_Color_t color)
{
    WS2812_SetColor(hws, led_index, color.r, color.g, color.b);
}

/**
 * @brief Set all LEDs to the same color
 * @param hws: WS2812 handle
 * @param r: Red value
 * @param g: Green value
 * @param b: Blue value
 */
void WS2812_SetAllColor(WS2812_Handle_t *hws, uint8_t r, uint8_t g, uint8_t b)
{
    if (hws == NULL) {
        return;
    }

    for (uint16_t i = 0; i < hws->led_count; i++) {
        hws->colors[i].r = r;
        hws->colors[i].g = g;
        hws->colors[i].b = b;
    }
}

/**
 * @brief Clear all LEDs (set to black/off)
 * @param hws: WS2812 handle
 */
void WS2812_Clear(WS2812_Handle_t *hws)
{
    WS2812_SetAllColor(hws, 0, 0, 0);
}

/**
 * @brief Convert color data to PWM buffer and send via DMA
 * @param hws: WS2812 handle
 * @note  This function prepares the PWM buffer and starts DMA transfer
 */
void WS2812_Update(WS2812_Handle_t *hws)
{
    if (hws == NULL || hws->busy) {
        return;
    }

    uint32_t index = 0;
    uint32_t arr_value = __HAL_TIM_GET_AUTORELOAD(hws->htim);

    /* Convert each LED's color to PWM pulses */
    for (uint16_t led = 0; led < hws->led_count; led++) {
        /* WS2812 color order is GRB (not RGB!) */
        uint8_t color_bytes[3] = {
            hws->colors[led].g,  // Green first
            hws->colors[led].r,  // Red second
            hws->colors[led].b   // Blue third
        };

        /* Convert each byte to 8 PWM pulses */
        for (uint8_t byte_idx = 0; byte_idx < 3; byte_idx++) {
            uint8_t byte = color_bytes[byte_idx];
            
            /* MSB first */
            for (int8_t bit = 7; bit >= 0; bit--) {
                if (byte & (1 << bit)) {
                    /* Bit is 1: ~64% duty cycle */
                    hws->pwm_buffer[index] = (arr_value * WS2812_1_CODE) / 100;
                } else {
                    /* Bit is 0: ~32% duty cycle */
                    hws->pwm_buffer[index] = (arr_value * WS2812_0_CODE) / 100;
                }
                index++;
            }
        }
    }

    /* Add reset pulses (low signal) */
    for (uint16_t i = 0; i < WS2812_RESET_PULSES; i++) {
        hws->pwm_buffer[index++] = 0;
    }

    /* Start PWM with DMA */
    hws->busy = true;
    HAL_TIM_PWM_Start_DMA(hws->htim, hws->channel, 
                          (uint32_t*)hws->pwm_buffer, 
                          (hws->led_count * 24) + WS2812_RESET_PULSES);
}

/**
 * @brief Set brightness for a specific LED (scales RGB values)
 * @param hws: WS2812 handle
 * @param led_index: LED index
 * @param brightness: Brightness (0-255)
 */
void WS2812_SetBrightness(WS2812_Handle_t *hws, uint16_t led_index, uint8_t brightness)
{
    if (hws == NULL || led_index >= hws->led_count) {
        return;
    }

    hws->colors[led_index].r = (hws->colors[led_index].r * brightness) / 255;
    hws->colors[led_index].g = (hws->colors[led_index].g * brightness) / 255;
    hws->colors[led_index].b = (hws->colors[led_index].b * brightness) / 255;
}

/**
 * @brief Check if WS2812 is busy (DMA transfer in progress)
 * @param hws: WS2812 handle
 * @retval true if busy, false if ready
 */
bool WS2812_IsBusy(WS2812_Handle_t *hws)
{
    return (hws != NULL) ? hws->busy : false;
}

/**
 * @brief DMA transfer complete callback
 * @param hws: WS2812 handle
 * @note  Call this from HAL_TIM_PWM_PulseFinishedCallback
 */
void WS2812_DMA_TransferComplete(WS2812_Handle_t *hws)
{
    if (hws == NULL) {
        return;
    }

    /* Stop PWM */
    HAL_TIM_PWM_Stop_DMA(hws->htim, hws->channel);
    hws->busy = false;
}
