#include <cassert>
#include <cmath>
#include <iostream>
#include "control_logic.h"

int main() {
  static_assert(kExampleWeek[1].first.startMinute==360, "Monday morning");
  assert(allowedByWeek(1,360));
  assert(!allowedByWeek(1,540));
  assert(allowedByWeek(0,8*60));
  assert(!allowedByWeek(7,300));
  SmartThermostat ctl(22.0f);
  // Missing sensor and clock must never request heat.
  assert(ctl.tick(NAN,false,true,1,400,3000000)==DemandState::NoTemperature);
  assert(ctl.tick(19.0f,true,false,1,400,3000000)==DemandState::NoClock);
  assert(ctl.tick(19.0f,true,true,1,400,100000)==DemandState::WaitingRestart);
  assert(ctl.tick(19.0f,true,true,1,400,2000000)==DemandState::HeatRequested);
  assert(ctl.heatRequested());
  // Setpoint triggers stop immediately, never forces heat on.
  assert(ctl.tick(22.0f,true,true,1,400,2000100)==DemandState::TargetReached);
  assert(!ctl.heatRequested());
  assert(ctl.tick(20.0f,true,true,1,400,2000200)==DemandState::WaitingRestart);
  assert(ctl.tick(20.0f,true,true,1,400,3200101)==DemandState::HeatRequested);
  assert(ctl.tick(20.0f,true,true,1,1000,3201000)==DemandState::OutsideSchedule);
  assert(!ctl.heatRequested());
  // Target adjustments bounded; infinite not accepted.
  ctl.setTarget(30); assert(fabs(ctl.target()-22)<0.01f);
  ctl.setTarget(NAN); assert(fabs(ctl.target()-22)<0.01f);
  std::cout << "12 checks passed (dry-run thermostat)\n";
}
