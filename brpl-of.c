/*
 * brpl-of.c
 * - BRPL-inspired objective function for RPL Lite
 * - Adds a queue occupancy penalty to path cost to emulate backpressure
 */

#include "net/routing/rpl-lite/rpl.h"
#include "net/link-stats.h"
#include "net/queuebuf.h"

#include "sys/log.h"
#define LOG_MODULE "BRPL"
#define LOG_LEVEL LOG_LEVEL_RPL

#ifndef BRPL_QUEUE_WEIGHT
#define BRPL_QUEUE_WEIGHT (LINK_STATS_ETX_DIVISOR / 4)
#endif

/*---------------------------------------------------------------------------*/
static void
reset(void)
{
  LOG_INFO("reset BRPL-OF\n");
}
/*---------------------------------------------------------------------------*/
static uint16_t
nbr_link_metric(rpl_nbr_t *nbr)
{
  const struct link_stats *stats = rpl_neighbor_get_link_stats(nbr);
  if(stats == NULL) {
    LOG_WARN("link stats missing for neighbor %p\n", (void *)nbr);
    return 0xffff;
  }
  if(stats->etx == 0) {
    LOG_WARN("link stats etx=0 for neighbor %p\n", (void *)nbr);
  }
  return stats->etx;
}
/*---------------------------------------------------------------------------*/
static uint16_t
link_metric_to_rank(uint16_t etx)
{
  return etx;
}
/*---------------------------------------------------------------------------*/
static uint16_t
queue_penalty(void)
{
  size_t free = queuebuf_numfree();
  size_t used = QUEUEBUF_NUM > free ? (QUEUEBUF_NUM - free) : 0;
  uint32_t penalty = (uint32_t)used * (uint32_t)BRPL_QUEUE_WEIGHT;
  return (uint16_t)MIN(penalty, 0xffff);
}
/*---------------------------------------------------------------------------*/
static uint16_t
nbr_path_cost(rpl_nbr_t *nbr)
{
  uint16_t base;

  if(nbr == NULL) {
    return 0xffff;
  }

#if RPL_WITH_MC
  /* Handle the different MC types */
  switch(curr_instance.mc.type) {
    case RPL_DAG_MC_ETX:
      base = nbr->mc.obj.etx;
      break;
    case RPL_DAG_MC_ENERGY:
      base = nbr->mc.obj.energy.energy_est << 8;
      break;
    default:
      base = nbr->rank;
      break;
  }
#else /* RPL_WITH_MC */
  base = nbr->rank;
#endif /* RPL_WITH_MC */

  /* BRPL-style penalty uses local queue occupancy to bias rank. */
  return MIN((uint32_t)base + link_metric_to_rank(nbr_link_metric(nbr)) + queue_penalty(), 0xffff);
}
/*---------------------------------------------------------------------------*/
static rpl_rank_t
rank_via_nbr(rpl_nbr_t *nbr)
{
  uint16_t min_hoprankinc;
  uint16_t path_cost;

  if(nbr == NULL) {
    return RPL_INFINITE_RANK;
  }

  min_hoprankinc = curr_instance.min_hoprankinc;
  path_cost = nbr_path_cost(nbr);

  /* Rank lower-bound: nbr rank + min_hoprankinc */
  return MAX(MIN((uint32_t)nbr->rank + min_hoprankinc, RPL_INFINITE_RANK), path_cost);
}
/*---------------------------------------------------------------------------*/
static int
nbr_has_usable_link(rpl_nbr_t *nbr)
{
  uint16_t link_metric = nbr_link_metric(nbr);
  return link_metric <= 4096;
}
/*---------------------------------------------------------------------------*/
static int
nbr_is_acceptable_parent(rpl_nbr_t *nbr)
{
  uint16_t path_cost = nbr_path_cost(nbr);
  int usable = nbr_has_usable_link(nbr);
  int ok = usable && path_cost <= 60000;
  if(!ok) {
    LOG_INFO("reject parent %p: etx=%u path_cost=%u\n",
             (void *)nbr, nbr_link_metric(nbr), path_cost);
  }
  return ok;
}
/*---------------------------------------------------------------------------*/
static int
within_hysteresis(rpl_nbr_t *nbr)
{
  uint16_t path_cost = nbr_path_cost(nbr);
  uint16_t parent_path_cost = nbr_path_cost(curr_instance.dag.preferred_parent);

  int within_rank_hysteresis = path_cost + 192 > parent_path_cost;
  int within_time_hysteresis = nbr->better_parent_since == 0
    || (clock_time() - nbr->better_parent_since) <= (10 * 60 * CLOCK_SECOND);

  return within_rank_hysteresis && within_time_hysteresis;
}
/*---------------------------------------------------------------------------*/
static rpl_nbr_t *
best_parent(rpl_nbr_t *nbr1, rpl_nbr_t *nbr2)
{
  int nbr1_is_acceptable;
  int nbr2_is_acceptable;

  nbr1_is_acceptable = nbr1 != NULL && nbr_is_acceptable_parent(nbr1);
  nbr2_is_acceptable = nbr2 != NULL && nbr_is_acceptable_parent(nbr2);

  if(!nbr1_is_acceptable) {
    return nbr2_is_acceptable ? nbr2 : NULL;
  }
  if(!nbr2_is_acceptable) {
    return nbr1_is_acceptable ? nbr1 : NULL;
  }

  if(nbr1 == curr_instance.dag.preferred_parent && within_hysteresis(nbr2)) {
    return nbr1;
  }
  if(nbr2 == curr_instance.dag.preferred_parent && within_hysteresis(nbr1)) {
    return nbr2;
  }

  return nbr_path_cost(nbr1) < nbr_path_cost(nbr2) ? nbr1 : nbr2;
}
/*---------------------------------------------------------------------------*/
#if !RPL_WITH_MC
static void
update_metric_container(void)
{
  curr_instance.mc.type = RPL_DAG_MC_NONE;
}
#else /* RPL_WITH_MC */
static void
update_metric_container(void)
{
  uint16_t path_cost;
  uint8_t type;

  if(!curr_instance.used) {
    LOG_WARN("cannot update the metric container when not joined\n");
    return;
  }

  if(curr_instance.dag.rank == ROOT_RANK) {
    curr_instance.mc.type = RPL_DAG_MC;
    curr_instance.mc.flags = 0;
    curr_instance.mc.aggr = RPL_DAG_MC_AGGR_ADDITIVE;
    curr_instance.mc.prec = 0;
    path_cost = curr_instance.dag.rank;
  } else {
    path_cost = nbr_path_cost(curr_instance.dag.preferred_parent);
  }

  switch(curr_instance.mc.type) {
    case RPL_DAG_MC_NONE:
      break;
    case RPL_DAG_MC_ETX:
      curr_instance.mc.length = sizeof(curr_instance.mc.obj.etx);
      curr_instance.mc.obj.etx = path_cost;
      break;
    case RPL_DAG_MC_ENERGY:
      curr_instance.mc.length = sizeof(curr_instance.mc.obj.energy);
      if(curr_instance.dag.rank == ROOT_RANK) {
        type = RPL_DAG_MC_ENERGY_TYPE_MAINS;
      } else {
        type = RPL_DAG_MC_ENERGY_TYPE_BATTERY;
      }
      curr_instance.mc.obj.energy.flags = type << RPL_DAG_MC_ENERGY_TYPE;
      curr_instance.mc.obj.energy.energy_est = path_cost >> 8;
      break;
    default:
      LOG_WARN("BRPL-OF, non-supported MC %u\n", curr_instance.mc.type);
      break;
  }
}
#endif /* RPL_WITH_MC */
/*---------------------------------------------------------------------------*/
rpl_of_t rpl_brpl = {
  reset,
  nbr_link_metric,
  nbr_has_usable_link,
  nbr_is_acceptable_parent,
  nbr_path_cost,
  rank_via_nbr,
  best_parent,
  update_metric_container,
  RPL_OCP_MRHOF
};
