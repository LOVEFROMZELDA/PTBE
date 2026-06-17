/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.c
  * @brief          : Main program body
  ******************************************************************************
  * @attention
  *
  * Copyright (c) 2025 STMicroelectronics.
  * All rights reserved.
  *
  * This software is licensed under terms that can be found in the LICENSE file
  * in the root directory of this software component. 
  * If no LICENSE file comes with this software, it is provided AS-IS.
  *
  ******************************************************************************
  */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "adc.h"
#include "dma.h"
#include "i2c.h"
#include "tim.h"
#include "usart.h"
#include "usb_device.h"
#include "gpio.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "usbd_cdc_if.h"
#include <stdio.h>
#include <string.h>
#include "pca9635_driver.h"
#include "adc_monitor.h"
#include "pca_adc_integration.h"
#include "uart_protocol.h"
#include "config_storage.h"
#include "ws2812.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */
extern DMA_HandleTypeDef hdma_adc1;
extern DMA_HandleTypeDef hdma_adc2;
/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
uint16_t adc1_buf[9]; 
uint16_t adc2_buf[7];
uint8_t usb_tx_buf[32];
volatile uint8_t adc_conv_complete = 0;

/* PCA9635 and ADC Monitor System */
PCA9635_HandleTypeDef hpca9635;
ADC_MonitorHandle_t adc_monitor;
PCA_ADC_Handle_t pca_adc;
UART_Protocol_Handle_t uart_protocol;

uint16_t combined_adc[16];  // Combined ADC buffer for monitoring
uint8_t uart_rx_byte;

/* WS2812 RGB LED */
WS2812_Handle_t hws2812;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_DMA_Init();
  MX_ADC1_Init();
  MX_ADC2_Init();
  MX_USART1_UART_Init();
  MX_I2C1_Init();
  MX_TIM3_Init();
  MX_USB_Device_Init();
  MX_TIM8_Init();
  /* USER CODE BEGIN 2 */
  uint8_t ret = HAL_OK;
  ret |= HAL_ADCEx_Calibration_Start(&hadc1, ADC_SINGLE_ENDED);
  ret |= HAL_ADCEx_Calibration_Start(&hadc2, ADC_SINGLE_ENDED);

  ret |= HAL_ADC_Start_DMA(&hadc1, (uint32_t*)adc1_buf, 9);
  ret |= HAL_ADC_Start_DMA(&hadc2, (uint32_t*)adc2_buf, 7);

  ret |=  HAL_TIM_Base_Start(&htim3);
  
  /* Initialize PCA9635 Driver */
  static uint8_t error_cnt = 5;
  while (PCA9635_Init(&hpca9635, &hi2c1, PCA9635_DEFAULT_ADDR) != PCA9635_OK && error_cnt--)
  {
    HAL_Delay(1000);
    HAL_UART_Transmit(&huart1, (uint8_t *)"PCA9635 Init Error\r\n", 21, HAL_MAX_DELAY);
  }
  if (error_cnt == 5) {
    HAL_UART_Transmit(&huart1, (uint8_t *)"PCA9635 Initialized Successfully\r\n", 36, HAL_MAX_DELAY);
  }
  
  /* Disable all PCA9635 channels on startup (all motors off) */
  PCA9635_AllOff(&hpca9635);
  
  /* Initialize ADC Monitor System */
  ADC_Monitor_Init(&adc_monitor);
  
  /* Initialize PCA-ADC Integration */
  PCA_ADC_Init(&pca_adc, &hpca9635, &adc_monitor);
  
  /* Initialize UART Protocol */
  UART_Protocol_Init(&uart_protocol, &pca_adc, &huart1);
  
  /* Set verbose handler for trigger logging */
  PCA_ADC_SetVerboseHandler(&pca_adc, &uart_protocol);
  
  /* Enable CDC to receive commands */
  CDC_SetCommandHandler(&uart_protocol);
  
  /* Start UART reception in interrupt mode */
  HAL_UART_Receive_IT(&huart1, &uart_rx_byte, 1);
  
  /* Try to load configuration from Flash */
  if (Config_Storage_IsValid()) {
    Config_Storage_Load(&pca_adc);
    // Configuration loaded successfully from Flash
  }
  
  /* Initialize WS2812 RGB LED */
  WS2812_Init(&hws2812, &htim8, TIM_CHANNEL_3, 1);
  WS2812_SetColor(&hws2812, 0, 255, 0, 0);  // Start with red
  WS2812_Update(&hws2812);
  
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  while (1)
  {
    if (adc_conv_complete) {
      adc_conv_complete = 0;

      // Combine ADC values into a single buffer for monitoring
      combined_adc[0] = adc1_buf[0];
      combined_adc[1] = adc1_buf[1];
      combined_adc[2] = adc1_buf[2];
      combined_adc[3] = adc1_buf[3];
      combined_adc[4] = adc1_buf[4];
      combined_adc[5] = adc1_buf[5];
      combined_adc[6] = adc1_buf[6];
      combined_adc[7] = adc1_buf[7];
      combined_adc[8] = adc1_buf[8];
      combined_adc[9] = adc2_buf[0];
      combined_adc[10] = adc2_buf[1];
      combined_adc[11] = adc2_buf[2];
      combined_adc[12] = adc2_buf[3];
      combined_adc[13] = adc2_buf[4];
      combined_adc[14] = adc2_buf[5];
      combined_adc[15] = adc2_buf[6];
      
      // Process PCA-ADC monitoring and control
      PCA_ADC_Process(&pca_adc, combined_adc, 16);

      // Format data as text for USB
      char text_buf[256];
      int len = sprintf(text_buf,
        "%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\r\n",
        adc1_buf[0], adc1_buf[1], adc1_buf[2], 
        adc1_buf[3], adc1_buf[4], adc1_buf[5], 
        adc1_buf[6], adc1_buf[7], adc1_buf[8],
        adc2_buf[0], adc2_buf[1], adc2_buf[2], 
        adc2_buf[3], adc2_buf[4], adc2_buf[5], adc2_buf[6]
      );
      
      // Transmit via USB CDC
      CDC_Transmit_FS((uint8_t*)text_buf, len);
      
      // Also transmit via UART if enabled
      if (UART_Protocol_IsDataOutputEnabled(&uart_protocol)) {
        HAL_UART_Transmit(&huart1, (uint8_t*)text_buf, len, 100);
      }
    }
    
    /* Rainbow color cycle for WS2812 - indicates STM32 is running */
    static uint32_t last_led_update = 0;
    static uint16_t hue = 0;  // 0-360 degrees
    
    if ((HAL_GetTick() - last_led_update) >= 50) {  // Update every 100ms
      last_led_update = HAL_GetTick();
      
      // Convert HSV to RGB for rainbow effect
      // H: 0-360, S: 100%, V: 100%
      uint8_t r, g, b;
      uint16_t h = hue % 360;
      uint8_t sector = h / 60;
      uint8_t offset = h % 60;
      uint8_t rising = (offset * 255) / 60;
      uint8_t falling = 255 - rising;
      
      switch (sector) {
        case 0: r = 255;    g = rising;  b = 0;      break;  // Red -> Yellow
        case 1: r = falling; g = 255;    b = 0;      break;  // Yellow -> Green
        case 2: r = 0;      g = 255;    b = rising;  break;  // Green -> Cyan
        case 3: r = 0;      g = falling; b = 255;    break;  // Cyan -> Blue
        case 4: r = rising;  g = 0;      b = 255;    break;  // Blue -> Magenta
        case 5: r = 255;    g = 0;      b = falling; break;  // Magenta -> Red
        default: r = 0; g = 0; b = 0; break;
      }
      
      // Apply brightness control (reduce to 20% to avoid blinding)
      const uint8_t BRIGHTNESS = 30;  // 0-255, 51 = 20% brightness
      r = (r * BRIGHTNESS) / 255;
      g = (g * BRIGHTNESS) / 255;
      b = (b * BRIGHTNESS) / 255;
      
      if (!WS2812_IsBusy(&hws2812)) {
        WS2812_SetColor(&hws2812, 0, r, g, b);
        WS2812_Update(&hws2812);
      }
      
      hue += 2;  // Increment hue for smooth transition
      if (hue >= 360) hue = 0;
    }
    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Configure the main internal regulator output voltage
  */
  HAL_PWREx_ControlVoltageScaling(PWR_REGULATOR_VOLTAGE_SCALE1_BOOST);

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI48|RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_ON;
  RCC_OscInitStruct.HSI48State = RCC_HSI48_ON;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = RCC_PLLM_DIV2;
  RCC_OscInitStruct.PLL.PLLN = 85;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ = RCC_PLLQ_DIV4;
  RCC_OscInitStruct.PLL.PLLR = RCC_PLLR_DIV2;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV1;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV1;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_4) != HAL_OK)
  {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */
void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef* hadc)
{
  // Assume synchronous triggering or just use ADC1 as the pacer
  if (hadc->Instance == ADC1)
  {
    adc_conv_complete = 1;
  }
}

void HAL_UART_RxCpltCallback(UART_HandleTypeDef *huart)
{
  if (huart->Instance == USART1)
  {
    /* Set command source to UART before processing */
    UART_Protocol_SetSource(&uart_protocol, CMD_SOURCE_UART);
    
    // Process the received byte
    UART_Protocol_ProcessByte(&uart_protocol, uart_rx_byte);
    
    // Continue receiving
    HAL_UART_Receive_IT(&huart1, &uart_rx_byte, 1);
  }
}

/**
 * @brief PWM pulse finished callback for WS2812
 */
void HAL_TIM_PWM_PulseFinishedCallback(TIM_HandleTypeDef *htim)
{
  if (htim->Instance == TIM8) {
    WS2812_DMA_TransferComplete(&hws2812);
  }
}
/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1)
  {
    HAL_Delay(1000);
    UART_Protocol_SendError(&uart_protocol, "Error_Handler invoked");
  }
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
