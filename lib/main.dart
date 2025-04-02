import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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
  Main main;
  List<Weather> weather;
  String dtTxt;

  WeatherData({
    required this.main,
    required this.weather,
    required this.dtTxt,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    return WeatherData(
      main: Main.fromJson(json['main']),
      weather: (json['weather'] as List).map((i) => Weather.fromJson(i)).toList(),
      dtTxt: json['dt_txt'],
    );
  }
}

class Place {
  final String? name;
  final double lat;
  final double lon;
  final int? sunrise;
  final int? sunset;

  Place({this.name, this.sunrise, this.sunset, required this.lat, required this.lon});

  Map<String, dynamic> toJson() => {
    'name': name,
    'coord': {
      'lat': lat,
      'lon': lon,
    },
    'sunrise': sunrise,
    'sunset': sunset,
  };

  factory Place.fromJson(Map<String, dynamic> json) {
    return Place(
      name: json['name'],
      sunrise: json['sunrise'],
      sunset: json['sunset'],
      lat: json['coord']['lat'],
      lon: json['coord']['lon'],
    );
  }
}

class ForecastResponse {
  List<WeatherData> list;
  Place city;

  ForecastResponse({
    required this.list,
    required this.city,
  });

  factory ForecastResponse.fromJson(Map<String, dynamic> json) {
    return ForecastResponse(
      list: (json['list'] as List).map((i) => WeatherData.fromJson(i)).toList(),
      city: Place.fromJson(json['city']),
    );
  }
}

// Основной виджет приложения
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

Color goodBackgroundColor([DateTime? sunrise, DateTime? sunset]) {
  if (sunrise == null || sunset == null) {
    DateTime now = DateTime.now();
    sunrise = DateTime.utc(now.year, now.month, now.day, 6);
    sunset = DateTime.utc(now.year, now.month, now.day, 20);
  }

  DateTime now = DateTime.now();
  DateTime sunriseStart = sunrise.subtract(Duration(minutes: 20));
  DateTime sunriseEnd = sunrise.add(Duration(minutes: 20));
  DateTime sunsetStart = sunset.subtract(Duration(minutes: 20));
  DateTime sunsetEnd = sunset.add(Duration(minutes: 20));
  DateTime afterSunset = sunset.add(Duration(hours: 1));
  return (now.isAfter(sunriseStart) && now.isBefore(sunriseEnd)) ||
      (now.isAfter(sunsetStart) && now.isBefore(sunsetEnd)) ? Color(0xFFFF7514) :
  (now.isAfter(sunriseEnd) && now.isBefore(sunsetStart)) ? Color(0xFFEFA94A) :
  (now.isAfter(sunset) && now.isBefore(afterSunset)) ? Color(0xFF5D9B9B) :
  Color(0xFFA18594);
}

class _MyAppState extends State<MyApp> {
  List<Place> places = [];
  PageController _pageController = PageController();

  Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  Future<File> get _localFile async {
    final path = await _localPath;
    return File('$path/cities.json');
  }

  Future<void> saveCitiesToFile(List<Place> places) async {
    try {
      final file = await _localFile;
      final jsonString = json.encode(places.map((city) => city.toJson()).toList());
      await file.writeAsString(jsonString);
    } catch (e) {
    }
  }

  Future<List<Place>> loadCitiesFromFile() async {
    try {
      final file = await _localFile;
      final contents = await file.readAsString();
      final List<dynamic> jsonList = json.decode(contents);
      return jsonList.map((json) => Place.fromJson(json)).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  void initState() {
    super.initState();
    loadCitiesFromFile().then((loadedCities) {
      setState(() {
        places = loadedCities;
      });
    });

    // Слушатель для скрытия клавиатуры при перелистывании
    _pageController.addListener(() {
      if (_pageController.page != null && _pageController.page! < places.length) {
        FocusScope.of(context).unfocus();
      }
    });
  }

  void _addCity(Place city) {
    setState(() {
      places.add(city);
      saveCitiesToFile(places);
      _pageController.jumpToPage(places.length - 1); // Переход к последнему городу
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        resizeToAvoidBottomInset: false, // Предотвращаем сжатие интерфейса
        body: PageView.builder(
          controller: _pageController,
          itemCount: places.length + 1, // +1 для страницы добавления
          itemBuilder: (context, index) {
            if (index < places.length) {
              return CityWeatherPage(place: places[index]);
            } else {
              return AddCityWidget(
                backgroundColor: goodBackgroundColor(), // Можно настроить
                onCityAdded: _addCity,
              );
            }
          },
        ),
      ),
    );
  }
}

// Виджет для страницы погоды города
class CityWeatherPage extends StatefulWidget {
  final Place place;

  CityWeatherPage({required this.place});

  @override
  _CityWeatherPageState createState() => _CityWeatherPageState();
}

class _CityWeatherPageState extends State<CityWeatherPage> {
  String cityName = 'Загрузка...';
  WeatherData? selectedWeatherData;
  List<WeatherData> allForecast = [];
  Map<String, List<WeatherData>> dailyForecast = {};
  String selectedDay = '';
  List<WeatherData> selectedDayForecast = [];
  Color backgroundColor = goodBackgroundColor();
  DateTime? sunrise;
  DateTime? sunset;

  @override
  void initState() {
    super.initState();
    fetchWeatherData();
  }

  void setBackgroundColor() {
    setState(() {
      backgroundColor = goodBackgroundColor(sunrise, sunset);
    });
  }

  Future<void> fetchWeatherData() async {
    final response = await http.get(Uri.parse(
        'http://api.openweathermap.org/data/2.5/forecast?lat=${widget.place.lat}&lon=${widget.place.lon}&appid=8aa58f5bf4b1fb19445883a8b8b769a0&lang=ru'));
    if (response.statusCode == 200) {
      final forecast = ForecastResponse.fromJson(json.decode(response.body));
      List<WeatherData> allData = forecast.list;

      Map<String, List<WeatherData>> groupedByDay = {};
      for (var data in allData) {
        String day = data.dtTxt.split(' ')[0];
        if (!groupedByDay.containsKey(day)) {
          groupedByDay[day] = [];
        }
        groupedByDay[day]!.add(data);
      }

      DateTime now = DateTime.now();
      WeatherData? currentWeather = allData.firstWhere(
            (data) => DateTime.parse(data.dtTxt).isAfter(now),
        orElse: () => allData.first,
      );
      if (mounted) {
        setState(() {
          cityName = forecast.city.name ?? "Какое-то место";
          allForecast = allData;
          dailyForecast = groupedByDay;
          selectedDay = groupedByDay.keys.first;
          selectedDayForecast = groupedByDay[selectedDay]!;
          selectedWeatherData = currentWeather;
          sunrise = DateTime.fromMillisecondsSinceEpoch(forecast.city.sunrise! * 1000, isUtc: true).toLocal();
          sunset = DateTime.fromMillisecondsSinceEpoch(forecast.city.sunset! * 1000, isUtc: true).toLocal();
          setBackgroundColor();
        });
      }
    } else {
      setState(() {
        cityName = 'Ошибка загрузки';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // Предотвращаем сжатие интерфейса
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text('Погода'),
        backgroundColor: Colors.grey.withOpacity(0.3),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Flexible(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.grey[600]!, width: 2.0),
                ),
                child: Center(
                  child: Text(
                    cityName,
                    style: TextStyle(fontSize: 24, color: Colors.white),
                  ),
                ),
              ),
            ),
            SizedBox(height: 10),
            Flexible(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.grey[600]!, width: 2.0),
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
            SizedBox(height: 10),
            Flexible(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.grey[600]!, width: 2.0),
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
            SizedBox(height: 10),
            Flexible(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.grey[600]!, width: 2.0),
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
                          selectedWeatherData = dayData.first;
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
            SizedBox(height: 10),
            Flexible(
              flex: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  border: Border.all(color: Colors.grey[600]!, width: 2.0),
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
    );
  }
}

// Виджет добавления города
class AddCityWidget extends StatefulWidget {
  final Color backgroundColor;
  final Function(Place) onCityAdded;

  const AddCityWidget({required this.backgroundColor, required this.onCityAdded});

  @override
  _AddCityWidgetState createState() => _AddCityWidgetState();
}

class _AddCityWidgetState extends State<AddCityWidget> {
  final TextEditingController _controller = TextEditingController();
  String _errorMessage = '';

  void _addCity() async {
    final cityName = _controller.text;
    if (cityName.isEmpty) {
      setState(() {
        _errorMessage = 'Введите название города';
      });
      return;
    }

    final response = await http.get(Uri.parse(
        'http://api.openweathermap.org/geo/1.0/direct?q=$cityName&limit=1&appid=8aa58f5bf4b1fb19445883a8b8b769a0'));
    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      if (data.isNotEmpty) {
        final city = Place(
          name: data[0]['name'],
          lat: data[0]['lat'],
          lon: data[0]['lon'],
        );
        widget.onCityAdded(city);
        _controller.clear();
        setState(() {
          _errorMessage = '';
        });
      } else {
        setState(() {
          _errorMessage = 'Город не найден';
        });
      }
    } else {
      setState(() {
        _errorMessage = 'Ошибка при получении данных';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, // Предотвращаем сжатие интерфейса
      backgroundColor: widget.backgroundColor,
      appBar: AppBar(
        title: Text('Добавить город'),
        backgroundColor: Colors.grey.withOpacity(0.3),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Flexible(
              flex: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.grey[600]!, width: 2.0),
                ),
                child: const Center(
                  child: Text(
                    'Добавить новый город',
                    style: TextStyle(fontSize: 24, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              flex: 5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16.0),
                  border: Border.all(color: Colors.grey[600]!, width: 2.0),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Введите название города',
                          hintStyle: TextStyle(color: Colors.white),
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _addCity,
                        child: const Text('Добавить'),
                      ),
                      if (_errorMessage.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(flex: 4, child: Container()),
            const SizedBox(height: 10),
            Flexible(flex: 4, child: Container()),
          ],
        ),
      ),
    );
  }
}

void main() {
  runApp(MyApp());
}