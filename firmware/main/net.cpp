#include "net.h"
#include "proto.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "nvs.h"
#include "mdns.h"
#include "lwip/sockets.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include <string.h>
#include <stdio.h>

#define AP_PASSWORD "opendeck"

static esp_netif_t *sta_netif, *ap_netif;
static volatile bool sta_connected = false;
static volatile bool ap_on = false;
static char ap_ssid[33];
static char sta_ssid[33];
static char sta_pass[65];
static int64_t sta_started_us = 0;

static void load_creds(void) {
  sta_ssid[0] = sta_pass[0] = 0;
  nvs_handle_t h;
  if (nvs_open("opendeck", NVS_READONLY, &h) == ESP_OK) {
    size_t n = sizeof(sta_ssid);
    nvs_get_str(h, "ssid", sta_ssid, &n);
    n = sizeof(sta_pass);
    nvs_get_str(h, "pass", sta_pass, &n);
    nvs_close(h);
  }
}

static void start_ap(void) {
  if (ap_on) return;
  wifi_config_t ap = {};
  memcpy(ap.ap.ssid, ap_ssid, strlen(ap_ssid));
  ap.ap.ssid_len = strlen(ap_ssid);
  memcpy(ap.ap.password, AP_PASSWORD, sizeof(AP_PASSWORD));
  ap.ap.authmode = WIFI_AUTH_WPA2_PSK;
  ap.ap.max_connection = 2;
  ap.ap.channel = 6;
  esp_wifi_set_mode(WIFI_MODE_APSTA);
  esp_wifi_set_config(WIFI_IF_AP, &ap);
  ap_on = true;
}

static void stop_ap(void) {
  if (!ap_on) return;
  esp_wifi_set_mode(WIFI_MODE_STA);
  ap_on = false;
}

static void on_event(void *, esp_event_base_t base, int32_t id, void *) {
  if (base == WIFI_EVENT && id == WIFI_EVENT_STA_START) {
    if (sta_ssid[0]) esp_wifi_connect();
  } else if (base == WIFI_EVENT && id == WIFI_EVENT_STA_DISCONNECTED) {
    sta_connected = false;
    if (sta_ssid[0]) esp_wifi_connect();
  } else if (base == IP_EVENT && id == IP_EVENT_STA_GOT_IP) {
    sta_connected = true;
  }
}

static void apply_sta(void) {
  wifi_config_t sta = {};
  memcpy(sta.sta.ssid, sta_ssid, strnlen(sta_ssid, 32));
  memcpy(sta.sta.password, sta_pass, strnlen(sta_pass, 64));
  sta.sta.threshold.authmode = sta_pass[0] ? WIFI_AUTH_WEP : WIFI_AUTH_OPEN;
  esp_wifi_set_config(WIFI_IF_STA, &sta);
  sta_started_us = esp_timer_get_time();
  if (sta_ssid[0]) esp_wifi_connect();
}

void net_set_wifi(const char *ssid, const char *pass) {
  nvs_handle_t h;
  if (nvs_open("opendeck", NVS_READWRITE, &h) == ESP_OK) {
    nvs_set_str(h, "ssid", ssid);
    nvs_set_str(h, "pass", pass);
    nvs_commit(h);
    nvs_close(h);
  }
  load_creds();
  esp_wifi_disconnect();
  apply_sta();
}

void net_status(NetStatus *s) {
  s->ap = ap_on && !sta_connected;
  s->connected = sta_connected;
  esp_netif_ip_info_t ip = {};
  if (s->ap) {
    snprintf(s->ssid, sizeof(s->ssid), "%s", ap_ssid);
    esp_netif_get_ip_info(ap_netif, &ip);
  } else {
    snprintf(s->ssid, sizeof(s->ssid), "%s", sta_ssid);
    esp_netif_get_ip_info(sta_netif, &ip);
  }
  snprintf(s->ip, sizeof(s->ip), IPSTR, IP2STR(&ip.ip));
}

// One task multiplexes the TCP listener, up to MAX_NET_CLIENTS clients and the UDP discovery socket.
static void net_task(void *) {
  int lsock = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
  int opt = 1;
  setsockopt(lsock, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
  sockaddr_in addr = {};
  addr.sin_family = AF_INET;
  addr.sin_port = htons(TCP_PORT);
  addr.sin_addr.s_addr = htonl(INADDR_ANY);
  bind(lsock, (sockaddr *)&addr, sizeof(addr));
  listen(lsock, 2);

  int usock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
  addr.sin_port = htons(UDP_PORT);
  bind(usock, (sockaddr *)&addr, sizeof(addr));

  static uint8_t rx[1536];
  while (true) {
    // Hotspot only while the configured network is unreachable.
    if (sta_connected) stop_ap();
    else if (!sta_ssid[0] || esp_timer_get_time() - sta_started_us > 15000000) start_ap();

    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(lsock, &rfds);
    FD_SET(usock, &rfds);
    int maxfd = lsock > usock ? lsock : usock;
    for (auto &c : g_net)
      if (c.used) { FD_SET(c.fd, &rfds); if (c.fd > maxfd) maxfd = c.fd; }
    timeval tv = {0, 200000};
    if (select(maxfd + 1, &rfds, NULL, NULL, &tv) <= 0) continue;

    if (FD_ISSET(lsock, &rfds)) {
      int fd = accept(lsock, NULL, NULL);
      if (fd >= 0) {
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
        bool placed = false;
        for (auto &c : g_net)
          if (!c.used) {
            c.fd = fd; c.len = 0; c.used = true; c.last_rx_us = esp_timer_get_time();
            placed = true;
            break;
          }
        if (!placed) close(fd);
      }
    }
    for (auto &c : g_net) {
      if (!c.used || !FD_ISSET(c.fd, &rfds)) continue;
      int n = recv(c.fd, rx, sizeof(rx), 0);
      if (n <= 0) {
        close(c.fd);
        c.used = false;
        c.fd = -1;
        if (c.up) { fclose(c.up); c.up = nullptr; }
        continue;
      }
      proto_feed(&c, rx, n);
    }
    if (FD_ISSET(usock, &rfds)) {
      sockaddr_in from = {};
      socklen_t fl = sizeof(from);
      int n = recvfrom(usock, rx, sizeof(rx) - 1, 0, (sockaddr *)&from, &fl);
      if (n >= 9 && !memcmp(rx, "OPENDECK?", 9)) {
        char *js = proto_hello_json();
        sendto(usock, js, strlen(js), 0, (sockaddr *)&from, fl);
        free(js);
      }
    }
  }
}

void net_start(void) {
  esp_netif_init();
  esp_event_loop_create_default();
  sta_netif = esp_netif_create_default_wifi_sta();
  ap_netif = esp_netif_create_default_wifi_ap();
  esp_netif_set_hostname(sta_netif, "opendeck");
  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  esp_wifi_init(&cfg);
  esp_wifi_set_storage(WIFI_STORAGE_RAM);
  esp_event_handler_register(WIFI_EVENT, ESP_EVENT_ANY_ID, on_event, NULL);
  esp_event_handler_register(IP_EVENT, IP_EVENT_STA_GOT_IP, on_event, NULL);

  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  snprintf(ap_ssid, sizeof(ap_ssid), "OpenDeck-%02X%02X", mac[4], mac[5]);

  load_creds();
  esp_wifi_set_mode(WIFI_MODE_STA);
  esp_wifi_start();
  apply_sta();
  esp_wifi_set_ps(WIFI_PS_NONE);  // low latency for key events

  if (mdns_init() == ESP_OK) {
    mdns_hostname_set("opendeck");
    mdns_instance_name_set("OpenDeck");
    mdns_service_add(NULL, "_opendeck", "_tcp", TCP_PORT, NULL, 0);
  }
  xTaskCreatePinnedToCore(net_task, "net", 8192, NULL, 5, NULL, 0);
}
