CONTIKI ?= $(abspath ../external/contiki-ng)

CONTIKI_PROJECT = receiver_root sender
PROJECT_SOURCEFILES += brpl-of.c

all: $(CONTIKI_PROJECT)

include $(CONTIKI)/Makefile.include
