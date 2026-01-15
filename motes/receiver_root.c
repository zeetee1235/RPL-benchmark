/*
 * receiver_root.c
 * - RPL root + UDP receiver/logger for Contiki-NG (Cooja)
 *
 * CSV output:
 * CSV,tag,src_ip,src_port,seq,t_send,t_recv,delay_ticks,len,gap
 *
 * Sensor payload expected: "seq=<n> t=<clock>"
 */

#include "contiki.h"
#include "sys/log.h"

#include "net/ipv6/uip.h"
#include "net/ipv6/uiplib.h"
#include "net/ipv6/uip-ds6.h"
#include "net/routing/routing.h"
#include "net/ipv6/simple-udp.h"
#include "net/ipv6/uip-nd6.h"

#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define LOG_MODULE "RECVROOT"
#define LOG_LEVEL LOG_LEVEL_INFO

#define UDP_PORT 8765
#define SYNC_PORT 8766
#define SYNC_INTERVAL_SECONDS 2
#define SYNC_INTERVAL (SYNC_INTERVAL_SECONDS * CLOCK_SECOND)
#define MAX_SENDERS 16

static struct simple_udp_connection udp_conn;
static struct simple_udp_connection sync_conn;
static struct etimer sync_timer;
static uip_ipaddr_t sync_addr;

typedef struct {
  uip_ipaddr_t ip;
  uint32_t last_seq;
  uint8_t used;
} sender_state_t;

static sender_state_t senders[MAX_SENDERS];

static void
set_root_address_and_prefix(void)
{
  uip_ipaddr_t ipaddr;
  uip_ipaddr_t prefix;

  /* Root global address: aaaa::1 */
  uip_ip6addr(&ipaddr, 0xaaaa,0,0,0,0,0,0,1);
  uip_ds6_addr_add(&ipaddr, 0, ADDR_MANUAL);

  /* Prefix: aaaa::/64 */
  uip_ip6addr(&prefix, 0xaaaa,0,0,0,0,0,0,0);
  uip_ds6_prefix_add(&prefix, 64,
                     1, /* advertise */
                     UIP_ND6_RA_FLAG_ONLINK | UIP_ND6_RA_FLAG_AUTONOMOUS,
                     UIP_ND6_INFINITE_LIFETIME,
                     UIP_ND6_INFINITE_LIFETIME);

  LOG_INFO("root ip = ");
  LOG_INFO_6ADDR(&ipaddr);
  LOG_INFO_("\n");
}

static int
parse_payload(const uint8_t *data, uint16_t len, uint32_t *seq_out, uint32_t *t_out)
{
  char buf[96];
  if(len >= sizeof(buf)) len = sizeof(buf) - 1;
  memcpy(buf, data, len);
  buf[len] = '\0';

  unsigned long seq = 0, t = 0;
  int matched = sscanf(buf, "seq=%lu t=%lu", &seq, &t);
  if(matched == 2) {
    *seq_out = (uint32_t)seq;
    *t_out   = (uint32_t)t;
    return 1;
  }
  return 0;
}

static sender_state_t *
get_sender_state(const uip_ipaddr_t *ip)
{
  for(int i = 0; i < MAX_SENDERS; i++) {
    if(senders[i].used && uip_ipaddr_cmp(&senders[i].ip, ip)) {
      return &senders[i];
    }
  }
  for(int i = 0; i < MAX_SENDERS; i++) {
    if(!senders[i].used) {
      senders[i].used = 1;
      uip_ipaddr_copy(&senders[i].ip, ip);
      senders[i].last_seq = 0;
      return &senders[i];
    }
  }
  return NULL;
}

static void
udp_rx_callback(struct simple_udp_connection *c,
                const uip_ipaddr_t *sender_addr,
                uint16_t sender_port,
                const uip_ipaddr_t *receiver_addr,
                uint16_t receiver_port,
                const uint8_t *data,
                uint16_t datalen)
{
  (void)c; (void)receiver_addr; (void)receiver_port;

  uint32_t seq = 0, t_send = 0;
  uint32_t t_recv = (uint32_t)clock_time();

  int ok = parse_payload(data, datalen, &seq, &t_send);
  uint32_t delay = ok ? (t_recv - t_send) : 0;

  uint32_t gap = 0;
  sender_state_t *st = get_sender_state(sender_addr);
  if(st != NULL && ok) {
    if(seq > st->last_seq + 1) {
      gap = seq - (st->last_seq + 1);
    }
    st->last_seq = seq;
  }

  static uint8_t printed_header = 0;
  if(!printed_header) {
    printed_header = 1;
    printf("CSV,tag,src_ip,src_port,seq,t_send,t_recv,delay_ticks,len,gap\n");
  }

  printf("CSV,RX,");
  uiplib_ipaddr_print(sender_addr);
  printf(",%u,", sender_port);

  if(ok) {
    printf("%lu,%lu,%lu,%lu,%u,%lu\n",
           (unsigned long)seq,
           (unsigned long)t_send,
           (unsigned long)t_recv,
           (unsigned long)delay,
           (unsigned)datalen,
           (unsigned long)gap);
  } else {
    printf("NA,NA,%lu,0,%u,0\n",
           (unsigned long)t_recv,
           (unsigned)datalen);
  }
}

PROCESS(receiver_root_process, "Receiver Root (RPL root + UDP logger)");
AUTOSTART_PROCESSES(&receiver_root_process);

PROCESS_THREAD(receiver_root_process, ev, data)
{
  (void)ev; (void)data;

  PROCESS_BEGIN();

  LOG_INFO("boot\n");

  /* Establish RPL root and prefix so sensors can auto-configure. */
  set_root_address_and_prefix();
  if(!NETSTACK_ROUTING.root_start()) {
    LOG_ERR("root_start() failed\n");
  } else {
    LOG_INFO("root_start() ok\n");
  }

  /* UDP receiver for sensor traffic. */
  simple_udp_register(&udp_conn, UDP_PORT, NULL, UDP_PORT, udp_rx_callback);
  LOG_INFO("UDP receiver listening on %u\n", UDP_PORT);

  /* Periodic time sync beacon for senders. */
  uip_create_linklocal_allnodes_mcast(&sync_addr);
  simple_udp_register(&sync_conn, SYNC_PORT, NULL, SYNC_PORT, NULL);
  etimer_set(&sync_timer, SYNC_INTERVAL);

  while(1) {
    PROCESS_WAIT_EVENT();
    if(etimer_expired(&sync_timer)) {
      char buf[32];
      uint32_t t_root = (uint32_t)clock_time();
      snprintf(buf, sizeof(buf), "SYNC t=%lu", (unsigned long)t_root);
      simple_udp_sendto(&sync_conn, buf, strlen(buf), &sync_addr);
      etimer_reset(&sync_timer);
    }
  }

  PROCESS_END();
}
