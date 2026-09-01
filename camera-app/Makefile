CXX ?= g++
CXXFLAGS ?= -O2 -g
CXXFLAGS += -std=c++20 -Wall -Wextra -Wpedantic
PKGS := gstreamer-app-1.0 gstreamer-video-1.0 gtk4

nabu-autofocus: nabu-autofocus.cpp
	$(CXX) $(CXXFLAGS) $(shell pkg-config --cflags $(PKGS)) -o $@ $< \
		$(shell pkg-config --libs $(PKGS))

.PHONY: clean
clean:
	$(RM) nabu-autofocus
