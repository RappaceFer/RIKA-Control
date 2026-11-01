#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WebServer.h>
#include <time.h>
#include <Arduino_GFX_Library.h>
#include "control_logic.h"

#if __has_include("network_secrets.h")
#include "network_secrets.h"
#else
#define RIKA_WIFI_SSID ""
#define RIKA_WIFI_PASSWORD ""
#endif

// ONLY for the ORIGINAL LilyGO T-Display-S3 1.9" ST7789 170x320 PAR8.
// Do not use this on AMOLED / Touch / other NerdMiner display variants.
static constexpr uint8_t PIN_LCD_POWER=15, PIN_LCD_BL=38;
static constexpr uint8_t PIN_BUTTON_MINUS=0, PIN_BUTTON_PLUS=14;
static constexpr uint8_t PIN_I2C_SDA=18, PIN_I2C_SCL=17;
static constexpr uint8_t SHT31_ADDR=0x44;

Arduino_DataBus* bus=new Arduino_ESP32PAR8Q(
  7, 6, 8, 9, 39, 40, 41, 42, 45, 46, 47, 48);
Arduino_GFX* gfx=new Arduino_ST7789(bus, 5, 0, true, 170, 320, 35, 0, 35, 0);
WebServer http(80);
Preferences prefs;
SmartThermostat regulator(22.0f);

float roomTemperature=NAN, humidityPercent=NAN;
uint32_t lastValidSensorMs=0, lastSensorReadMs=0, lastDrawMs=0, lastButtonChangeMs=0;
bool firstSensorReading=false, wifiConfigured=false, webStarted=false;
uint32_t lastConnectAttemptMs=0;
bool buttonMinusPrev=false, buttonPlusPrev=false;
uint32_t lastButtonActionMs=0;
bool configurationDirty=false;

uint16_t orange, white, gray, green, red, dark, darker;

static uint8_t crc8(const uint8_t* bytes, uint8_t n) {
  uint8_t crc=0xFF;
  for (uint8_t i=0; i<n; ++i) {
    crc ^= bytes[i];
    for (uint8_t b=0; b<8; ++b) crc=(crc & 0x80) ? (crc << 1) ^ 0x31 : (crc << 1);
  }
  return crc;
}
bool readSht31(float& temp, float& humidity) {
  Wire.beginTransmission(SHT31_ADDR);
  Wire.write(0x2C);
  Wire.write(0x06); // single shot, high repeatability, clock stretching
  if (Wire.endTransmission()!=0) return false;
  delay(22);
  if (Wire.requestFrom(static_cast<int>(SHT31_ADDR), 6) != 6) return false;
  uint8_t b[6];
  for (auto& v : b) v=Wire.read();
  if (crc8(b, 2)!=b[2] || crc8(&b[3], 2)!=b[5]) return false;
  const uint16_t t=(static_cast<uint16_t>(b[0])<<8)|b[1];
  const uint16_t h=(static_cast<uint16_t>(b[3])<<8)|b[4];
  temp=-45.0f+175.0f*(static_cast<float>(t)/65535.0f);
  humidity=100.0f*(static_cast<float>(h)/65535.0f);
  return isfinite(temp) && temp>=-10 && temp<=50 && humidity>=0 && humidity<=100;
}
bool sensorAvailable(uint32_t now) {
  return firstSensorReading && static_cast<uint32_t>(now-lastValidSensorMs)<15000U;
}
bool getLocalClock(struct tm& now) {
  if (!getLocalTime(&now, 10)) return false;
  return (now.tm_year+1900)>=2025 && now.tm_wday>=0 && now.tm_wday<7;
}
void displayUi(bool sensorOk, bool timeOk, const struct tm& localTime) {
  gfx->fillScreen(darker);
  gfx->fillRoundRect(9, 8, 302, 154, 14, dark);
  gfx->setTextSize(2); gfx->setTextColor(orange);
  gfx->setCursor(18, 16); gfx->print("RIKA SMART");
  gfx->setTextSize(1); gfx->setTextColor(gray);
  gfx->setCursor(239, 19); gfx->print("V0.1");
  gfx->drawFastHLine(19, 38, 280, gray);
  gfx->setTextColor(white); gfx->setTextSize(2);
  gfx->setCursor(18, 51);
  if(sensorOk) gfx->print(String(roomTemperature, 1)+" C");
  else gfx->print("--.- C");
  gfx->setTextColor(gray); gfx->setTextSize(1);
  gfx->setCursor(18, 79); gfx->print("AMBIANCE");
  gfx->setTextColor(orange); gfx->setTextSize(3);
  gfx->setCursor(175, 48); gfx->print(String(regulator.target(),1));
  gfx->setTextSize(1); gfx->setTextColor(gray);
  gfx->setCursor(175, 79); gfx->print("CONSIGNE");
  gfx->fillRoundRect(17, 98, 286, 26, 8,
                     regulator.heatRequested()?0x2384:0x4208);
  gfx->setTextSize(1);
  gfx->setTextColor(white); gfx->setCursor(25, 107);
  gfx->print(demandLabel(regulator.state()));
  gfx->setCursor(19, 136); gfx->setTextColor(gray);
  if (timeOk) {
    char clock[16]; snprintf(clock,sizeof(clock),"%02d:%02d",localTime.tm_hour,localTime.tm_min);
    gfx->print(clock);
  } else gfx->print("Heure NTP absente");
  gfx->setCursor(195, 136);
  gfx->print("SIMULATION");
  gfx->setTextColor(orange); gfx->setCursor(19, 166);
  gfx->print("AUCUNE SORTIE VERS LE POELE");
}
void handleButtons(uint32_t now) {
  const bool minus=(digitalRead(PIN_BUTTON_MINUS)==LOW);
  const bool plus=(digitalRead(PIN_BUTTON_PLUS)==LOW);
  if(now-lastButtonActionMs>=200U) {
    if(minus && !buttonMinusPrev) {
      regulator.setTarget(roundf((regulator.target()-0.1f)*10.0f)/10.0f);
      lastButtonChangeMs=now; lastButtonActionMs=now; configurationDirty=true;
    }
    if(plus && !buttonPlusPrev) {
      regulator.setTarget(roundf((regulator.target()+0.1f)*10.0f)/10.0f);
      lastButtonChangeMs=now; lastButtonActionMs=now; configurationDirty=true;
    }
  }
  buttonMinusPrev=minus; buttonPlusPrev=plus;
  if(configurationDirty && now-lastButtonChangeMs>3000U) {
    prefs.putFloat("target",regulator.target());
    configurationDirty=false;
  }
}
void serveStatus() {
  struct tm clock={};
  const bool clockValid=getLocalClock(clock);
  const bool sensorOk=sensorAvailable(millis());
  const String body=String("{\"product\":\"RIKA Smart ESP32-S3\",")+
    "\"version\":\"0.1.0\",\"mode\":\"dry_run\",\"relay_enabled\":false,"+
    "\"sensor_ok\":"+(sensorOk?"true":"false")+
    ",\"clock_ok\":"+(clockValid?"true":"false")+
    ",\"room_c\":"+(sensorOk?String(roomTemperature,2):"null")+
    ",\"target_c\":"+String(regulator.target(),1)+
    ",\"heat_request\":"+(regulator.heatRequested()?"true":"false")+
    ",\"decision\":\""+String(demandLabel(regulator.state()))+"\"}";
  http.sendHeader("Cache-Control","no-store");
  http.send(200,"application/json; charset=utf-8",body);
}
void startNetwork() {
  wifiConfigured=strlen(RIKA_WIFI_SSID)>0 && strcmp(RIKA_WIFI_SSID,"YOUR_WIFI_NAME")!=0;
  if (!wifiConfigured) { Serial.println("WiFi not configured: offline demonstration"); return; }
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(RIKA_WIFI_SSID,RIKA_WIFI_PASSWORD);
  lastConnectAttemptMs=millis();
}
void networkLoop(uint32_t now) {
  if(!wifiConfigured) return;
  if(WiFi.status()==WL_CONNECTED) {
    if(!webStarted) {
      configTzTime("CET-1CEST,M3.5.0/2,M10.5.0/3",
                   "pool.ntp.org","time.cloudflare.com");
      http.on("/api/status",HTTP_GET,serveStatus);
      http.on("/",HTTP_GET,[](){http.send(200,"text/plain; charset=utf-8",
          "RIKA Smart ESP32-S3 : GET /api/status (lecture seule, reseau local).");});
      http.onNotFound([](){http.send(404,"text/plain","Not found");});
      http.begin();
      webStarted=true;
      Serial.println("Local API: http://"+WiFi.localIP().toString()+"/api/status");
    }
    http.handleClient();
  } else if(now-lastConnectAttemptMs>30000U) {
    lastConnectAttemptMs=now;
    WiFi.disconnect();
    WiFi.begin(RIKA_WIFI_SSID, RIKA_WIFI_PASSWORD);
  }
}
void setup() {
  Serial.begin(115200);
  pinMode(PIN_BUTTON_MINUS,INPUT_PULLUP);
  pinMode(PIN_BUTTON_PLUS,INPUT_PULLUP);
  pinMode(PIN_LCD_POWER,OUTPUT); digitalWrite(PIN_LCD_POWER,HIGH);
  pinMode(PIN_LCD_BL,OUTPUT); digitalWrite(PIN_LCD_BL,HIGH);
  gfx->begin(); gfx->setRotation(1);
  dark=gfx->color565(29,30,34);
  darker=gfx->color565(12,13,15);
  orange=gfx->color565(255,120,43);
  white=gfx->color565(240,240,240);
  gray=gfx->color565(134,137,141);
  green=gfx->color565(46,173,115);
  red=gfx->color565(230,64,64);
  gfx->fillScreen(darker);
  Wire.begin(PIN_I2C_SDA,PIN_I2C_SCL);
  Wire.setClock(100000);
  prefs.begin("rika-smart",false);
  regulator.setTarget(prefs.getFloat("target",22.0f));
  startNetwork();
  Serial.println("RIKA Smart demo: no relay GPIO, no stove commands.");
}
void loop() {
  const uint32_t now=millis();
  handleButtons(now);
  networkLoop(now);
  if(now-lastSensorReadMs>=1500U) {
    lastSensorReadMs=now;
    float t=NAN,h=NAN;
    if(readSht31(t,h)) {
      roomTemperature=t;
      humidityPercent=h;
      lastValidSensorMs=millis();
      firstSensorReading=true;
    }
  }
  struct tm localTime={};
  bool timeOk=getLocalClock(localTime);
  const bool valid=sensorAvailable(millis());
  regulator.tick(roomTemperature,valid,timeOk,
        timeOk?localTime.tm_wday:-1,
        timeOk?localTime.tm_hour*60+localTime.tm_min:-1,
        millis());
  if(millis()-lastDrawMs>=1000U) {
    lastDrawMs=millis();
    displayUi(valid,timeOk,localTime);
  }
  delay(20);
}
