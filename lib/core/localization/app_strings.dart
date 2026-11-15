import 'package:flutter/widgets.dart';

String tr(BuildContext context, String arabic, String english) {
  return Localizations.localeOf(context).languageCode == 'ar'
      ? arabic
      : english;
}

String currencyName(String code, BuildContext context) {
  return switch (code) {
    'YER' => tr(context, 'ريال يمني', 'Yemeni Rial'),
    'SAR' => tr(context, 'ريال سعودي', 'Saudi Riyal'),
    'USD' => tr(context, 'دولار أمريكي', 'US Dollar'),
    _ => code,
  };
}
