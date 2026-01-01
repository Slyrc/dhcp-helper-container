# One-command static musl build, auto-stripped, executable

CC := gcc
STRIP := strip
CHMOD := chmod

CFLAGS := -O2
LDFLAGS := -static

TARGET := dhcp-helper
SRC := dhcp-helper.c

VERSION := $(shell ./get-version 2>/dev/null || echo UNKNOWN)

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) \
		-DVERSION=\"$(VERSION)\" \
		-Wall -W \
		-o $(TARGET) $(SRC) \
		$(LDFLAGS)
	$(STRIP) $(TARGET)
	$(CHMOD) 0555 $(TARGET)

clean:
	rm -f $(TARGET) *.o core *~
