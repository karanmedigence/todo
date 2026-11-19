String? validateName(String? value) {
  if ((value ?? '').trim().length < 2) {
    return 'Enter a name with at least 2 characters.';
  }
  return null;
}

String? validateEmail(String? value) {
  final email = (value ?? '').trim();
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email address.';
  }
  return null;
}

String? validatePassword(String? value) {
  if ((value ?? '').length < 8) {
    return 'Password must be at least 8 characters.';
  }
  return null;
}
