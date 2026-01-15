/*
 * sender.c
 * - UDP sensor sender for Contiki-NG (Cooja)
 * - Sends seq + local clock every 10 seconds
 */

#include "contiki.h"
#include "sys/log.h"

#include "net/ipv6/uip.h"
#include "net/ipv6/uiplib.h"
#include "net/ipv6/uip-ds6-route.h"
#include "net/routing/routing.h"
#include "net/ipv6/simple-udp.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define LOG_MODULE "SENDER"
#define LOG_LEVEL LOG_LEVEL_INFO

#define UDP_PORT 8765
#define SYNC_PORT 8766
#ifndef SEND_INTERVAL_SECONDS
#define SEND_INTERVAL_SECONDS 10
#endif
#define SEND_INTERVAL (SEND_INTERVAL_SECONDS * CLOCK_SECOND)
#define SYNC_WINDOW 5

static struct simple_udp_connection udp_conn;
static struct simple_udp_connection sync_conn;
static uip_ipaddr_t root_ipaddr;
static int32_t offset_samples[SYNC_WINDOW];
static int64_t offset_sum;
static uint8_t offset_count;
static uint8_t offset_index;
static int32_t offset_avg;
static uint8_t has_sync;

static int
parse_sync(const uint8_t *data, uint16_t len, uint32_t *t_root_out)
{
  char buf[48];
  if(len >= sizeof(buf)) len = sizeof(buf) - 1;
  memcpy(buf, data, len);
  buf[len] = '\0';

  unsigned long t_root = 0;
  int matched = sscanf(buf, "SYNC t=%lu", &t_root);
  if(matched == 1) {
    *t_root_out = (uint32_t)t_root;
    return 1;
  }
  return 0;
}

static void
sync_rx_callback(struct simple_udp_connection *c,
                 const uip_ipaddr_t *sender_addr,
                 uint16_t sender_port,
                 const uip_ipaddr_t *receiver_addr,
                 uint16_t receiver_port,
                 const uint8_t *data,
                 uint16_t datalen)
{
  (void)c; (void)sender_addr; (void)sender_port; (void)receiver_addr; (void)receiver_port;

  uint32_t t_root = 0;
  if(!parse_sync(data, datalen, &t_root)) {
    return;
  }

  uint32_t t_local = (uint32_t)clock_time();
  int32_t offset = (int32_t)(t_root - t_local);
  LOG_INFO("sync rx: t_root=%lu t_local=%lu offset=%ld\n",
           (unsigned long)t_root, (unsigned long)t_local, (long)offset);

  if(offset_count < SYNC_WINDOW) {
    offset_sum += offset;
    offset_samples[offset_index] = offset;
    offset_index = (offset_index + 1) % SYNC_WINDOW;
    offset_count++;
  } else {
    offset_sum -= offset_samples[offset_index];
    offset_sum += offset;
    offset_samples[offset_index] = offset;
    offset_index = (offset_index + 1) % SYNC_WINDOW;
  }

  offset_avg = (int32_t)(offset_sum / (int64_t)offset_count);
  has_sync = 1;
}

PROCESS(sender_process, "UDP sender (sensor)");
AUTOSTART_PROCESSES(&sender_process);

PROCESS_THREAD(sender_process, ev, data)
{
  static struct etimer periodic_timer;
  static uint32_t seq;
  static uint8_t last_reachable;
  char buf[64];

  (void)ev; (void)data;

  PROCESS_BEGIN();

  /* Root is aaaa::1 as configured by receiver_root.c. */
  uip_ip6addr(&root_ipaddr, 0xaaaa,0,0,0,0,0,0,1);

  simple_udp_register(&udp_conn, UDP_PORT, NULL, UDP_PORT, NULL);
  simple_udp_register(&sync_conn, SYNC_PORT, NULL, SYNC_PORT, sync_rx_callback);
  etimer_set(&periodic_timer, SEND_INTERVAL);
  last_reachable = 0;

  while(1) {
    PROCESS_WAIT_EVENT_UNTIL(etimer_expired(&periodic_timer));
    etimer_reset(&periodic_timer);

    uint8_t reachable = NETSTACK_ROUTING.node_is_reachable();
    uint8_t joined = NETSTACK_ROUTING.node_has_joined();
    if(reachable != last_reachable) {
      LOG_INFO("reachable changed: %u -> %u\n",
               (unsigned)last_reachable, (unsigned)reachable);
      last_reachable = reachable;
    }
    if(LOG_INFO_ENABLED) {
      const uip_ipaddr_t *defrt = uip_ds6_defrt_choose();
      int routes = uip_ds6_route_num_routes();
      LOG_INFO("routing state: joined=%d reachable=%u routes=%d defrt=%s",
               joined, (unsigned)reachable, routes, defrt ? "yes" : "no");
      if(defrt) {
        LOG_INFO_(" defrt=");
        LOG_INFO_6ADDR(defrt);
      }
      LOG_INFO_("\n");
    }

    if(!has_sync) {
      LOG_INFO("waiting for sync\n");
      continue;
    }

    if(joined) {
      uint32_t t_send_local = (uint32_t)clock_time();
      int64_t t_send_root64 = (int64_t)t_send_local + (int64_t)offset_avg;
      uint32_t t_send_root = t_send_root64 < 0 ? 0 : (uint32_t)t_send_root64;
      seq++;
      snprintf(buf, sizeof(buf), "seq=%lu t=%lu",
               (unsigned long)seq, (unsigned long)t_send_root);
      simple_udp_sendto(&udp_conn, buf, strlen(buf), &root_ipaddr);
      LOG_INFO("TX seq=%lu t=%lu\n", (unsigned long)seq, (unsigned long)t_send_root);
    } else {
      LOG_INFO("not joined yet\n");
    }
  }

  PROCESS_END();
}
