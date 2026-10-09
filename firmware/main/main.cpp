// OpenDeck firmware (ESP-IDF)
//
// The app renders every page to a finished JPEG and uploads it with a small
// JSON manifest (deck.json). The firmware decodes pages into PSRAM, handles
// touch and swipes, draws press feedback and toggle states, and reports key
// taps to the connected hosts, which run the actions on the computer.
#include <string>
#include <vector>
#include <string.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include "board.h"
#include "gfx.h"
#include "jpeg.h"
#include "net.h"
#include "proto.h"
#include "cJSON.h"
#include "esp_heap_caps.h"
#include "esp_littlefs.h"
#include "esp_system.h"
#include "esp_timer.h"
#include "esp_app_desc.h"
#include "nvs_flash.h"
#include "nvs.h"
#include "mbedtls/base64.h"
#include "usb_link.h"
#include "lwip/sockets.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "freertos/queue.h"

#define FW_VERSION "0.1.0"
#define FS_ROOT "/fs"
#define DECK_DIR FS_ROOT "/deck"
#define STAGE_DIR FS_ROOT "/stage"
#define CHUNK_RAW 3072

Channel g_usb;
Channel g_net[MAX_NET_CLIENTS];

// Deck model
enum NavKind { NAV_NONE, NAV_NEXT, NAV_PREV, NAV_PAGE, NAV_BRIGHT };
struct Key {
  std::string id;
  int x, y, w, h;
  std::string alt;     // optional image shown while the key's state is "on"
  bool on = false;
  NavKind nav = NAV_NONE;
  int arg = 0;
  std::vector<HidOp> hid;  // what the deck does by itself when no computer app handles it
};
struct Page {
  std::string img;
  std::vector<Key> keys;
};

static std::vector<Page> pages;
static int cur_page = 0;
static int rotation = 0;
static int brightness = 200;
static int dot_x = -1, dot_y = -1;
static uint16_t accent = COL_LIME;
static bool deck_loaded = false;
static char device_name[32] = "OpenDeck";
static int lcd_variant = 0;
static volatile int fill_request = -1;  // diagnostic solid fill

#if BOARD_FRAMEBUFFER
static uint16_t *fb, *page_buf;  // composed frame and decoded page, both in PSRAM
#else
#define BAND_H 32
static uint16_t *band;  // the screen is redrawn BAND_H rows at a time
#endif
static SemaphoreHandle_t lock;
static volatile bool dirty = true;
static int dirty_y0 = 0, dirty_y1 = DISP_H;  // rows that need a redraw
volatile uint32_t g_frames, g_flush_ms, g_flush_timeouts;
static int pressed = -1;
static bool show_info = false;

// Helpers
static bool host_active(const Channel &c) {
  return (c.usb || c.used) && c.last_rx_us && esp_timer_get_time() - c.last_rx_us < 6000000;
}
// A desktop app that runs actions has registered with {"t":"host","exec":true}.
static bool executor_present(void) {
  if (host_active(g_usb) && g_usb.exec) return true;
  for (auto &c : g_net) if (c.used && c.exec && host_active(c)) return true;
  return false;
}

static bool any_host(void) {
  if (host_active(g_usb)) return true;
  for (auto &c : g_net) if (host_active(c)) return true;
  return false;
}

void chan_send(Channel *c, const char *s, size_t n) {
  if (c->usb) {
    if (!host_active(*c)) return;  // nobody reading: don't stall
    usb_link_write(s, n);
  } else if (c->used) {
    send(c->fd, s, n, 0);
  }
}

static void send_json(Channel *c, cJSON *j) {
  char *s = cJSON_PrintUnformatted(j);
  std::string line(s);
  line += '\n';
  chan_send(c, line.data(), line.size());
  cJSON_free(s);
}

static void broadcast(cJSON *j) {
  send_json(&g_usb, j);
  for (auto &c : g_net) if (c.used) send_json(&c, j);
}

static void reply(Channel *c, bool ok, const char *msg = nullptr) {
  cJSON *j = cJSON_CreateObject();
  cJSON_AddStringToObject(j, "t", ok ? "ok" : "err");
  if (msg) cJSON_AddStringToObject(j, "m", msg);
  send_json(c, j);
  cJSON_Delete(j);
}

static void rmrf(const std::string &path) {
  struct stat st;
  if (stat(path.c_str(), &st) != 0) return;
  if (S_ISDIR(st.st_mode)) {
    DIR *d = opendir(path.c_str());
    if (d) {
      struct dirent *e;
      std::vector<std::string> names;
      while ((e = readdir(d))) names.push_back(e->d_name);
      closedir(d);
      for (auto &n : names) if (n != "." && n != "..") rmrf(path + "/" + n);
    }
    rmdir(path.c_str());
  } else {
    unlink(path.c_str());
  }
}

static bool safe_name(const char *n) {
  size_t l = strlen(n);
  if (l == 0 || l > 31 || n[0] == '.') return false;
  for (size_t i = 0; i < l; i++) {
    char c = n[i];
    if (!(isalnum((unsigned char)c) || c == '_' || c == '-' || c == '.')) return false;
  }
  return true;
}

// Rendering
static void mark_dirty(void) {
  dirty_y0 = 0;
  dirty_y1 = DISP_H;
  dirty = true;
}

static void mark_dirty_rows(int y, int h) {
  if (!dirty) {
    dirty_y0 = y;
    dirty_y1 = y + h;
  } else {
    if (y < dirty_y0) dirty_y0 = y;
    if (y + h > dirty_y1) dirty_y1 = y + h;
  }
  if (dirty_y0 < 0) dirty_y0 = 0;
  if (dirty_y1 > DISP_H) dirty_y1 = DISP_H;
  dirty = true;
}

static std::string page_path(void) { return std::string(DECK_DIR "/") + pages[cur_page].img; }

static void load_page_image(void) {
#if BOARD_FRAMEBUFFER
  Canvas c = {page_buf, 0, 0, DISP_W, DISP_H};
  gfx_fill(c, COL_DARK);
  if (!deck_loaded || pages.empty()) return;
  if (cur_page < 0 || cur_page >= (int)pages.size()) cur_page = 0;
  jpeg_draw_file(c, page_path().c_str(), 0, 0);
#else
  if (cur_page < 0 || cur_page >= (int)pages.size()) cur_page = 0;
#endif
}

static void compose_info(const Canvas &c) {
  gfx_fill(c, COL_DARK);
  // Small screens drop the logo image and use a text title.
  bool roomy = DISP_H >= 420;
  int y = roomy ? 36 : 14;
  if (roomy) {
    jpeg_draw_mem(c, SPLASH, sizeof(SPLASH), (DISP_W - SPLASH_W) / 2, y);
    y += SPLASH_H + 28;
  } else {
    gfx_text_center(c, FONT_BIG, DISP_W, y, "OpenDeck", COL_LIME);
    y += FONT_BIG.line_h + 12;
  }

  NetStatus ns;
  net_status(&ns);
  if (ns.ap) {
    gfx_text_center(c, FONT_BODY, DISP_W, y, "Wi-Fi setup hotspot", COL_MUTED); y += FONT_BODY.line_h + 4;
    gfx_text_center(c, FONT_BIG, DISP_W, y, ns.ssid, COL_TEXT); y += FONT_BIG.line_h + 4;
    gfx_text_center(c, FONT_BODY, DISP_W, y, "password: opendeck", COL_TEXT); y += FONT_BODY.line_h + 2;
    gfx_text_center(c, FONT_BODY, DISP_W, y, ns.ip, COL_MUTED); y += FONT_BODY.line_h;
  } else if (ns.connected) {
    gfx_text_center(c, FONT_BODY, DISP_W, y, ns.ssid, COL_MUTED); y += FONT_BODY.line_h + 4;
    gfx_text_center(c, FONT_BIG, DISP_W, y, ns.ip, COL_TEXT); y += FONT_BIG.line_h;
  } else {
    gfx_text_center(c, FONT_BODY, DISP_W, y, "Connecting to Wi-Fi...", COL_MUTED); y += FONT_BODY.line_h;
  }
  y += roomy ? 22 : 12;
  gfx_text_center(c, FONT_BODY, DISP_W, y, any_host() ? "App connected" : "Open the OpenDeck app", any_host() ? COL_LIME : COL_TEXT);
  y += FONT_BODY.line_h + 2;
  gfx_text_center(c, FONT_BODY, DISP_W, y, deck_loaded ? "Tap to return to your deck" : "to design your deck", COL_MUTED);
  char ver[48];
  snprintf(ver, sizeof(ver), "fw " FW_VERSION "  |  %s", BOARD_NAME);
  gfx_text_center(c, FONT_BODY, DISP_W, DISP_H - 28, ver, COL_MUTED);
}

static void compose(const Canvas &c) {
  if (show_info || !deck_loaded || pages.empty()) {
    compose_info(c);
    return;
  }
#if BOARD_FRAMEBUFFER
  gfx_blit_screen(c, page_buf, DISP_W);
#else
  gfx_fill(c, COL_DARK);
  jpeg_draw_file(c, page_path().c_str(), 0, 0);
#endif
  Page &p = pages[cur_page];
  for (auto &k : p.keys)
    if (k.on && !k.alt.empty() && gfx_overlaps(c, k.x, k.y, k.w, k.h)) {
      std::string path = std::string(DECK_DIR "/") + k.alt;
      jpeg_draw_file(c, path.c_str(), k.x, k.y);
    }
  if (pressed >= 0 && pressed < (int)p.keys.size()) {
    Key &k = p.keys[pressed];
    gfx_darken_rect(c, k.x, k.y, k.w, k.h);
    gfx_round_outline(c, k.x, k.y, k.w, k.h, 12, 3, accent);
  }
  if (dot_x >= 0) gfx_fill_circle(c, dot_x, dot_y, 4, any_host() ? accent : COL_MUTED);
}

// Draw the whole screen with fn. On framebuffer boards the frame is pushed in one go.
static void paint_screen(void (*fn)(const Canvas &)) {
#if BOARD_FRAMEBUFFER
  Canvas c = {fb, 0, 0, DISP_W, DISP_H};
  fn(c);
  board_display_draw(0, 0, DISP_W, DISP_H, fb);
#else
  for (int y = 0; y < DISP_H; y += BAND_H) {
    Canvas c = {band, 0, y, DISP_W, DISP_H - y < BAND_H ? DISP_H - y : BAND_H};
    fn(c);
    board_display_draw(0, y, c.w, c.h, band);
  }
#endif
}

static void draw_splash(const Canvas &c) {
  gfx_fill(c, COL_DARK);
  jpeg_draw_mem(c, SPLASH, sizeof(SPLASH), (DISP_W - SPLASH_W) / 2, (DISP_H - SPLASH_H) / 2);
}

static uint16_t fill_color;
static void draw_fill(const Canvas &c) { gfx_fill(c, fill_color); }

// Deck i/o
static int jint(cJSON *o, const char *k, int def) {
  cJSON *v = cJSON_GetObjectItem(o, k);
  return cJSON_IsNumber(v) ? v->valueint : def;
}
static const char *jstr(cJSON *o, const char *k, const char *def) {
  cJSON *v = cJSON_GetObjectItem(o, k);
  return cJSON_IsString(v) ? v->valuestring : def;
}

static void load_deck(void) {
  pages.clear();
  deck_loaded = false;
  FILE *f = fopen(DECK_DIR "/deck.json", "rb");
  if (f) {
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    std::string s(n, '\0');
    fread(&s[0], 1, n, f);
    fclose(f);
    cJSON *doc = cJSON_Parse(s.c_str());
    if (doc) {
      rotation = jint(doc, "rot", 0);
      brightness = jint(doc, "bright", 200);
      accent = (uint16_t)jint(doc, "acc", COL_LIME);
      cJSON *dot = cJSON_GetObjectItem(doc, "dot");
      if (cJSON_GetArraySize(dot) == 2) {
        dot_x = cJSON_GetArrayItem(dot, 0)->valueint;
        dot_y = cJSON_GetArrayItem(dot, 1)->valueint;
      } else {
        dot_x = dot_y = -1;
      }
      cJSON *po;
      cJSON_ArrayForEach(po, cJSON_GetObjectItem(doc, "pages")) {
        Page p;
        p.img = jstr(po, "img", "");
        cJSON *ko;
        cJSON_ArrayForEach(ko, cJSON_GetObjectItem(po, "keys")) {
          Key k;
          k.id = jstr(ko, "id", "");
          cJSON *r = cJSON_GetObjectItem(ko, "r");
          if (cJSON_GetArraySize(r) != 4) continue;
          k.x = cJSON_GetArrayItem(r, 0)->valueint;
          k.y = cJSON_GetArrayItem(r, 1)->valueint;
          k.w = cJSON_GetArrayItem(r, 2)->valueint;
          k.h = cJSON_GetArrayItem(r, 3)->valueint;
          k.alt = jstr(ko, "alt", "");
          cJSON *op;
          cJSON_ArrayForEach(op, cJSON_GetObjectItem(ko, "hid")) {
            // ["k", mods, key...] | ["c", usage] | ["w", ms] | ["t", "text"]
            const char *kind = cJSON_GetStringValue(cJSON_GetArrayItem(op, 0));
            if (!kind) continue;
            HidOp h{};
            if (kind[0] == 'k') {
              h.kind = HidOp::KEYS;
              h.mods = cJSON_GetArrayItem(op, 1) ? cJSON_GetArrayItem(op, 1)->valueint : 0;
              for (int i = 2; i < cJSON_GetArraySize(op) && h.nkeys < 6; i++) h.keys[h.nkeys++] = cJSON_GetArrayItem(op, i)->valueint;
            } else if (kind[0] == 'c') {
              h.kind = HidOp::CONSUMER;
              h.usage = cJSON_GetArrayItem(op, 1)->valueint;
            } else if (kind[0] == 'w') {
              h.kind = HidOp::WAIT;
              h.usage = cJSON_GetArrayItem(op, 1)->valueint;
            } else if (kind[0] == 't') {
              h.kind = HidOp::TEXT;
              const char *tx = cJSON_GetStringValue(cJSON_GetArrayItem(op, 1));
              h.text = tx ? tx : "";
            } else {
              continue;
            }
            k.hid.push_back(h);
          }
          cJSON *dev = cJSON_GetObjectItem(ko, "dev");
          if (dev) {
            cJSON *nav = cJSON_GetObjectItem(dev, "nav");
            cJSON *br = cJSON_GetObjectItem(dev, "bright");
            if (cJSON_IsString(nav)) k.nav = !strcmp(nav->valuestring, "prev") ? NAV_PREV : NAV_NEXT;
            else if (cJSON_IsNumber(nav)) { k.nav = NAV_PAGE; k.arg = nav->valueint; }
            else if (cJSON_IsNumber(br)) { k.nav = NAV_BRIGHT; k.arg = br->valueint; }
          }
          p.keys.push_back(k);
        }
        pages.push_back(p);
      }
      deck_loaded = !pages.empty();
      cur_page = jint(doc, "start", 0);
      cJSON_Delete(doc);
    }
  }
  if (cur_page < 0 || cur_page >= (int)pages.size()) cur_page = 0;
  board_backlight(brightness);
  load_page_image();
  mark_dirty();
}

static void goto_page(int n) {
  if (pages.empty()) return;
  int cnt = pages.size();
  cur_page = ((n % cnt) + cnt) % cnt;
  load_page_image();
  mark_dirty();
  cJSON *j = cJSON_CreateObject();
  cJSON_AddStringToObject(j, "t", "page");
  cJSON_AddNumberToObject(j, "n", cur_page);
  broadcast(j);
  cJSON_Delete(j);
}

// Protocol
char *proto_hello_json(void) {
  cJSON *d = cJSON_CreateObject();
  cJSON_AddStringToObject(d, "t", "hello");
  cJSON_AddStringToObject(d, "fw", FW_VERSION);
  cJSON_AddStringToObject(d, "board", BOARD_NAME);
  cJSON_AddStringToObject(d, "id", BOARD_ID);
  cJSON_AddStringToObject(d, "name", device_name);
  cJSON_AddNumberToObject(d, "w", DISP_W);
  cJSON_AddNumberToObject(d, "h", DISP_H);
  size_t total = 0, used = 0;
  esp_littlefs_info("storage", &total, &used);
  cJSON_AddNumberToObject(d, "fs_total", total);
  cJSON_AddNumberToObject(d, "fs_used", used);
  cJSON_AddNumberToObject(d, "psram_free", heap_caps_get_free_size(MALLOC_CAP_SPIRAM));
  cJSON_AddNumberToObject(d, "pages", pages.size());
  cJSON_AddNumberToObject(d, "page", cur_page);
  cJSON_AddNumberToObject(d, "port", TCP_PORT);
  cJSON_AddNumberToObject(d, "lcd", lcd_variant);
  cJSON_AddBoolToObject(d, "hid", usb_hid_ready());
  cJSON_AddNumberToObject(d, "frames", g_frames);
  cJSON_AddNumberToObject(d, "flush_ms", g_flush_ms);
  cJSON_AddNumberToObject(d, "flush_timeouts", g_flush_timeouts);
  NetStatus ns;
  net_status(&ns);
  cJSON *w = cJSON_AddObjectToObject(d, "wifi");
  cJSON_AddBoolToObject(w, "ap", ns.ap);
  cJSON_AddBoolToObject(w, "connected", ns.connected);
  cJSON_AddStringToObject(w, "ssid", ns.ssid);
  cJSON_AddStringToObject(w, "ip", ns.ip);
  char *s = cJSON_PrintUnformatted(d);
  cJSON_Delete(d);
  return s;
}

static void handle_line(Channel *c, char *line) {
  cJSON *doc = cJSON_Parse(line);
  if (!doc) {
    size_t n = strlen(line);
    char msg[96];
    snprintf(msg, sizeof(msg), "bad json len=%u head=%.16s tail=%.16s", (unsigned)n, line, n > 16 ? line + n - 16 : line);
    for (char *q = msg; *q; q++) if (*q == '"' || *q == '\\') *q = '_';
    reply(c, false, msg);
    return;
  }
  const char *t = jstr(doc, "t", "");

  if (!strcmp(t, "hello")) {
    char *s = proto_hello_json();
    std::string out = std::string(s) + "\n";
    chan_send(c, out.data(), out.size());
    cJSON_free(s);
  } else if (!strcmp(t, "ping")) {
    const char pong[] = "{\"t\":\"pong\"}\n";
    chan_send(c, pong, sizeof(pong) - 1);
  } else if (!strcmp(t, "begin")) {
    rmrf(STAGE_DIR);
    mkdir(STAGE_DIR, 0777);
    reply(c, true);
  } else if (!strcmp(t, "put")) {
    const char *f = jstr(doc, "f", "");
    if (!safe_name(f)) { reply(c, false, "bad name"); cJSON_Delete(doc); return; }
    if (c->up) fclose(c->up);
    mkdir(STAGE_DIR, 0777);
    std::string p = std::string(STAGE_DIR "/") + f;
    c->up = fopen(p.c_str(), "wb");
    c->up_left = jint(doc, "n", 0);
    if (!c->up) reply(c, false, "open failed");
    else {
      if (c->up_left == 0) { fclose(c->up); c->up = nullptr; }
      reply(c, true);
    }
  } else if (!strcmp(t, "data")) {
    const char *b64 = jstr(doc, "d", "");
    static uint8_t raw[CHUNK_RAW + 16];
    size_t n = 0;
    if (!c->up || mbedtls_base64_decode(raw, sizeof(raw), &n, (const uint8_t *)b64, strlen(b64)) != 0) {
      reply(c, false, "decode");
    } else if (fwrite(raw, 1, n, c->up) != n) {
      fclose(c->up); c->up = nullptr;
      reply(c, false, "storage full");
    } else {
      c->up_left = n >= c->up_left ? 0 : c->up_left - n;
      if (c->up_left == 0) { fclose(c->up); c->up = nullptr; }
      reply(c, true);
    }
  } else if (!strcmp(t, "commit")) {
    struct stat st;
    if (stat(STAGE_DIR "/deck.json", &st) != 0) {
      reply(c, false, "no deck.json");
    } else {
      rmrf(DECK_DIR);
      if (rename(STAGE_DIR, DECK_DIR) != 0) reply(c, false, "rename");
      else { show_info = false; load_deck(); reply(c, true); }
    }
  } else if (!strcmp(t, "get")) {
    // Read back a stored file in chunks (e.g. project.json, so another app instance can sync).
    const char *f = jstr(doc, "f", "");
    int off = jint(doc, "o", 0);
    std::string p = std::string(DECK_DIR "/") + f;
    FILE *fh = safe_name(f) ? fopen(p.c_str(), "rb") : nullptr;
    if (!fh) reply(c, false, "not found");
    else {
      static uint8_t raw[CHUNK_RAW];
      static unsigned char enc[CHUNK_RAW * 4 / 3 + 8];
      fseek(fh, 0, SEEK_END);
      long total = ftell(fh);
      fseek(fh, off, SEEK_SET);
      size_t n = fread(raw, 1, CHUNK_RAW, fh);
      fclose(fh);
      size_t elen = 0;
      mbedtls_base64_encode(enc, sizeof(enc), &elen, raw, n);
      enc[elen] = 0;
      cJSON *d = cJSON_CreateObject();
      cJSON_AddStringToObject(d, "t", "ok");
      cJSON_AddNumberToObject(d, "n", total);
      cJSON_AddStringToObject(d, "d", (const char *)enc);
      send_json(c, d);
      cJSON_Delete(d);
    }
  } else if (!strcmp(t, "state")) {
    const char *id = jstr(doc, "id", "");
    bool on = cJSON_IsTrue(cJSON_GetObjectItem(doc, "on"));
    for (auto &p : pages)
      for (auto &k : p.keys)
        if (k.id == id && k.on != on) {
          k.on = on;
          mark_dirty_rows(k.y, k.h);
        }
    reply(c, true);
  } else if (!strcmp(t, "page")) {
    goto_page(jint(doc, "n", cur_page));
    reply(c, true);
  } else if (!strcmp(t, "bright")) {
    brightness = jint(doc, "v", brightness);
    board_backlight(brightness);
    reply(c, true);
  } else if (!strcmp(t, "wifi")) {
    reply(c, true);
    net_set_wifi(jstr(doc, "ssid", ""), jstr(doc, "pass", ""));
    mark_dirty();
  } else if (!strcmp(t, "name")) {
    snprintf(device_name, sizeof(device_name), "%s", jstr(doc, "v", "OpenDeck"));
    nvs_handle_t h;
    if (nvs_open("opendeck", NVS_READWRITE, &h) == ESP_OK) {
      nvs_set_str(h, "name", device_name);
      nvs_commit(h);
      nvs_close(h);
    }
    reply(c, true);
  } else if (!strcmp(t, "info")) {
    show_info = cJSON_IsTrue(cJSON_GetObjectItem(doc, "on"));
    mark_dirty();
    reply(c, true);
  } else if (!strcmp(t, "host")) {
    // desktop apps that run actions say exec:true; phones (configure only) say false
    c->exec = cJSON_IsTrue(cJSON_GetObjectItem(doc, "exec"));
    reply(c, true);
  } else if (!strcmp(t, "dfu")) {
    if (!usb_can_reboot_to_download()) {
      reply(c, false, "unsupported");
    } else {
      reply(c, true);
      vTaskDelay(pdMS_TO_TICKS(150));
      usb_reboot_to_download();
    }
  } else if (!strcmp(t, "lcd")) {
    // choose the panel init sequence (kept in NVS), then reboot
    nvs_handle_t h;
    if (nvs_open("opendeck", NVS_READWRITE, &h) == ESP_OK) {
      nvs_set_i32(h, "lcd", jint(doc, "v", 0));
      nvs_commit(h);
      nvs_close(h);
    }
    reply(c, true);
    vTaskDelay(pdMS_TO_TICKS(100));
    esp_restart();
#ifdef BOARD_VIRTUAL
  } else if (!strcmp(t, "tap")) {
    board_virtual_tap(jint(doc, "x", 0), jint(doc, "y", 0));
    reply(c, true);
  } else if (!strcmp(t, "shot")) {
    // Rows y..y+n-1 (n up to 8) of the screen copy, RGB565 little endian,
    // base64; "s" is the sampling step, so the copy is DISP_W/s by DISP_H/s.
    int y = jint(doc, "y", 0), n = jint(doc, "n", 1);
    int step = board_virtual_shot_step();
    if (n < 1 || n > 8 || !board_virtual_row(y) || !board_virtual_row(y + n - 1)) {
      reply(c, false, "no row");
    } else {
      static uint8_t raw[8 * DISP_W * 2];
      static unsigned char enc[sizeof(raw) * 4 / 3 + 8];
      size_t row_bytes = DISP_W / step * 2, elen = 0;
      for (int i = 0; i < n; i++) memcpy(raw + i * row_bytes, board_virtual_row(y + i), row_bytes);
      mbedtls_base64_encode(enc, sizeof(enc), &elen, raw, n * row_bytes);
      enc[elen] = 0;
      cJSON *d = cJSON_CreateObject();
      cJSON_AddStringToObject(d, "t", "ok");
      cJSON_AddNumberToObject(d, "s", step);
      cJSON_AddNumberToObject(d, "y", y);
      cJSON_AddStringToObject(d, "d", (const char *)enc);
      send_json(c, d);
      cJSON_Delete(d);
    }
#endif
  } else if (!strcmp(t, "fill")) {
    fill_request = jint(doc, "c", 0xF800);
    reply(c, true);
  } else if (!strcmp(t, "reset")) {
    rmrf(DECK_DIR);
    rmrf(STAGE_DIR);
    load_deck();
    reply(c, true);
  } else if (!strcmp(t, "reboot")) {
    reply(c, true);
    vTaskDelay(pdMS_TO_TICKS(100));
    esp_restart();
  } else {
    reply(c, false, "unknown");
  }
  cJSON_Delete(doc);
}

void proto_feed(Channel *c, const uint8_t *data, size_t n) {
  c->last_rx_us = esp_timer_get_time();
  for (size_t i = 0; i < n; i++) {
    char ch = (char)data[i];
    if (ch == '\n' || ch == '\r') {
      if (c->len) {
        c->buf[c->len] = 0;
        xSemaphoreTake(lock, portMAX_DELAY);
        handle_line(c, c->buf);
        xSemaphoreGive(lock);
        c->len = 0;
      }
    } else if (c->len < LINE_MAX_LEN - 1) {
      c->buf[c->len++] = ch;
    } else {
      c->len = 0;  // overlong line: drop it
    }
  }
}

static void usb_task(void *) {
  static uint8_t rx[512];
  while (true) {
    int n = usb_link_read(rx, sizeof(rx), 20);
    if (n > 0) proto_feed(&g_usb, rx, n);
  }
}

// Touch
static void mark_key(int idx) {
  if (idx >= 0 && idx < (int)pages[cur_page].keys.size()) {
    Key &k = pages[cur_page].keys[idx];
    mark_dirty_rows(k.y, k.h);
  }
}

static int key_at(int x, int y) {
  if (!deck_loaded || pages.empty()) return -1;
  auto &ks = pages[cur_page].keys;
  for (size_t i = 0; i < ks.size(); i++)
    if (x >= ks[i].x && x < ks[i].x + ks[i].w && y >= ks[i].y && y < ks[i].y + ks[i].h) return i;
  return -1;
}

static QueueHandle_t hid_queue;  // const std::vector<HidOp>* to run

static void hid_task(void *) {
  const std::vector<HidOp> *ops;
  while (true)
    if (xQueueReceive(hid_queue, &ops, portMAX_DELAY) == pdTRUE) {
      usb_hid_run(*ops);
      delete ops;
    }
}

static void fire_key(int idx) {
  Key &k = pages[cur_page].keys[idx];
  // The computer app runs actions when it's open (it can do more, e.g. real mic
  // mute); otherwise the deck types the action itself over USB HID.
  bool by_device = !executor_present() && !k.hid.empty() && usb_hid_ready();
  if (by_device) {
    auto *ops = new std::vector<HidOp>(k.hid);
    if (xQueueSend(hid_queue, &ops, 0) != pdTRUE) delete ops;
  }
  cJSON *j = cJSON_CreateObject();
  cJSON_AddStringToObject(j, "t", "key");
  cJSON_AddNumberToObject(j, "p", cur_page);
  cJSON_AddStringToObject(j, "id", k.id.c_str());
  cJSON_AddBoolToObject(j, "h", by_device);
  broadcast(j);
  cJSON_Delete(j);
  switch (k.nav) {
    case NAV_NEXT: goto_page(cur_page + 1); break;
    case NAV_PREV: goto_page(cur_page - 1); break;
    case NAV_PAGE: goto_page(k.arg); break;
    case NAV_BRIGHT:
      brightness = brightness + k.arg;
      if (brightness < 10) brightness = 10;
      if (brightness > 255) brightness = 255;
      board_backlight(brightness);
      break;
    default: break;
  }
}

static void touch_poll(void) {
  // One finger-down..finger-up is one gesture. The AXS15231B goes quiet for
  // tens of ms mid-press and mid-swipe, so a lift only counts after 150 ms with
  // no finger. Any movement turns the gesture into a swipe and cancels the tap.
  static bool touching = false, moved = false;
  static int64_t last_down_us = 0, last_fire_us = 0, tap_guard_until = 0;
  static int last_fire_key = -1;
  static int16_t x0, y0, x1, y1;
  int16_t x, y;
  bool down = board_touch_read(&x, &y);
  int64_t now = esp_timer_get_time();
  if (down) {
    last_down_us = now;
    if (!touching) {
      touching = true;
      moved = false;
      x0 = x1 = x;
      y0 = y1 = y;
      pressed = key_at(x, y);
      mark_key(pressed);
    } else {
      x1 = x;
      y1 = y;
      if (!moved && (abs(x1 - x0) > 18 || abs(y1 - y0) > 18)) {
        moved = true;
        if (pressed >= 0) {
          mark_key(pressed);
          pressed = -1;
        }
      }
    }
    return;
  }
  if (!touching || now - last_down_us < 150000) return;
  touching = false;
  int dx = x1 - x0, dy = y1 - y0, ldx = dx, ldy = dy;
  switch (rotation) {  // native swipe delta -> deck orientation
    case 1: ldx = dy;  ldy = -dx; break;
    case 2: ldx = -dx; ldy = -dy; break;
    case 3: ldx = -dy; ldy = dx;  break;
  }
  int released = pressed;
  pressed = -1;
  if (show_info || !deck_loaded) {
    if (deck_loaded && !moved) {
      show_info = false;
      mark_dirty();
    }
  } else if (moved) {
    if (abs(ldx) > 50 && abs(ldx) > abs(ldy)) {
      goto_page(cur_page + (ldx < 0 ? 1 : -1));
    } else if (ldy > 120 && ldy > abs(ldx) * 2) {
      show_info = true;  // long swipe down: connection info
      mark_dirty();
    }
    tap_guard_until = now + 300000;  // stray taps right after a swipe are part of it
  } else if (released >= 0) {
    mark_key(released);
    if (now > tap_guard_until && key_at(x1, y1) == released &&
        !(released == last_fire_key && now - last_fire_us < 250000)) {
      last_fire_key = released;
      last_fire_us = now;
      fire_key(released);
    }
  }
}

// Main
extern "C" void app_main(void) {
  esp_err_t err = nvs_flash_init();
  if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    nvs_flash_erase();
    nvs_flash_init();
  }
  nvs_handle_t h;
  if (nvs_open("opendeck", NVS_READONLY, &h) == ESP_OK) {
    size_t n = sizeof(device_name);
    nvs_get_str(h, "name", device_name, &n);
    int32_t v = 0;
    if (nvs_get_i32(h, "lcd", &v) == ESP_OK) lcd_variant = v;
    nvs_close(h);
  }
  lock = xSemaphoreCreateMutex();

#if BOARD_FRAMEBUFFER
  fb = (uint16_t *)heap_caps_malloc(DISP_W * DISP_H * 2, MALLOC_CAP_SPIRAM);
  page_buf = (uint16_t *)heap_caps_malloc(DISP_W * DISP_H * 2, MALLOC_CAP_SPIRAM);
#else
  band = (uint16_t *)heap_caps_malloc(DISP_W * BAND_H * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
#endif

  board_display_init(lcd_variant);
  paint_screen(draw_splash);
  for (int b = 0; b <= 200; b += 10) { board_backlight(b); vTaskDelay(pdMS_TO_TICKS(15)); }
  int64_t splash_until = esp_timer_get_time() + 1200000;

  board_touch_init();

  esp_vfs_littlefs_conf_t fs = {};
  fs.base_path = FS_ROOT;
  fs.partition_label = "storage";
  fs.format_if_mount_failed = true;
  esp_vfs_littlefs_register(&fs);

  usb_link_start();
  hid_queue = xQueueCreate(4, sizeof(void *));
  xTaskCreatePinnedToCore(hid_task, "hid", 4096, NULL, 4, NULL, 1);
  g_usb.usb = true;
  g_usb.buf = (char *)heap_caps_malloc_prefer(LINE_MAX_LEN, 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);
  for (auto &c : g_net) c.buf = (char *)heap_caps_malloc_prefer(LINE_MAX_LEN, 2, MALLOC_CAP_SPIRAM, MALLOC_CAP_DEFAULT);

  xSemaphoreTake(lock, portMAX_DELAY);
  load_deck();
  xSemaphoreGive(lock);
#ifndef BOARD_VIRTUAL  // QEMU has no Wi-Fi radio
  net_start();
#endif
  xTaskCreatePinnedToCore(usb_task, "usb", 8192, NULL, 5, NULL, 0);

  while (esp_timer_get_time() < splash_until) vTaskDelay(pdMS_TO_TICKS(20));

  bool last_host = false;
  int64_t last_info_refresh = 0;
  while (true) {
    xSemaphoreTake(lock, portMAX_DELAY);
    touch_poll();
    bool host = any_host();
    if (host != last_host) {
      last_host = host;
      mark_dirty();
    }
    int64_t now = esp_timer_get_time();
    // the info screen shows live network state
    if ((show_info || !deck_loaded) && now - last_info_refresh > 2000000) {
      last_info_refresh = now;
      mark_dirty();
    }
    if (fill_request >= 0) {
      fill_color = (uint16_t)fill_request;
      fill_request = -1;
      paint_screen(draw_fill);
    } else if (dirty) {
      dirty = false;
#if BOARD_FRAMEBUFFER
      Canvas c = {fb, 0, 0, DISP_W, DISP_H};
      compose(c);
      xSemaphoreGive(lock);
      board_display_draw(0, 0, DISP_W, DISP_H, fb);
      vTaskDelay(pdMS_TO_TICKS(15));
      continue;
#else
      for (int y = dirty_y0 / BAND_H * BAND_H; y < dirty_y1; y += BAND_H) {
        Canvas c = {band, 0, y, DISP_W, DISP_H - y < BAND_H ? DISP_H - y : BAND_H};
        compose(c);
        board_display_draw(0, y, c.w, c.h, band);
      }
#endif
    }
    xSemaphoreGive(lock);
    vTaskDelay(pdMS_TO_TICKS(15));
  }
}
