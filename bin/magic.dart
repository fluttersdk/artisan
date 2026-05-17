import 'package:magic_cli/src/console/kernel.dart';
import 'package:magic_cli/src/commands/key_generate_command.dart';
import 'package:magic_cli/src/commands/make_migration_command.dart';
import 'package:magic_cli/src/commands/make_model_command.dart';
import 'package:magic_cli/src/commands/make_lang_command.dart';
import 'package:magic_cli/src/commands/make_seeder_command.dart';
import 'package:magic_cli/src/commands/make_factory_command.dart';
import 'package:magic_cli/src/commands/make_view_command.dart';
import 'package:magic_cli/src/commands/make_controller_command.dart';
import 'package:magic_cli/src/commands/make_policy_command.dart';
import 'package:magic_cli/src/commands/install_command.dart';
import 'package:magic_cli/src/commands/make_provider_command.dart';
import 'package:magic_cli/src/commands/make_middleware_command.dart';
import 'package:magic_cli/src/commands/make_enum_command.dart';
import 'package:magic_cli/src/commands/make_event_command.dart';
import 'package:magic_cli/src/commands/make_listener_command.dart';
import 'package:magic_cli/src/commands/make_request_command.dart';

void main(List<String> arguments) async {
  final kernel = Kernel();

  // Register commands
  kernel.register(KeyGenerateCommand());
  kernel.register(MakeMigrationCommand());
  kernel.register(MakeModelCommand());
  kernel.register(MakeViewCommand());
  kernel.register(MakeControllerCommand());
  kernel.register(MakePolicyCommand());
  kernel.register(MakeLangCommand());
  kernel.register(MakeSeederCommand());
  kernel.register(MakeFactoryCommand());
  kernel.register(InstallCommand());
  kernel.register(MakeProviderCommand());
  kernel.register(MakeMiddlewareCommand());
  kernel.register(MakeEnumCommand());
  kernel.register(MakeEventCommand());
  kernel.register(MakeListenerCommand());
  kernel.register(MakeRequestCommand());

  // Handle arguments
  await kernel.handle(arguments);
}
