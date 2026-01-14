/*
 * sender.c
 * - UDP sensor sender for Contiki-NG (Cooja)
 * - Sends seq + local clock every 10 seconds
 */

#include "contiki.h"
#include "sys/log.h"

#include "net/ipv6/uip.h"
#include "net/ipv6/uiplib.h"
#include "net/routing/routing.h"
#include "net/ipv6/simple-udp.h"

#include <stdint.h>
#include <stdio.h>

#define LOG_MODULE "SENDER"
#define LOG_LEVEL LOG_LEVEL_INFO

#define UDP_PORT 8765
#ifndef SEND_INTERVAL_SECONDS
#define SEND_INTERVAL_SECONDS 10
#endif
#define SEND_INTERVAL (SEND_INTERVAL_SECONDS * CLOCK_SECOND)

static struct simple_udp_connection udp_conn;
static uip_ipaddr_t root_ipaddr;

PROCESS(sender_process, "UDP sender (sensor)");
AUTOSTART_PROCESSES(&sender_process);

PROCESS_THREAD(sender_process, ev, data)
{
  static struct etimer periodic_timer;
  static uint32_t seq;
  char buf[64];

  (void)ev; (void)data;

  PROCESS_BEGIN();

  /* Root is aaaa::1 as configured by receiver_root.c. */
  uip_ip6addr(&root_ipaddr, 0xaaaa,0,0,0,0,0,0,1);

  simple_udp_register(&udp_conn, UDP_PORT, NULL, UDP_PORT, NULL);
  etimer_set(&periodic_timer, SEND_INTERVAL);

  while(1) {
    PROCESS_WAIT_EVENT_UNTIL(etimer_expired(&periodic_timer));
    etimer_reset(&periodic_timer);

    if(NETSTACK_ROUTING.node_is_reachable()) {
      uint32_t t_send = (uint32_t)clock_time();
      seq++;
      snprintf(buf, sizeof(buf), "seq=%lu t=%lu",
               (unsigned long)seq, (unsigned long)t_send);
      simple_udp_sendto(&udp_conn, buf, strlen(buf), &root_ipaddr);
      LOG_INFO("TX seq=%lu t=%lu\n", (unsigned long)seq, (unsigned long)t_send);
    } else {
      LOG_INFO("not reachable yet\n");
    }
  }

  PROCESS_END();
}
