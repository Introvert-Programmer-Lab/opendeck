#include "drivers.h"
#include "driver/ledc.h"

static bool inverted;

void backlight_init(gpio_num_t pin, bool active_high) {
  inverted = !active_high;
  ledc_timer_config_t t = {};
  t.speed_mode = LEDC_LOW_SPEED_MODE;
  t.duty_resolution = LEDC_TIMER_8_BIT;
  t.timer_num = LEDC_TIMER_0;
  t.freq_hz = 5000;
  t.clk_cfg = LEDC_AUTO_CLK;
  ledc_timer_config(&t);
  ledc_channel_config_t c = {};
  c.gpio_num = pin;
  c.speed_mode = LEDC_LOW_SPEED_MODE;
  c.channel = LEDC_CHANNEL_0;
  c.timer_sel = LEDC_TIMER_0;
  c.duty = inverted ? 255 : 0;
  ledc_channel_config(&c);
}

void backlight_set(uint8_t level) {
  ledc_set_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0, inverted ? 255 - level : level);
  ledc_update_duty(LEDC_LOW_SPEED_MODE, LEDC_CHANNEL_0);
}
