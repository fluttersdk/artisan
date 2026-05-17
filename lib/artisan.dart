/// fluttersdk_artisan — Symfony-Console-grade CLI framework for Dart + Flutter.
///
/// Single barrel entry. Consumers import via `package:fluttersdk_artisan/artisan.dart`
/// and gain access to the full public API surface (Application + Command + Input/Output
/// + ServiceProvider + Context + VmServiceClient + StateFile + Stub system + Helpers).
///
/// 16 make:* commands from magic_cli are NOT carried here — they live in the
/// `magic` package as `MagicArtisanProvider`. fluttersdk_artisan is framework-agnostic.
library;

// Re-exports for CLI plugins.
export 'package:args/args.dart';

// Console: Application + Command base + boot mode + I/O + context + service provider + registry + collision.
export 'src/console/artisan_application.dart';
export 'src/console/artisan_command.dart';
export 'src/console/artisan_command_collision_exception.dart';
export 'src/console/artisan_context.dart';
export 'src/console/artisan_generator_command.dart';
export 'src/console/artisan_input.dart';
export 'src/console/artisan_output.dart';
export 'src/console/artisan_registry.dart';
export 'src/console/artisan_service_provider.dart';
export 'src/console/command_boot.dart';
export 'src/console/command_signature.dart';
export 'src/console/pid_parser.dart';
export 'src/console/process_alive.dart';
export 'src/console/prompt.dart';
export 'src/console/shell_quote.dart';
export 'src/console/string_helper.dart';

// Helpers (ported as-is from magic_cli).
export 'src/helpers/config_editor.dart';
export 'src/helpers/console_style.dart';
export 'src/helpers/env_editor.dart';
export 'src/helpers/file_helper.dart';
export 'src/helpers/gradle_editor.dart';
export 'src/helpers/html_editor.dart';
export 'src/helpers/json_editor.dart';
export 'src/helpers/main_dart_editor.dart';
export 'src/helpers/platform_helper.dart';
export 'src/helpers/podfile_editor.dart';
export 'src/helpers/route_registry_editor.dart';
export 'src/helpers/xml_editor.dart';
export 'src/helpers/plist_writer.dart';

// State + VM Service + extension registration (substrate ported from ai-test).
export 'src/extensions/register_extension_idempotent.dart';
export 'src/state/state_file.dart';
export 'src/stubs/stub_loader.dart';
export 'src/vm/vm_service_client.dart';

// Builtin commands (ship with artisan; consumer bin/artisan.dart registers them
// alongside ArtisanServiceProvider commands from the consumer's appConfig).
export 'src/commands/commands_index_writer.dart';
export 'src/commands/commands_refresh_command.dart';
export 'src/commands/doctor_command.dart';
export 'src/commands/help_command.dart';
export 'src/commands/hot_restart_command.dart';
export 'src/commands/list_command.dart';
export 'src/commands/logs_command.dart';
export 'src/commands/make_command_command.dart';
export 'src/commands/plugin_install_command.dart';
export 'src/commands/reload_command.dart';
export 'src/commands/restart_command.dart';
export 'src/commands/start_command.dart';
export 'src/commands/status_command.dart';
export 'src/commands/stop_command.dart';
export 'src/commands/tinker_command.dart';

// Installer DSL: typed exceptions + driver abstractions + DI container + FS + operation taxonomy.
export 'src/installer/conflict_detector.dart';
export 'src/installer/dry_run_renderer.dart';
export 'src/installer/install_context.dart';
export 'src/installer/install_exception.dart';
export 'src/installer/install_operation.dart';
export 'src/installer/install_transaction.dart';
export 'src/installer/prompt_driver.dart';
export 'src/installer/stub_driver.dart';
export 'src/installer/virtual_fs.dart';

// Tinker REPL hooks. Integration packages populate
// `Tinker.autocompleteCorpus / classAliases / casters` in their host-side
// install entry to enrich the REPL output for that ecosystem (Magic ships
// MagicTinkerIntegration which seeds ~30 facade symbols + Eloquent caster).
export 'src/tinker/tinker.dart';
export 'src/tinker/tinker_formatter.dart';
