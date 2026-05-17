class StringHelper {
  /// Converts string to PascalCase
  static String toPascalCase(String input) {
    if (input.isEmpty) return '';

    // First convert from camelCase or PascalCase to snake_case if needed
    final snakeCase = toSnakeCase(input);

    // Then split by underscore and capitalize each part
    final parts = snakeCase.split('_');
    return parts.map((part) {
      if (part.isEmpty) return '';
      return part[0].toUpperCase() + part.substring(1).toLowerCase();
    }).join('');
  }

  /// Converts string to snake_case
  static String toSnakeCase(String input) {
    if (input.isEmpty) return '';

    // Replace hyphens and spaces with underscores
    String snake = input.replaceAll(RegExp(r'[-\s]+'), '_');

    // Insert underscore before capital letters (unless it's the first letter or already preceded by an underscore)
    snake = snake.replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (match) {
      return '_${match.group(1)}';
    });

    return snake.toLowerCase();
  }

  /// Converts string to camelCase
  static String toCamelCase(String input) {
    if (input.isEmpty) return '';

    final pascal = toPascalCase(input);
    return pascal[0].toLowerCase() + pascal.substring(1);
  }

  /// Converts a singular word to its plural form
  static String toPlural(String input) {
    if (input.isEmpty) return '';

    final lower = input.toLowerCase();

    // Exceptions
    switch (lower) {
      case 'person':
        return 'people';
      case 'child':
        return 'children';
      case 'man':
        return 'men';
      case 'woman':
        return 'women';
    }

    if (lower.endsWith('y') && !RegExp(r'[aeiou]y$').hasMatch(lower)) {
      return '${input.substring(0, input.length - 1)}ies';
    }

    if (lower.endsWith('s') ||
        lower.endsWith('x') ||
        lower.endsWith('z') ||
        lower.endsWith('ch') ||
        lower.endsWith('sh')) {
      return '${input}es';
    }

    return '${input}s';
  }

  /// Parse nested name into components
  static ({String directory, String className, String fileName}) parseName(
      String input) {
    if (input.isEmpty) {
      return (directory: '', className: '', fileName: '');
    }

    final parts = input.split('/');
    final className = parts.last;

    final directory = parts.length > 1
        ? parts
            .sublist(0, parts.length - 1)
            .map((p) => toSnakeCase(p))
            .join('/')
        : '';

    final fileName = toSnakeCase(className);

    return (directory: directory, className: className, fileName: fileName);
  }
}
