import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/auth.dart';
import '../core/errors.dart';
import 'handlers/admin_handlers.dart';
import 'handlers/auth_handlers.dart';
import 'handlers/content_handlers.dart';
import 'handlers/favorites_handlers.dart';
import 'handlers/history_handlers.dart';
import 'handlers/snippets_handlers.dart';

/// Заголовки CORS для админ-панели (Flutter Web).
const Map<String, String> _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS',
  'access-control-allow-headers': 'Content-Type, Authorization',
  'access-control-max-age': '86400',
};

/// Создание shelf-обработчика: CORS, журналирование, обработка ошибок.
Handler createHandler(Database db) {
  final router = ApiRouter(db);
  return (Request request) async {
    final stopwatch = Stopwatch()..start();
    Response response;

    if (request.method == 'OPTIONS') {
      response = Response(204);
    } else {
      try {
        response = await router.dispatch(request);
      } on ApiError catch (error) {
        response = errorResponse(error);
      } catch (error, stackTrace) {
        // Детали остаются в журнале сервера, клиенту — общее сообщение.
        stderr.writeln('Необработанная ошибка: $error\n$stackTrace');
        response = errorResponse(ApiError.internal());
      }
    }

    response = response.change(headers: _corsHeaders);
    stdout.writeln(
      '${request.method} /${request.url.path} -> ${response.statusCode} '
      '(${stopwatch.elapsedMilliseconds} мс)',
    );
    return response;
  };
}

/// Ручная маршрутизация по path и method (shelf_router не используется).
class ApiRouter {
  ApiRouter(Database db) : _auth = AuthService(db) {
    _authHandlers = AuthHandlers(db, _auth);
    _contentHandlers = ContentHandlers(db, _auth);
    _favoritesHandlers = FavoritesHandlers(db, _auth);
    _historyHandlers = HistoryHandlers(db, _auth);
    _snippetsHandlers = SnippetsHandlers(db, _auth);
    _adminHandlers = AdminHandlers(db, _auth);
  }

  final AuthService _auth;
  late final AuthHandlers _authHandlers;
  late final ContentHandlers _contentHandlers;
  late final FavoritesHandlers _favoritesHandlers;
  late final HistoryHandlers _historyHandlers;
  late final SnippetsHandlers _snippetsHandlers;
  late final AdminHandlers _adminHandlers;

  /// Маршрутизация запроса.
  Future<Response> dispatch(Request request) async {
    final segments = request.url.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty || segments.first != 'api') {
      throw ApiError.notFound('Маршрут не найден');
    }
    final route = segments.sublist(1);
    if (route.isEmpty) throw ApiError.notFound('Маршрут не найден');
    final method = request.method.toUpperCase();

    if (route.length == 1 && route[0] == 'health' && method == 'GET') {
      return jsonResponse({'status': 'ok'});
    }

    switch (route[0]) {
      case 'auth':
        return _dispatchAuth(request, method, route);
      case 'profile':
        return _dispatchProfile(request, method, route);
      case 'categories':
        if (route.length == 1 && method == 'GET') {
          return _contentHandlers.categories(request);
        }
        throw ApiError.notFound('Маршрут не найден');
      case 'articles':
        if (route.length == 1 && method == 'GET') {
          return _contentHandlers.articles(request);
        }
        if (route.length == 2 && method == 'GET') {
          return _contentHandlers.articleById(request, route[1]);
        }
        throw ApiError.notFound('Маршрут не найден');
      case 'favorites':
        return _dispatchFavorites(request, method, route);
      case 'history':
        return _dispatchHistory(request, method, route);
      case 'snippets':
        return _dispatchSnippets(request, method, route);
      case 'admin':
        return _dispatchAdmin(request, method, route);
    }
    throw ApiError.notFound('Маршрут не найден');
  }

  Future<Response> _dispatchAuth(
    Request request,
    String method,
    List<String> route,
  ) {
    if (route.length == 2) {
      switch (route[1]) {
        case 'register':
          if (method == 'POST') return _authHandlers.register(request);
        case 'login':
          if (method == 'POST') return _authHandlers.login(request);
        case 'logout':
          if (method == 'POST') return _authHandlers.logout(request);
        case 'me':
          if (method == 'GET') return _authHandlers.me(request);
      }
    }
    throw ApiError.notFound('Маршрут не найден');
  }

  Future<Response> _dispatchProfile(
    Request request,
    String method,
    List<String> route,
  ) {
    if (route.length == 1 && method == 'PUT') {
      return _authHandlers.updateProfile(request);
    }
    if (route.length == 2 && route[1] == 'password' && method == 'PUT') {
      return _authHandlers.changePassword(request);
    }
    throw ApiError.notFound('Маршрут не найден');
  }

  Future<Response> _dispatchFavorites(
    Request request,
    String method,
    List<String> route,
  ) {
    if (route.length == 1 && method == 'GET') {
      return _favoritesHandlers.list(request);
    }
    if (route.length == 2) {
      if (method == 'POST') {
        return _favoritesHandlers.add(request, route[1]);
      }
      if (method == 'DELETE') {
        return _favoritesHandlers.remove(request, route[1]);
      }
    }
    throw ApiError.notFound('Маршрут не найден');
  }

  Future<Response> _dispatchHistory(
    Request request,
    String method,
    List<String> route,
  ) {
    if (route.length == 1) {
      if (method == 'GET') return _historyHandlers.list(request);
      if (method == 'DELETE') return _historyHandlers.clear(request);
    }
    if (route.length == 2 && method == 'POST') {
      return _historyHandlers.record(request, route[1]);
    }
    throw ApiError.notFound('Маршрут не найден');
  }

  Future<Response> _dispatchSnippets(
    Request request,
    String method,
    List<String> route,
  ) {
    if (route.length == 1) {
      if (method == 'GET') return _snippetsHandlers.list(request);
      if (method == 'POST') return _snippetsHandlers.create(request);
    }
    if (route.length == 2) {
      switch (method) {
        case 'GET':
          return _snippetsHandlers.getById(request, route[1]);
        case 'PUT':
          return _snippetsHandlers.update(request, route[1]);
        case 'DELETE':
          return _snippetsHandlers.delete(request, route[1]);
      }
    }
    throw ApiError.notFound('Маршрут не найден');
  }

  Future<Response> _dispatchAdmin(
    Request request,
    String method,
    List<String> route,
  ) {
    if (route.length < 2) throw ApiError.notFound('Маршрут не найден');
    final section = route[1];
    final rest = route.sublist(2);

    switch (section) {
      case 'users':
        if (rest.isEmpty) {
          if (method == 'GET') return _adminHandlers.users(request);
          if (method == 'POST') return _adminHandlers.createUser(request);
        }
        if (rest.length == 1 && method == 'PUT') {
          return _adminHandlers.updateUser(request, rest[0]);
        }
        if (rest.length == 2 && method == 'PATCH') {
          if (rest[1] == 'block') {
            return _adminHandlers.blockUser(request, rest[0]);
          }
          if (rest[1] == 'role') {
            return _adminHandlers.changeRole(request, rest[0]);
          }
        }
        throw ApiError.notFound('Маршрут не найден');
      case 'articles':
        if (rest.isEmpty) {
          if (method == 'GET') return _adminHandlers.articles(request);
          if (method == 'POST') return _adminHandlers.createArticle(request);
        }
        if (rest.length == 1) {
          if (method == 'PUT') {
            return _adminHandlers.updateArticle(request, rest[0]);
          }
          if (method == 'DELETE') {
            return _adminHandlers.deleteArticle(request, rest[0]);
          }
        }
        if (rest.length == 2 && rest[1] == 'publish' && method == 'PATCH') {
          return _adminHandlers.publishArticle(request, rest[0]);
        }
        throw ApiError.notFound('Маршрут не найден');
      case 'categories':
        if (rest.isEmpty) {
          if (method == 'GET') return _adminHandlers.categories(request);
          if (method == 'POST') {
            return _adminHandlers.createCategory(request);
          }
        }
        if (rest.length == 1) {
          if (method == 'PUT') {
            return _adminHandlers.updateCategory(request, rest[0]);
          }
          if (method == 'DELETE') {
            return _adminHandlers.deleteCategory(request, rest[0]);
          }
        }
        throw ApiError.notFound('Маршрут не найден');
    }
    throw ApiError.notFound('Маршрут не найден');
  }
}
