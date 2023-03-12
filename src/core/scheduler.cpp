/*
 * moestation is a WIP PlayStation 2 emulator.
 * Copyright (C) 2022-2023  Lady Starbreeze (Michelle-Marie Schiller)
 */

#include "scheduler.hpp"

#include <cassert>
#include <cstdio>
#include <deque>
#include <vector>

namespace ps2::scheduler {

/* Scheduler event */
struct Event {
    u64 id;

    int param;
    i64 cyclesUntilEvent;
};

std::deque<Event> events; // Event queue

std::vector<std::function<void(int, i64)>> registeredFuncs;

i64 cycleCount, cyclesUntilNextEvent;

/* Finds the next event */
void reschedule() {
    auto nextEvent = INT64_MAX;

    for (auto &event : events) {
        if (event.cyclesUntilEvent < nextEvent) nextEvent = event.cyclesUntilEvent;
    }

    cyclesUntilNextEvent = nextEvent;
}

void init() {
    cycleCount = cyclesUntilNextEvent = 0;
}

/* Registers an event, returns event ID */
u64 registerEvent(std::function<void(int, i64)> func) {
    static u64 idPool;

    registeredFuncs.push_back(func);

    return idPool++;
}

/* Adds a scheduler event */
void addEvent(u64 id, int param, i64 cyclesUntilEvent, bool doReschedule) {
    assert(cyclesUntilEvent >= 0);

    //std::printf("[Scheduler ] Adding event %llu, cycles until event: %lld\n", id, cyclesUntilEvent);

    events.push_front(Event{id, param, cyclesUntilEvent});

    if (doReschedule) reschedule();
}

void processEvents(i64 elapsedCycles) {
    assert(!events.empty());

    cycleCount += elapsedCycles;

    if (cycleCount < cyclesUntilNextEvent) return;

    for (auto event = events.begin(); event != events.end();) {
        event->cyclesUntilEvent -= cycleCount;

        if (event->cyclesUntilEvent <= 0) {
            const auto id = event->id;
            const auto param = event->param;
            const auto cyclesUntilEvent = event->cyclesUntilEvent;

            event = events.erase(event);

            registeredFuncs[id](param, cyclesUntilEvent);
        } else {
            event++;
        }
    }

    cycleCount -= cyclesUntilNextEvent;

    reschedule();
}

}
