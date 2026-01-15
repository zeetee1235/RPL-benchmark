#ifndef PROJECT_CONF_H_
#define PROJECT_CONF_H_

/* Forward declaration for custom BRPL objective function. */
typedef struct rpl_of rpl_of_t;
extern rpl_of_t rpl_brpl;

#ifdef BRPL_MODE
/* Use BRPL-inspired objective function when BRPL_MODE is enabled. */
#define RPL_CONF_SUPPORTED_OFS {&rpl_brpl}
#define RPL_CONF_OF_OCP RPL_OCP_MRHOF
/* Avoid blocking on DAO-ACK in BRPL experiments; mark reachable on DAO send. */
#define RPL_CONF_WITH_DAO_ACK 0
#endif

#ifndef SEND_INTERVAL_SECONDS
#define SEND_INTERVAL_SECONDS 10
#endif

#ifndef WARMUP_SECONDS
#define WARMUP_SECONDS 60
#endif

/* Keep logs readable in Cooja for experiment parsing. */
#define LOG_LEVEL_APP LOG_LEVEL_INFO
#define LOG_CONF_LEVEL_RPL LOG_LEVEL_INFO
#define LOG_CONF_LEVEL_IPV6 LOG_LEVEL_WARN

#endif /* PROJECT_CONF_H_ */
