CONTIKI ?= $(abspath ../external/contiki-ng)

CONTIKI_PROJECT = receiver_root sender
ifneq (,$(findstring BRPL_MODE=1,$(DEFINES)))
PROJECT_SOURCEFILES += brpl-of.c
endif

all: $(CONTIKI_PROJECT)

include $(CONTIKI)/Makefile.include
