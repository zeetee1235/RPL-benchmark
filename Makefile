CONTIKI ?= $(abspath ../external/contiki-ng)

CONTIKI_PROJECT = receiver_root sender
BRPL_OF :=
ifneq (,$(findstring BRPL_MODE=1,$(DEFINES)))
BRPL_OF := 1
endif
ifneq ($(BRPL_MODE),)
BRPL_OF := 1
endif
ifneq ($(BRPL_OF),)
PROJECT_SOURCEFILES += brpl-of.c
endif

all: $(CONTIKI_PROJECT)

include $(CONTIKI)/Makefile.include
