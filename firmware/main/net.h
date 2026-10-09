#pragma once
#include <stddef.h>

struct NetStatus {
  bool ap;          // setup hotspot active
  bool connected;   // station connected to the configured network
  char ssid[33];    // hotspot name in AP mode, network name otherwise
  char ip[16];
};

void net_start(void);
void net_status(NetStatus *s);
// Save new credentials to NVS and reconnect.
void net_set_wifi(const char *ssid, const char *pass);
