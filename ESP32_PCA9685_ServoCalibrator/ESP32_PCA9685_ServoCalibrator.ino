#include <Wire.h>
#include <Adafruit_PWMServoDriver.h>
#include <WiFi.h>
#include <WebServer.h>

// Замените на свои SSID и пароль Wi-Fi
const char* ssid = "TP-LINK_24F3";
const char* password = "fdsarr2023";

// Создаем веб-сервер на порту 80
WebServer server(80);

// Создаем объект для PCA9685
Adafruit_PWMServoDriver pwm = Adafruit_PWMServoDriver();

// Определение диапазона для сервоприводов
//int SERVOMIN = 80;
//int SERVOMAX = 600;
int currentPulse = 500; // Текущее значение импульса
int servoNum = 12; // Номер сервопривода (если используется один, можно оставить 0)

// HTML-код страницы
const char webpage[] PROGMEM = R"=====(
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Web Page with Slider and Buttons</title>
    <style>    
        
        body {
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            margin: 0;
            font-family: Arial, sans-serif;            
            background: #1f253d;
        }
        .container { 
            text-align: center;
            display: block;
            width: 300px;            
            padding: 0px;
            border-bottom-left-radius: 5px;
            border-bottom-right-radius: 5px;
            background: #4c5164;            

        }
        .titular {
            display: block;            
            line-height: 60px;
            width: 100%;
            margin: 0;
            text-align: center;
            border-top-left-radius: 5px;
            border-top-right-radius: 5px;
        }

         .titular2 {
            display: block;
            line-height: 100%;
            width: 100%;
            margin: 0;
            text-align: center;
            border-bottom-left-radius: 5px;
            border-bottom-right-radius: 5px;
        }

        h1 {            
            color: #fff;
            background-color: #11a8ab;
        }

        input[type="range"] {
            -webkit-appearance: none;
            width: 90%;
            height: 8px;
            border: solid 2px;
            border-color: #1f253d;
            border-radius: 5px;
            background: #DFD0B8;
            outline: none;
            opacity: 0.7;
            -webkit-transition: .2s;
            transition: opacity .2s;            
            margin: 10px 0;

            &:active + #rangevalue
        }

        input[type="range"]::-webkit-slider-thumb {
            -webkit-appearance: none;
            appearance: none;
            width: 17px;
            height: 17px;
            border-radius: 50%;
            background: #948979;
            cursor: pointer;
        }
        input[type="range"]::-moz-range-thumb {
            width: 17px;
            height: 17px;
            border-radius: 50%;
            background: #948979;
            cursor: pointer;
        }
        input[type="range"]::-ms-thumb {
            width: 17px;
            height: 17px;
            border-radius: 50%;
            background: #948979;
            cursor: pointer;
        }

        output {
            color: #fff;
        }
        .buttons {
            display: flex;
            justify-content: space-between;
            margin: 10px;            
        }
        .buttons button{
            width: 23%;
            padding: 10px;            
            border: solid 2px;
            background-color: #948979;
            color: #fff;
            font-size: 16px;
            cursor: pointer;
            border-radius: 5px;
        }
        
        .buttons2 {
            display: flex;
            justify-content: space-between;
            margin: 10px;            
        }

        .buttons2 button{
            width: 32%;
            padding: 10px;            
            border: solid 2px;
            background-color: #948979;
            color: #fff;            
            font-size: 16px;
            cursor: pointer;
            border-radius: 5px;            
        }

        .resetMinMax button{
            width: 94%;
            padding: 10px;            
            border: solid 2px;
            background-color: #948979;
            color: #fff;
            font-size: 16px;
            cursor: pointer;
            border-radius: 5px;
        }
        
        .buttons button:hover, .buttons2 button:hover, .resetMinMax button:hover {
            background-color: #DFD0B8;            
            color: #1f253d;
        }

    </style>
</head>
<body>
    
    <div class="container">
    <h1 class="titular">servo calibrator</h1>    
    <div class="container">
    <br>                
        <input type="range" id="pin" min="0" max="15" value="12"><br>
        <b><output id="rangevalue_pin">servo pin number: 12</output></b><br>
        <input type="range" id="slider" min="0" max="1000" value="500"><br>
        <b><output id="rangevalue_slider">pulse wight: 500</output></b>
        <br>
        <br>
        <div class="buttons">
            <button id="minus5">- 5</button>
            <button id="minus1">- 1</button>
            <button id="plus1">+ 1</button>
            <button id="plus5">+ 5</button>
        </div>

        <div class="resetMinMax">
        <button id="resetMinMax">reset min\max</button>
        </div>

        <div class="buttons2">
            <button id="SERVOMIN">set min</button>
            <button id="setCenter">center</button>
            <button id="SERVOMAX">set max</button>        
        </div>
    </div>

    <script>
        const resetminmax = document.getElementById('resetMinMax');
        const pin = document.getElementById('pin');
        const slider = document.getElementById('slider');
        const minus5 = document.getElementById('minus5');
        const minus1 = document.getElementById('minus1');
        const plus1 = document.getElementById('plus1');
        const plus5 = document.getElementById('plus5');
        const showPinNumber = document.getElementById('rangevalue_pin');
        const showSliderNumber = document.getElementById('rangevalue_slider');
        const setCenter = document.getElementById('setCenter');
        const servomin = document.getElementById('SERVOMIN');
        const servomax = document.getElementById('SERVOMAX');

        function changePin() {            
            showPinNumber.textContent = `servo pin number: ${pin.value}`;
            sendData('/changepin',pin.value);
        }

        function updateSliderText() {
            showSliderNumber.textContent = `pulse wight: ${slider.value}`;
            sendData('/action',slider.value);
        }

        resetminmax.addEventListener('click', () => {
            slider.min = 0;
            slider.max = 1000;
            sendData('/restminmax',1);
        });

        minus5.addEventListener('click', () => {
            slider.value = Math.max(0, parseInt(slider.value) - 5);
            updateSliderText();
            sendData('/action',slider.value);
        });

        minus1.addEventListener('click', () => {
            slider.value = Math.max(0, parseInt(slider.value) - 1);
            updateSliderText();
            sendData('/action', slider.value);
        });

        plus1.addEventListener('click', () => {
            slider.value = Math.min(1000, parseInt(slider.value) + 1);
            updateSliderText();
            sendData('/action', slider.value);
        });

        plus5.addEventListener('click', () => {
            slider.value = Math.min(1000, parseInt(slider.value) + 5);
            updateSliderText();
            sendData('/action', slider.value);
        });

        setCenter.addEventListener('click', () => {            
            slider.value = Math.round((parseInt(slider.max) + parseInt(slider.min)) / 2);
            updateSliderText();
            sendData('/action', slider.value);
        });

        pin.addEventListener('input', changePin);
        slider.addEventListener('input', updateSliderText);

        servomin.addEventListener('click', () => {
            slider.min = slider.value;
            sendData('/setmin', slider.value);
            updateSliderText();
        });

        servomax.addEventListener('click', () => {
            slider.max = slider.value;
            sendData('/setmax', slider.value);
            updateSliderText();
        });

        function sendData(endpoint, value) {
            var xhr = new XMLHttpRequest();
            xhr.open("GET", endpoint + "?value=" + value, true);
            xhr.send();
        }

        // Initial update of button text
        updateSliderText();
    </script>
</body>
</html>
)=====";

void setup() {
  Serial.begin(115200);
  
  // Инициализация PCA9685
  pwm.begin();
  pwm.setPWMFreq(50); // Частота 50 Гц для сервоприводов

  // Подключение к Wi-Fi
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(1000);
    Serial.println("Connecting to WiFi...");
  }
  Serial.println("Connected to WiFi");
  Serial.print("IP address: "); Serial.println(WiFi.localIP());

// ===========================================================================

server.on("/changepin", HTTP_GET, []() {  
  if (server.hasArg("value")) {
    servoNum = server.arg("value").toInt();    
  }
  server.send(200, "text/plain", "OK");
});

// Обработчик запросов на /set
server.on("/action", HTTP_GET, []() {
  if (server.hasArg("value")) {
    currentPulse = server.arg("value").toInt();
    pwm.setPWM(servoNum, 0, currentPulse);
  }
  server.send(200, "text/plain", "OK");
});

/*
// Обработчик запросов на /setmin
server.on("/setmin", HTTP_GET, []() {
  if (server.hasArg("value")) {
    SERVOMIN = server.arg("value").toInt();
    // Обновляем минимальное значение слайдера
    String script = "<script>document.getElementById('slider').min = " + String(SERVOMIN) + ";</script>";
    server.send(200, "text/html", script);
  } else {
    server.send(400, "text/plain", "Bad Request");
  }
});

// Обработчик запросов на /setmax
server.on("/setmax", HTTP_GET, []() {
  if (server.hasArg("value")) {
    SERVOMAX = server.arg("value").toInt();
    // Обновляем максимальное значение слайдера
    String script = "<script>document.getElementById('slider').max = " + String(SERVOMAX) + ";</script>";
    server.send(200, "text/html", script);
  } else {
    server.send(400, "text/plain", "Bad Request");
  }
});

*/

  // Отправка HTML-страницы
  server.on("/", HTTP_GET, []() {
    server.send_P(200, "text/html", webpage);
  });

  // Запуск веб-сервера
  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  // Обработка запросов клиента
  server.handleClient();
}
