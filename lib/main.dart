import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// -----------------------------------
///          External Packages
/// -----------------------------------
final FlutterAppAuth appAuth = FlutterAppAuth();
final FlutterSecureStorage secureStorage = FlutterSecureStorage();

/// -----------------------------------
///           Auth0 Variables
/// -----------------------------------

String auth0Domain = dotenv.get('AUTH0_DOMAIN');
String auth0ClientId = dotenv.get('AUTH0_CLIENT_ID');
String auth0RedirectUri = dotenv.get('AUTH0_REDIRECT_URI');
String auth0Issuer = dotenv.get('AUTH0_ISSUER');

Future main() async {
  // To load the .env file contents into dotenv.
  // NOTE: fileName defaults to .env and can be omitted in this case.
  // Ensure that the filename corresponds to the path in step 1 and 2.
  await dotenv.load(fileName: ".env");
  runApp(MyHomePage());
}

class MyHomePage extends StatefulWidget {
  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool isBusy = false;
  bool isLoggedIn = false;
  String errorMessage = '';
  String name = '';
  String picture = '';

  @override
  Widget build(BuildContext context) {
    const text = Text('Auth0 Demo');
    const circularProgressIndicator = CircularProgressIndicator();
    return MaterialApp(
      title: 'Auth0 Demo',
      home: Scaffold(
        appBar: AppBar(
          title: text,
        ),
        body: Center(
          child: isBusy
              ? circularProgressIndicator
              : isLoggedIn
                  ? Profile(logoutAction, name, picture)
                  : Login(loginAction, errorMessage),
        ),
      ),
    );
  }

  Map<String, dynamic> parseIdToken(String? idToken) {
    final parts = idToken!.split(r'.');
    assert(parts.length == 3);

    return jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
  }

  Future<Map<String, dynamic>> getUserDetails(String? accessToken) async {
    final url = Uri.parse('https://$auth0Domain/userinfo');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user details');
    }
  }

  Future<void> loginAction() async {
    setState(() {
      isBusy = true;
      errorMessage = '';
    });

    try {
      final AuthorizationTokenResponse? result =
          await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(auth0ClientId, auth0RedirectUri,
            issuer: 'https://$auth0Domain',
            scopes: [
              'openid',
              'profile',
              'offline_access'
            ],
            promptValues: [
              'login'
            ] // ignore any existing session; force interactive login prompt
            ),
      );

      final idToken = parseIdToken(result!.idToken);
      final profile = await getUserDetails(result.accessToken);

      await secureStorage.write(
          key: 'refresh_token', value: result.refreshToken);

      setState(() {
        isBusy = false;
        isLoggedIn = true;
        name = idToken['name'];
        picture = profile['picture'];
      });
    } catch (e) {
      setState(() {
        isBusy = false;
        isLoggedIn = false;
        errorMessage = e.toString();
      });
    }
  }

  void logoutAction() async {
    await secureStorage.delete(key: 'refresh_token');
    setState(() {
      isLoggedIn = false;
      isBusy = false;
    });
  }

  @override
  void initState() {
    initAction();
    super.initState();
  }

  void initAction() async {
    final storedRefreshToken = await secureStorage.read(key: 'refresh_token');
    if (storedRefreshToken == null) return;

    setState(() {
      isBusy = true;
    });

    try {
      final response = await appAuth.token(TokenRequest(
        auth0ClientId,
        auth0RedirectUri,
        issuer: auth0Issuer,
        refreshToken: storedRefreshToken,
      ));

      final idToken = parseIdToken(response!.idToken);
      final profile = await getUserDetails(response.accessToken);

      secureStorage.write(key: 'refresh_token', value: response.refreshToken);

      setState(() {
        isBusy = false;
        isLoggedIn = true;
        name = idToken['name'];
        picture = profile['picture'];
      });
    } catch (e) {
      logoutAction();
    }
  }
}

/// -----------------------------------
///           Profile Widget
/// -----------------------------------

class Profile extends StatelessWidget {
  final logoutAction;
  final String name;
  final String picture;

  const Profile(this.logoutAction, this.name, this.picture);

  @override
  Widget build(BuildContext context) {
    const sizedBox24 = SizedBox(height: 24.0);
    const sizedBox48 = SizedBox(height: 48.0);
    const logoutText = Text('Logout');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Container(
          width: 150,
          height: 150,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 4.0),
            shape: BoxShape.circle,
            image: DecorationImage(
              fit: BoxFit.fill,
              image: NetworkImage(picture),
            ),
          ),
        ),
        sizedBox24,
        Text('Name: $name'),
        sizedBox48,
        ElevatedButton(
          onPressed: () {
            logoutAction();
          },
          child: logoutText,
        ),
      ],
    );
  }
}

/// -----------------------------------
///            Login Widget
/// -----------------------------------

class Login extends StatelessWidget {
  final loginAction;
  final String loginError;

  const Login(this.loginAction, this.loginError);

  @override
  Widget build(BuildContext context) {
    const loginText = Text('Login');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ElevatedButton(
          onPressed: () {
            loginAction();
          },
          child: loginText,
        ),
        Text(loginError),
      ],
    );
  }
}
