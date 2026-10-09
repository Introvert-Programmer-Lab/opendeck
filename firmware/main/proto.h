// Host link: line-delimited JSON over USB (Serial/JTAG) and TCP. See docs/PROTOCOL.md.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#define MAX_NET_CLIENTS 3
#define LINE_MAX_LEN 8192
#define TCP_PORT 7777
#define UDP_PORT 7778

struct Channel {
  bool used = false;
  bool usb = false;
  bool exec = false;        // this host runs actions (desktop app)
  int fd = -1;
  char *buf = nullptr;
  size_t len = 0;
  FILE *up = nullptr;       // file being uploaded on this channel
  size_t up_left = 0;
  int64_t last_rx_us = 0;   // hosts ping every ~2 s; used for the "host connected" dot
};

extern Channel g_usb;
extern Channel g_net[MAX_NET_CLIENTS];

void proto_feed(Channel *c, const uint8_t *data, size_t n);
void chan_send(Channel *c, const char *s, size_t n);
// JSON object describing the device (also used as the UDP discovery reply).
char *proto_hello_json(void);
