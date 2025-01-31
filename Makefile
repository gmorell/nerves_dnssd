# Variables to override
#
# CC            C compiler
# CROSSCOMPILE	crosscompiler prefix, if any
# CFLAGS	compiler flags for compiling all C files
# ERL_CFLAGS	additional compiler flags for files using Erlang header files
# ERL_EI_LIBDIR path to libei.a
# LDFLAGS	linker flags for linking all binaries
# ERL_LDFLAGS	additional linker flags for projects referencing Erlang libraries

MDNSRESPONDER_VSN = 878.200.35
# MDNSRESPONDER_URL = https://github.com/apple-oss-distributions/mDNSResponder/archive/refs/tags/mDNSResponder-$(MDNSRESPONDER_VSN).tar.gz
# MDNSRESPONDER_URL = https://codeload.github.com/apple-oss-distributions/mDNSResponder/tar.gz/refs/tags/mDNSResponder-$(MDNSRESPONDER_VSN)
MDNSRESPONDER_URL=  https://codeload.github.com/apple-oss-distributions/mDNSResponder/tar.gz/refs/tags/mDNSResponder-878.200.35
# MDNSRESPONDER_URL = https://opensource.apple.com/tarballs/mDNSResponder/mDNSResponder-$(MDNSRESPONDER_VSN).tar.gz

UNAME = $(shell uname -s)

ifneq ($(NERVES_SYSTEM),)
TARGET_OS = linux
TARGET_OPTS = HAVE_IPV6=0
else ifeq ($(UNAME),Linux)
TARGET_OS ?= linux
TARGET_OPTS =
else ifeq ($(UNAME),Darwin)
TARGET_OS ?= x
TARGET_OPTS =
else
$(error No configuration for system $(UNAME))
endif

CC ?= $(CROSSCOMPILER)gcc
STRIP ?= $(CROSSCOMPILER)strip -S

ifeq ($(TARGET_OS),x)
LD = $(CC) -bundle -flat_namespace -undefined suppress
else
# Assume Linux/Nerves
LD = $(CC) -shared
endif

CFLAGS += -fPIC
LDFLAGS +=

BUILD_DIR ?= _build/make
SRC_ROOT_DIR = $(BUILD_DIR)/mDNSResponder-$(MDNSRESPONDER_VSN)
SRC_ROOT_DIR2 = $(BUILD_DIR)/mDNSResponder-mDNSResponder-$(MDNSRESPONDER_VSN)
BUILD_DRV_DIR = $(BUILD_DIR)/dnssd_drv
BUILD_MDNSD_DIR = $(BUILD_DIR)/mdnsd
INSTALL_DIR ?= .

# Set Erlang-specific compile and linker flags
ERL_EI_INCLUDE_DIR ?= $(ROOTDIR)/usr/include
ERL_EI_LIBDIR ?= $(ROOTDIR)/usr/lib
ERL_CFLAGS ?= -I$(ERL_EI_INCLUDE_DIR)
ERL_LDFLAGS ?= -L$(ERL_EI_LIBDIR) -lei

###
# from  mDNSResponder-$(MDNSRESPONDER_VSN)/mDNSPosix/Makefile:
CLIENTLIBOBJS = $(BUILD_DRV_DIR)/dnssd_clientlib.c.so.o $(BUILD_DRV_DIR)/dnssd_clientstub.c.so.o $(BUILD_DRV_DIR)/dnssd_ipc.c.so.o

.PHONY: all clean daemon lib driver

all: daemon lib driver

daemon: $(INSTALL_DIR)/priv/mdnsd
	@echo "===> $^ installed"

lib: $(BUILD_DRV_DIR)/libdns_sd.so.1
	@echo "===> $^ compiled"

driver: lib $(INSTALL_DIR)/priv/dnssd_drv.so
	@echo "===> $^ installed"

deps/mDNSResponder-$(MDNSRESPONDER_VSN).tar.gz:
	curl $(MDNSRESPONDER_URL) -o deps/mDNSResponder-$(MDNSRESPONDER_VSN).tar.gz --create-dirs

$(SRC_ROOT_DIR): deps/mDNSResponder-$(MDNSRESPONDER_VSN).tar.gz c_src/mDNSResponder.patch
	mkdir -p $(BUILD_DIR)
	tar xzf deps/mDNSResponder-$(MDNSRESPONDER_VSN).tar.gz -C $(BUILD_DIR)
	patch -p 1 -d $(SRC_ROOT_DIR2) < c_src/mDNSResponder.patch

##
# The daemon
#

$(INSTALL_DIR)/priv/mdnsd: $(SRC_ROOT_DIR2)
	make -C $(SRC_ROOT_DIR2)/mDNSPosix Daemon os=$(TARGET_OS) CC=$(CC) STRIP="$(STRIP)" BUILDDIR=$(INSTALL_DIR)/priv $(TARGET_OPTS) 2>&1

##
# The port driver
#

$(BUILD_DRV_DIR)/libdns_sd.so.1: $(SRC_ROOT_DIR2)
	make -C $(SRC_ROOT_DIR2)/mDNSPosix libdns_sd os=$(TARGET_OS) CC=$(CC) STRIP="$(STRIP)" BUILDDIR=$(BUILD_DRV_DIR) OBJDIR=$(BUILD_DRV_DIR) $(TARGET_OPTS) 2>&1

$(BUILD_DRV_DIR)/dnssd.o: c_src/dnssd.c
	$(CC) -c $(ERL_CFLAGS) $(CFLAGS) -I $(SRC_ROOT_DIR2)/mDNSShared -o $@ $<

$(INSTALL_DIR)/priv/dnssd_drv.so: $(BUILD_DRV_DIR)/dnssd.o $(CLIENTLIBOBJS)
	mkdir -p $(INSTALL_DIR)/priv
	$(LD) $+ $(ERL_LDFLAGS) $(LDFLAGS) -o $@

clean:
	rm -rf $(SRC_ROOT_DIR2) $(BUILD_DRV_DIR) $(BUILD_MDNSD_DIR)
