import 'package:get_it/get_it.dart';

import 'package:frontend/admin/data/admin_users_repository.dart';
import 'package:frontend/auth/data/auth_api.dart';
import 'package:frontend/auth/data/auth_repository_impl.dart';
import 'package:frontend/auth/domain/auth_repository.dart';
import 'package:frontend/auth/domain/user_repository.dart';
import 'package:frontend/auth/presentation/bloc/auth_bloc.dart';
import 'package:frontend/chat/data/chat_repository.dart';
import 'package:frontend/core/network/api_client.dart';
import 'package:frontend/core/storage/token_storage.dart';
import 'package:frontend/todo/bloc/todo_bloc.dart';
import 'package:frontend/todo/domain/todo_repository.dart';

final getIt = GetIt.instance;

Future<void> setupDependencies() async {
  getIt.registerLazySingleton<TokenStorage>(() => SecureTokenStorage());
  getIt.registerLazySingleton<ApiClient>(
    () => ApiClient(tokenStorage: getIt<TokenStorage>()),
  );
  getIt.registerLazySingleton<AuthApi>(() => AuthApi(getIt<ApiClient>()));
  getIt.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(
      authApi: getIt<AuthApi>(),
      apiClient: getIt<ApiClient>(),
      tokenStorage: getIt<TokenStorage>(),
    ),
  );
  getIt.registerLazySingleton<UserRepository>(
    () => UserRepository(getIt<AuthRepository>()),
  );
  getIt.registerFactory<AuthBloc>(
    () => AuthBloc(
      authRepository: getIt<AuthRepository>(),
      apiClient: getIt<ApiClient>(),
    ),
  );
  getIt.registerLazySingleton<TodoRepository>(
    () => TodoRepository(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<AdminUsersRepository>(
    () => AdminUsersRepository(getIt<ApiClient>()),
  );
  getIt.registerLazySingleton<ChatRepository>(
    () => ChatRepository(
      apiClient: getIt<ApiClient>(),
      tokenStorage: getIt<TokenStorage>(),
    ),
  );
  getIt.registerFactory<TodoBloc>(
    () => TodoBloc(todoRepository: getIt<TodoRepository>()),
  );
}
