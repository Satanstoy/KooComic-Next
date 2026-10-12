CC ?= gcc
CFLAGS ?= -O2 -Wall -Wextra
TARGET ?= host
OUTPUT = build/moire-$(TARGET).so
SOURCES = filter.c vendor/kissfft/kiss_fft.c vendor/kissfft/kiss_fftnd.c

.PHONY: all clean smoke
all: $(OUTPUT)

$(OUTPUT): $(SOURCES) vendor/moire_filter_kissfft.c vendor/kissfft/kiss_fft.h vendor/kissfft/kiss_fftnd.h
	mkdir -p build
	$(CC) $(CFLAGS) -std=c99 -fPIC -shared -fvisibility=hidden -Ivendor/kissfft $(SOURCES) -lm -o $@

clean:
	rm -f build/moire-*.so

build/native-smoke-$(TARGET): ../../spec/native_preprocess_smoke.c
	mkdir -p build
	$(CC) $(CFLAGS) $< -ldl -o $@

smoke: $(OUTPUT) build/native-smoke-$(TARGET)
	./build/native-smoke-$(TARGET) ./$(OUTPUT)
