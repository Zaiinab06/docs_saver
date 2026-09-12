class AppStrings {
  AppStrings._();

  // App & Header
  static const String appName = 'Second Brain';
  static const String authWelcomeTitle = 'Welcome to Second Brain';
  static const String authWelcomeSubtitle =
      'Capture, connect, and recall your thoughts effortlessly.';

  // Tabs & Buttons
  static const String signInTab = 'Sign In';
  static const String signUpTab = 'Sign Up';
  static const String signInButton = 'Sign In';
  static const String signUpButton = 'Create Account';

  // Form Field Labels
  static const String nameLabel = 'Full Name';
  static const String emailLabel = 'Email Address';
  static const String passwordLabel = 'Password';

  // Form Field Hints
  static const String nameHint = 'Enter your name';
  static const String emailHint = 'name@example.com';
  static const String passwordHintSignIn = 'Enter your password';
  static const String passwordHintSignUp =
      'Create a password (min 6 characters)';

  // Navigation / Toggle Prompts
  static const String dontHaveAccount = "Don't have an account? ";
  static const String alreadyHaveAccount = "Already have an account? ";

  // Form Validations
  static const String validationEmptyName = 'Please enter your name';
  static const String validationEmptyEmail = 'Please enter your email';
  static const String validationInvalidEmail =
      'Please enter a valid email address';
  static const String validationEmptyPassword = 'Please enter your password';
  static const String validationShortPassword =
      'Password must be at least 6 characters';
}
