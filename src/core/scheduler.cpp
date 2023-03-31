/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "scheduler.hpp"

#include <algorithm>
#include <cassert>
#include <cstdio>
#include <deque>
#include <queue>
#include <vector>

namespace ps2::scheduler {

/* --- Scheduler constants --- */

constexpr i64 MAX_RUN_CYCLES = 64;

/* Scheduler event */
struct Event {
    u64 id;

    int param;
    i64 cyclesUntilEvent;
};

std::deque<Event> events;     // Event queue
std::queue<Event> nextEvents;

std::vector<std::function<void(int)>> registeredFuncs;

i64 cyclesUntilNextEvent;

/* Finds the next event */
void reschedule() {
    auto nextEvent = INT64_MAX;

    for (auto &event : events) {
        if (event.cyclesUntilEvent < nextEvent) nextEvent = event.cyclesUntilEvent;
    }

    cyclesUntilNextEvent = nextEvent;
}

void init() {
    cyclesUntilNextEvent = INT64_MAX;
}

void flush() {
    if (nextEvents.empty()) return reschedule();

    while (!nextEvents.empty()) { events.push_back(nextEvents.front()); nextEvents.pop(); }

    reschedule();
}

/* Registers an event, returns event ID */
u64 registerEvent(std::function<void(int)> func) {
    static u64 idPool;

    registeredFuncs.push_back(func);

    return idPool++;
}

/* Adds a scheduler event */
void addEvent(u64 id, int param, i64 cyclesUntilEvent) {
    assert(cyclesUntilEvent >= 0);

    //std::printf("[Scheduler ] Adding event %llu, cycles until event: %lld\n", id, cyclesUntilEvent);

    nextEvents.emplace(Event{id, param, cyclesUntilEvent});
}

/* Removes all scheduler events of a certain ID */
void removeEvent(u64 id) {
    for (auto event = events.begin(); event != events.end();) {
        if (event->id == id) {
            event = events.erase(event);
        } else {
            event++;
        }
    }
}

void processEvents(i64 elapsedCycles) {
    assert(!events.empty());

    cyclesUntilNextEvent -= elapsedCycles;

    for (auto event = events.begin(); event != events.end();) {
        event->cyclesUntilEvent -= elapsedCycles;

        assert(event->cyclesUntilEvent >= 0);

        if (!event->cyclesUntilEvent) {
            const auto id = event->id;
            const auto param = event->param;

            event = events.erase(event);

            registeredFuncs[id](param);
        } else {
            event++;
        }
    }
}

i64 getRunCycles() {
    return std::min((i64)MAX_RUN_CYCLES, cyclesUntilNextEvent);
}

}
