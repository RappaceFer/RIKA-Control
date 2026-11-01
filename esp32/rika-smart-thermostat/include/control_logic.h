#pragma once
#include <stdint.h>
#include <math.h>

// Independent thermostat decision engine. NO GPIO/relay control in this file.
// Time/day values come from the local clock after successful NTP sync.
struct HeatWindow { uint16_t startMinute; uint16_t endMinute; };
struct DaySchedule { HeatWindow first; HeatWindow second; };

constexpr HeatWindow kDisabledWindow{0, 0};
// C tm_wday: 0=Sunday, 1=Monday, ... 6=Saturday.
// EXAMPLE timetable only. Adapt before real operation.
constexpr DaySchedule kExampleWeek[7] = {
  {{7*60+30, 22*60+30}, kDisabledWindow}, // Sunday
  {{6*60, 9*60}, {17*60, 22*60}},          // Monday
  {{6*60, 9*60}, {17*60, 22*60}},          // Tuesday
  {{6*60, 9*60}, {17*60, 22*60}},          // Wednesday
  {{6*60, 9*60}, {17*60, 22*60}},          // Thursday
  {{6*60, 9*60}, {17*60, 22*60}},          // Friday
  {{7*60+30, 22*60+30}, kDisabledWindow} // Saturday
};
inline bool within(const HeatWindow &w, int minute) {
  return w.startMinute < w.endMinute &&
         minute >= static_cast<int>(w.startMinute) &&
         minute < static_cast<int>(w.endMinute);
}
inline bool allowedByWeek(int weekday, int minute) {
  if (weekday < 0 || weekday > 6 || minute < 0 || minute >= 1440) return false;
  const DaySchedule& d=kExampleWeek[weekday];
  return within(d.first, minute) || within(d.second, minute);
}
enum class DemandState {
  NoTemperature, NoClock, OutsideSchedule, WaitingRestart, HeatRequested, TargetReached
};
inline const char* demandLabel(DemandState s) {
  switch (s) {
    case DemandState::NoTemperature: return "SONDE ABSENTE";
    case DemandState::NoClock: return "HORLOGE INVALIDE";
    case DemandState::OutsideSchedule: return "HORS PLANNING";
    case DemandState::WaitingRestart: return "PAUSE ANTI-CYCLE";
    case DemandState::HeatRequested: return "CHAUFFE DEMANDEE";
    case DemandState::TargetReached: return "CONSIGNE ATTEINTE";
  }
  return "INCONNU";
}

class SmartThermostat {
 public:
  static constexpr float kRestartGapC = 0.8f;
  static constexpr uint32_t kMinimumOffMs = 20UL * 60UL * 1000UL;
  explicit SmartThermostat(float setpointC=22.0f): targetC_(setpointC) {}
  void setTarget(float c) { if (isfinite(c) && c>=14.0f && c<=28.0f) targetC_=c; }
  float target() const { return targetC_; }
  bool heatRequested() const { return heat_; }
  DemandState state() const { return state_; }

  DemandState tick(float roomC, bool hasSensor, bool clockReady,
                   int weekday, int minuteOfDay, uint32_t uptimeMs) {
    if (!hasSensor || !isfinite(roomC) || roomC < -10 || roomC > 50) {
      stop(uptimeMs); state_=DemandState::NoTemperature; return state_;
    }
    if (!clockReady) {
      stop(uptimeMs); state_=DemandState::NoClock; return state_;
    }
    if (!allowedByWeek(weekday, minuteOfDay)) {
      stop(uptimeMs); state_=DemandState::OutsideSchedule; return state_;
    }
    // Stop at target promptly; an ESP32 MUST NOT override the RIKA safety logic.
    if (roomC >= targetC_) {
      stop(uptimeMs); state_=DemandState::TargetReached; return state_;
    }
    if (heat_) { state_=DemandState::HeatRequested; return state_; }
    if (roomC > targetC_ - kRestartGapC) {
      state_=DemandState::TargetReached; return state_;
    }
    if (uptimeMs < kMinimumOffMs ||
        (offRecorded_ && static_cast<uint32_t>(uptimeMs - lastOffMs_) < kMinimumOffMs)) {
      state_=DemandState::WaitingRestart; return state_;
    }
    heat_=true;
    state_=DemandState::HeatRequested;
    return state_;
  }

 private:
  void stop(uint32_t nowMs) {
    if (heat_) { heat_=false; lastOffMs_=nowMs; offRecorded_=true; }
  }
  float targetC_;
  bool heat_=false;
  bool offRecorded_=false;
  uint32_t lastOffMs_=0;
  DemandState state_=DemandState::NoClock;
};
