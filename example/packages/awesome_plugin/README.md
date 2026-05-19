# awesome_plugin

A fluttersdk_artisan plugin.

## Install

```bash
# In your Flutter app:
dart pub add awesome_plugin
dart run fluttersdk_artisan plugin:install awesome_plugin
```

## Commands

- `artisan awesome_plugin:install`, install awesome_plugin
- `artisan awesome_plugin:uninstall`, uninstall awesome_plugin

## Authoring

Edit `install.yaml` to declare what gets published, injected, and configured.
Edit `lib/src/commands/install_command.dart` for procedural overrides.

See the [fluttersdk_artisan plugin authoring guide](https://artisan.fluttersdk.com/plugins).
