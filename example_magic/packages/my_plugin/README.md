# my_plugin

A fluttersdk_artisan plugin.

## Install

```bash
# In your Flutter app:
dart pub add my_plugin
dart run fluttersdk_artisan plugin:install my_plugin
```

## Commands

- `artisan my_plugin:install`, install my_plugin
- `artisan my_plugin:uninstall`, uninstall my_plugin

## Authoring

Edit `install.yaml` to declare what gets published, injected, and configured.
Edit `lib/src/commands/install_command.dart` for procedural overrides.

See the [fluttersdk_artisan plugin authoring guide](https://artisan.fluttersdk.com/plugins).
