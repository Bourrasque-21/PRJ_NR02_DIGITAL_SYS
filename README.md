**1. Overview**  
 Basys3 보드 기반 통합 디지털 시스템
- Stopwatch
- Digital Clock
- SR04 Ultrasonic Distance Sensor
- DHT11 Temperature & Humidity Sensor
- UART-based PC Control Interface
  
  
**2. System Architecture** 
- Debounce 처리된 물리 버튼 입력과 UART를 통한 PC 입력 제어 통합  
- FND 컨트롤러가 시스템 모드에 따라 디스플레이 소스를 선택  
  
  
**3. Operating Modes**  
-  Stopwatch Mode    
Start/Stop/Clear 기능    

-  Clock Mode (Time-Set Mode 포함)    
실시간 시계 동작 및 시계 시간 설정    

-  SR04 Mode    
거리 측정 (cm)    

-  DHT11 Mode    
온도/습도 표시    
  
  
**4. Button & Switch Mapping**    
   
|Button  |	Function (SW/CLK Mode)  |  
|--------|----------------------------------|
|BTN_U   |	(Run / Stop) / Up  | 
|BTN_C   |	NA           / Time-set select  | 
|BTN_D   |	Clear        / Down  | 
  
Button  |	Function (SR04/DHT11 Mode)  
|-------|------------------------------------|
BTN_L   |	distance measurement  
BTN_R   |	temperature/humidity measurement  
  
|Mode Switches | SW[1] & SW[4]  |
|--------------|-----------------------------|  
|00            | Stopwatch mode  |
|01            | Clock mode  |
|10            | Sr04 mode  |
|11            | DHT11 mode  |
**LED indicator (same as system mode)  
  
|Switches | SW[0], SW[2], SW[3], SW[15]|
|---------|----------------------------------|
|SW[0]    | Stopwatch count mode (up/down)|
|SW[2]    | Display-format|
|SW[3]    | Time-set mode (LED turns ON in Clock mode)|
|SW[15]   | Reset|
  
  
**5. PC Control Mode**  
ASCII Command list  
```
M : Toggle PC Control Mode  
R : BTN_U
N : BTN_C
C : BTN_D  
T : BTN_L
H : BTN_R
Q : Request Current Time & DHT11 Sensor Data
  - Data Format
    HH:MM:SS:CC
    T xx.xC
    H xx.x%

0 : Toggle SW[0]
1 : Toggle SW[1]
2 : Toggle SW[2]
3 : Toggle SW[3]
4 : Toggle SW[4]
```
  
  
**6. Display Format(FND)**  
-  Stopwatch Mode  
  HH:MM / SS:CC  
  99:59 / 59:99 까지 표시 가능
  
-  Clock Mode (Time-Set Mode 포함)  
  HH:MM / SS:CC  
  24시간제 표시  
  *Time-set 모드에서는 선택 자리 LED 점등  
  
-  SR04 Mode  
  Sr04 / xxx.x  
  라벨 표시 / 0.1cm 측정 단위 표시  
  
-  DHT11 Mode  
  hxx.x / txx.x  
  습도 / 온도 표시
  
  
**7. Design Considerations**  
- Watchdog / Timeout Protection  
  **SR04 Timeout Handling**    
  1)echo 신호가 감지되지 않는 경우, 2)echo HIGH 구간이 비정상적인 경우  
  안정성 확보를 위한 FSM 복귀 타임아웃 설계  
  
  **DHT11 Watchdog Timer**  
  센서 응답 오류 및 통신 실패로 인해 FSM이 특정 상태에서 멈출 경우  
  FSM을 강제로 초기 상태로 복귀시키기 위 Watchdog Timer 사용  

- Metastability Mitigation  
  SR04 echo, DHT11 dhtio 비동기 신호 동기화(Synchronizer)  
  Edge detection 구조 설계  
  
- Input Priority Control  
  *PC 제어 모드* **활성화** 시 UART 입력을 통한 스위치 제어만 가능  
  **비활성화** 시 물리 스위치 제어만 가능  
