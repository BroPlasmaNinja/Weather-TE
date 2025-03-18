import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart'; // Для форматирования даты
import 'package:path_provider/path_provider.dart'; // Для работы с файлами
import 'dart:io'; // Для работы с файлами

// Классы для десериализации JSON остаются без изменений
class Main {
  double temp;
  double feelsLike;
  int humidity;

  Main({required this.temp, required this.feelsLike, required this.humidity});

  factory Main.fromJson(Map<String, dynamic> json) {
    return Main(
      temp: json['temp'].toDouble(),
      feelsLike: json['feels_like'].toDouble(),
      humidity: json['humidity'],
    );
  }
}

class Weather {
  String description;

  Weather({required this.description});

  factory Weather.fromJson(Map<String, dynamic> json) {
    return Weather(description: json['description']);
  }
}

class WeatherData {
  int dt;
  Main main;
  List<Weather> weather;
  String dtTxt;

  WeatherData({
    required this.dt,
    required this.main,
    required this.weather,
    required this.dtTxt,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      dt: json['dt'],
      main: Main.fromJson(json['main']),
      weather: (json['weather'] as List).map((i) => Weather.fromJson(i)).toList(),
      dtTxt: json['dt_txt'],
    );
  }
}

class City {
  String name;
  int sunrise;
  int sunset;

  City({required this.name, required this.sunrise, required this.sunset});

  factory City.fromJson(Map<String, dynamic> json) {
    return City(
      name: json['name'],
      sunrise: json['sunrise'],
      sunset: json['sunset'],
    );
  }
}

class ForecastResponse {
  String cod;
  int cnt;
  List<WeatherData> list;
  City city;

  ForecastResponse({
    required this.cod,
    required this.cnt,
    required this.list,
    required this.city,
  });

  factory ForecastResponse.fromJson(Map<String, dynamic> json) {
    return ForecastResponse(
      cod: json['cod'],
      cnt: json['cnt'],
      list: (json['list'] as List).map((i) => WeatherData.fromJson(i)).toList(),
      city: City.fromJson(json['city']),
    );
  }
}

// Новый класс для хранения городов в JSON
class SavedCity {
  final String name;

  SavedCity({required this.name});

  // Преобразование в JSON
  Map<String, dynamic> toJson() => {
    'name': name,
  };

  // Создание объекта из JSON
  factory SavedCity.fromJson(Map<String, dynamic> json) {
    return SavedCity(
      name: json['name'],
    );
  }
}

// Основной виджет приложения
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String cityName = 'Загрузка...';
  WeatherData? selectedWeatherData; // Выбранное время для контейнера 2
  List<WeatherData> allForecast = []; // Все отрезки времени
  Map<String, List<WeatherData>> dailyForecast = {}; // Прогнозы, сгруппированные по дням
  String selectedDay = ''; // Выбранный день для контейнера 3
  List<WeatherData> selectedDayForecast = []; // Прогноз для выбранного дня

  Color backgroundColor = Color(0xFF5D9B9B);

  DateTime? sunrise;
  DateTime? sunset;

  List<SavedCity> cities = []; // Список сохраненных городов

  // Путь к файлу для сохранения городов
  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/cities.json');
  }

  // Метод для сохранения списка городов в JSON-файл
  Future<void> saveCitiesToFile(List<SavedCity> cities) async {
    final file = await _localFile;
    final jsonString = json.encode(cities.map((city) => city.toJson()).toList());
    await file.writeAsString(jsonString);
  }

  // Метод для загрузки списка городов из JSON-файла
  Future<List<SavedCity>> loadCitiesFromFile() async {
    try {
      final file = await _localFile;
      final contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      return jsonList.map((json) => SavedCity.fromJson(json)).toList();
    } catch (e) {
      // Если файл не найден или произошла ошибка, возвращаем пустой список
      return [];
    }
  }

  // Установка фона в зависимости от времени суток
  void setBackgroundColor() {
    if (sunrise == null || sunset == null) return;

    DateTime now = DateTime.now();
    DateTime sunriseStart = sunrise!.subtract(Duration(minutes: 20));
    DateTime sunriseEnd = sunrise!.add(Duration(minutes: 20));
    DateTime sunsetStart = sunset!.subtract(Duration(minutes: 20));
    DateTime sunsetEnd = sunset!.add(Duration(minutes: 20));
    DateTime afterSunset = sunset!.add(Duration(hours: 1));

    setState(() {
      if ((now.isAfter(sunriseStart) && now.isBefore(sunriseEnd)) ||
          (now.isAfter(sunsetStart) && now.isBefore(sunsetEnd))) {
        backgroundColor = Color(0xFFFF7514); // Восход или Закат
      } else if (now.isAfter(sunriseEnd) && now.isBefore(sunsetStart)) {
        backgroundColor = Color(0xFFEFA94A); // День
      } else if (now.isAfter(sunset!) && now.isBefore(afterSunset)) {
        backgroundColor = Color(0xFF5D9B9B); // Час после заката
      } else {
        backgroundColor = Color(0xFFA18594); // Ночь
      }
    });
  }

  // Загрузка данных о погоде
  Future<void> fetchWeatherData() async {
    final response = await http.get(Uri.parse(
        'http://api.openweathermap.org/data/2.5/forecast?lat=54.3107593&lon=48.3642771&appid=8aa58f5bf4b1fb19445883a8b8b769a0&lang=ru'));
    if (response.statusCode == 200) {
      final forecast = ForecastResponse.fromJson(json.decode(response.body));

      // Сначала сохраняем все отрезки времени в один список
      List<WeatherData> allData = forecast.list;

      // Группируем данные по дням
      Map<String, List<WeatherData>> groupedByDay = {};
      for (var data in allData) {
        String day = data.dtTxt.split(' ')[0];
        if (!groupedByDay.containsKey(day)) {
          groupedByDay[day] = [];
        }
        groupedByDay[day]!.add(data);
      }

      // Находим ближайшее текущее время
      DateTime now = DateTime.now();
      WeatherData? currentWeather = allData.firstWhere(
            (data) => DateTime.parse(data.dtTxt).isAfter(now),
        orElse: () => allData.first,
      );

      setState(() {
        cityName = forecast.city.name;
        allForecast = allData;
        dailyForecast = groupedByDay;

        // Устанавливаем текущий день и ближайшее время по умолчанию
        selectedDay = groupedByDay.keys.first;
        selectedDayForecast = groupedByDay[selectedDay]!;
        selectedWeatherData = currentWeather;

        sunrise = DateTime.fromMillisecondsSinceEpoch(forecast.city.sunrise * 1000, isUtc: true).toLocal();
        sunset = DateTime.fromMillisecondsSinceEpoch(forecast.city.sunset * 1000, isUtc: true).toLocal();

        setBackgroundColor();
      });

      // Сохраняем город, если его еще нет в списке
      if (!cities.any((city) => city.name == forecast.city.name)) {
        cities.add(SavedCity(name: forecast.city.name));
        await saveCitiesToFile(cities);
      }
    } else {
      print('Ошибка при загрузке данных: ${response.statusCode}');
      setState(() {
        sunrise = DateTime.parse("2023-10-17 06:00:00");
        sunset = DateTime.parse("2023-10-17 18:00:00");
        setBackgroundColor();
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Загружаем список городов при запуске приложения
    loadCitiesFromFile().then((loadedCities) {
      setState(() {
        cities = loadedCities;
      });
      // Загружаем погоду для первого города или по умолчанию
      fetchWeatherData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: backgroundColor, // Основной фон приложения
        appBar: AppBar(
          title: Text('Погода'),
          backgroundColor: Colors.grey.withOpacity(0.3), // Полупрозрачный AppBar
          elevation: 0, // Убираем тень
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0), // Отступы по краям экрана
          child: Column(
            children: [
              // Контейнер 1: Название города (2 части)
              Flexible(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3), // Полупрозрачный серый фон
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: Colors.grey[600]!, width: 2.0), // Выделенные края
                  ),
                  child: Center(
                    child: Text(
                      cityName,
                      style: TextStyle(fontSize: 24, color: Colors.white), // Белый текст
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10), // Отступ между контейнерами

              // Контейнер 2: Полная информация о выбранном времени
              Flexible(
                flex: 5,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3), // Полупрозрачный серый фон
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: Colors.grey[600]!, width: 2.0), // Выделенные края
                  ),
                  child: Center(
                    child: selectedWeatherData != null
                        ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${(selectedWeatherData!.main.temp - 273.15).toStringAsFixed(1)}°C',
                          style: TextStyle(fontSize: 48, color: Colors.white),
                        ),
                        Text(
                          'Ощущается как: ${(selectedWeatherData!.main.feelsLike - 273.15).toStringAsFixed(1)}°C',
                          style: TextStyle(color: Colors.white),
                        ),
                        Text(
                          'Влажность: ${selectedWeatherData!.main.humidity}%',
                          style: TextStyle(color: Colors.white),
                        ),
                        Text(
                          'Описание: ${selectedWeatherData!.weather[0].description}',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    )
                        : Text(
                      'Загрузка...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 10), // Отступ между контейнерами

              // Контейнер 3: Времена для выбранного дня
              Flexible(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3), // Полупрозрачный серый фон
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: Colors.grey[600]!, width: 2.0), // Выделенные края
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: selectedDayForecast.length,
                    itemBuilder: (context, index) {
                      final data = selectedDayForecast[index];
                      final celsius = (data.main.temp - 273.15).toStringAsFixed(1);
                      final time = data.dtTxt.split(' ')[1].substring(0, 5);
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedWeatherData = data;
                          });
                        },
                        child: Container(
                          width: 100,
                          margin: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selectedWeatherData == data
                                ? Colors.blueAccent.withOpacity(0.5)
                                : Colors.grey.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(color: Colors.grey[600]!, width: 2.0),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                time,
                                style: TextStyle(color: Colors.white),
                              ),
                              Text(
                                '$celsius°C',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: 10), // Отступ между контейнерами

              // Контейнер 4: Дни для выбора
              Flexible(
                flex: 4,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3), // Полупрозрачный серый фон
                    borderRadius: BorderRadius.circular(16.0),
                    border: Border.all(color: Colors.grey[600]!, width: 2.0), // Выделенные края
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: dailyForecast.keys.length,
                    itemBuilder: (context, index) {
                      final day = dailyForecast.keys.toList()[index];
                      final dayData = dailyForecast[day]!;
                      final avgTemp = dayData.map((e) => e.main.temp).reduce((a, b) => a + b) / dayData.length;
                      final celsius = (avgTemp - 273.15).toStringAsFixed(1);
                      final date = DateFormat('d MMM').format(DateTime.parse(day));
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedDay = day;
                            selectedDayForecast = dayData;
                            selectedWeatherData = dayData.first; // По умолчанию первое время дня
                          });
                        },
                        child: Container(
                          width: 100,
                          margin: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: selectedDay == day
                                ? Colors.blueAccent.withOpacity(0.5)
                                : Colors.grey.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12.0),
                            border: Border.all(color: Colors.grey[600]!, width: 2.0),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                date,
                                style: TextStyle(color: Colors.white),
                              ),
                              Text(
                                '$celsius°C',
                                style: TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              SizedBox(height: 10), // Отступ между контейнерами

              // Контейнер 5: Свайпать между городами (1 часть)
              Flexible(
                flex: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3), // Полупрозрачный серый фон
                    border: Border.all(color: Colors.grey[600]!, width: 2.0), // Выделенные края
                  ),
                  child: Center(
                    child: Text(
                      '<—————————————————>',
                      style: TextStyle(fontSize: 24, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  runApp(MyApp());
}